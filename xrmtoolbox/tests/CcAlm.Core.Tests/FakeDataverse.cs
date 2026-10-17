using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using CcAlm.Core.Model;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CcAlm.Core.Tests
{
    /// <summary>
    /// An in-memory Dataverse built from Web API JSON: EntityDefinitions responses (tests/fixtures/schema.json
    /// or a recording's metadata) and records as the Web API returns them. Strict where Dataverse is: a
    /// column that does not exist, a write to a column not valid for create or update, or a lookup to a
    /// record that does not exist fails.
    /// </summary>
    public sealed class FakeDataverse : IDataverse
    {
        readonly Dictionary<string, JObject> _metadata;
        readonly Dictionary<string, TableSchema> _schemas = new Dictionary<string, TableSchema>();
        public Dictionary<string, List<Record>> Rows { get; } = new Dictionary<string, List<Record>>();

        public FakeDataverse(string name, string url, Dictionary<string, JObject> metadata)
        {
            Name = name;
            Url = url;
            _metadata = metadata;
            foreach (var kv in metadata) if (kv.Value != null) Rows[kv.Key] = new List<Record>();
        }

        public string Name { get; }
        public string Url { get; }
        public List<(string Method, string Table, Guid Id, IDictionary<string, object> Values)> Writes { get; } = new List<(string, string, Guid, IDictionary<string, object>)>();
        public int MetadataReads { get; private set; }
        public int RecordReads { get; private set; }
        /// <summary>Return a message to make that write fail: (method, table, values) → message or null.</summary>
        public Func<string, string, IDictionary<string, object>, string> FailWhen { get; set; }
        /// <summary>Runs after a create or update is stored, like a plugin.</summary>
        public Action<string, string, Record> OnWrite { get; set; }
        /// <summary>Provision a routing contract on every new workstream, as Dataverse does.</summary>
        public bool ProvisionRoutingContract { get; set; }

        // --- Loading ------------------------------------------------------------------------------

        public static Dictionary<string, JObject> LoadMetadata(string path)
        {
            var raw = JObject.Parse(File.ReadAllText(path));
            return raw.Properties().ToDictionary(p => p.Name, p => p.Value.Type == JTokenType.Null ? null : (JObject)p.Value);
        }

        /// <summary>Records as the Web API returns them, keyed by entity set (a recording's *.records.json).</summary>
        public void LoadRecords(string path)
        {
            var raw = JObject.Parse(File.ReadAllText(path), new JsonLoadSettings());
            var bySet = _metadata.Where(kv => kv.Value != null).ToDictionary(kv => (string)kv.Value["EntitySetName"], kv => kv.Key);
            foreach (var p in raw.Properties())
            {
                if (!bySet.TryGetValue(p.Name, out var logical)) continue;
                var schema = GetSchemaInternal(logical);
                foreach (var row in (JArray)p.Value) Rows[logical].Add(FromWebApi((JObject)row, schema));
            }
        }

        static Record FromWebApi(JObject row, TableSchema schema)
        {
            var r = new Record();
            foreach (var prop in row.Properties())
            {
                var name = prop.Name;
                if (name.Contains("@")) continue;
                if (name.StartsWith("_", StringComparison.Ordinal) && name.EndsWith("_value", StringComparison.Ordinal))
                {
                    var col = name.Substring(1, name.Length - 7);
                    var v = (string)prop.Value;
                    r.Values[col] = string.IsNullOrEmpty(v) ? null
                        : new LookupValue((string)row[name + "@Microsoft.Dynamics.CRM.lookuplogicalname"], Guid.Parse(v), (string)row[name + "@OData.Community.Display.V1.FormattedValue"]);
                    continue;
                }
                r.Values[name] = Plain(prop.Value);
                var fv = row[name + "@OData.Community.Display.V1.FormattedValue"];
                if (fv != null && fv.Type != JTokenType.Null) r.Formatted[name] = (string)fv;
            }
            if (r.Get(schema.PrimaryId) is string id) r.Id = Guid.Parse(id);
            return r;
        }

        static object Plain(JToken t)
        {
            switch (t.Type)
            {
                case JTokenType.Null: case JTokenType.Undefined: return null;
                case JTokenType.Integer: return (long)t;
                case JTokenType.Float: return (double)t;
                case JTokenType.Boolean: return (bool)t;
                case JTokenType.Date: return ((DateTime)t).ToUniversalTime().ToString("o");
                default: return (string)t;
            }
        }

        // --- IDataverse ----------------------------------------------------------------------------

        public TableSchema GetTableSchema(string logicalName)
        {
            MetadataReads++;
            return GetSchemaInternal(logicalName);
        }

        TableSchema GetSchemaInternal(string logical)
        {
            if (_schemas.TryGetValue(logical, out var cached)) return cached;
            if (!_metadata.TryGetValue(logical, out var m) || m == null) return _schemas[logical] = TableSchema.Missing(logical);
            var s = new TableSchema
            {
                LogicalName = logical, Exists = true,
                EntitySet = (string)m["EntitySetName"], PrimaryId = (string)m["PrimaryIdAttribute"], PrimaryName = (string)m["PrimaryNameAttribute"],
                Label = (string)m.SelectToken("DisplayCollectionName.UserLocalizedLabel.Label") ?? logical,
            };
            foreach (JObject a in (JArray)m["Attributes"])
            {
                if (a["AttributeOf"] != null && a["AttributeOf"].Type != JTokenType.Null) continue;
                var name = (string)a["LogicalName"];
                var level = (string)a.SelectToken("RequiredLevel.Value");
                s.Attributes[name] = new AttributeInfo
                {
                    Name = name, Type = (string)a["AttributeType"],
                    Read = (bool?)a["IsValidForRead"] ?? false, Create = (bool?)a["IsValidForCreate"] ?? false, Update = (bool?)a["IsValidForUpdate"] ?? false,
                    Required = level == "ApplicationRequired" || level == "SystemRequired",
                    Label = (string)a.SelectToken("DisplayName.UserLocalizedLabel.Label") ?? name,
                };
            }
            foreach (JObject rel in (JArray)m["ManyToManyRelationships"] ?? new JArray())
                s.ManyToMany.Add(new ManyToManyInfo
                {
                    SchemaName = (string)rel["SchemaName"], Entity1 = (string)rel["Entity1LogicalName"], Entity2 = (string)rel["Entity2LogicalName"],
                    IntersectEntity = (string)rel["IntersectEntityName"], Entity1Attribute = (string)rel["Entity1IntersectAttribute"], Entity2Attribute = (string)rel["Entity2IntersectAttribute"],
                });
            foreach (JObject rel in (JArray)m["ManyToOneRelationships"])
            {
                var col = (string)rel["ReferencingAttribute"];
                if (!s.Lookups.TryGetValue(col, out var lk)) s.Lookups[col] = lk = new LookupInfo { Column = col };
                var target = (string)rel["ReferencedEntity"];
                if (!lk.Targets.Contains(target)) lk.Targets.Add(target);
                lk.Nav[target] = (string)rel["ReferencingEntityNavigationPropertyName"];
            }
            return _schemas[logical] = s;
        }

        public IList<Record> GetRecords(TableSchema schema, IEnumerable<string> columns, string whereColumn = null, object whereValue = null)
        {
            RecordReads++;
            var cols = columns.ToList();
            var real = GetSchemaInternal(schema.LogicalName);
            foreach (var c in cols.Concat(whereColumn == null ? new string[0] : new[] { whereColumn }))
                if (!real.Attributes.ContainsKey(c)) throw new DataverseException($"Could not find a property named '{c}' on type '{schema.LogicalName}'.");
            IEnumerable<Record> rows = Rows[schema.LogicalName];
            if (whereColumn != null) rows = rows.Where(r => Equals(Normal(r.Get(whereColumn)), Normal(whereValue)));
            return rows.Select(r => Project(r, cols, real)).ToList();
        }

        static object Normal(object v) => v is bool b ? (object)b : v?.ToString();

        static Record Project(Record r, List<string> cols, TableSchema schema)
        {
            var p = new Record { Id = r.Id };
            foreach (var c in cols)
            {
                p.Values[c] = r.Get(c);
                if (r.Formatted.TryGetValue(c, out var f)) p.Formatted[c] = f;
            }
            if (!p.Values.ContainsKey(schema.PrimaryId)) p.Values[schema.PrimaryId] = r.Id.ToString();
            return p;
        }

        public Record Retrieve(TableSchema schema, Guid id, IEnumerable<string> columns)
        {
            RecordReads++;
            var row = Find(schema.LogicalName, id);
            return row == null ? null : Project(row, columns.ToList(), GetSchemaInternal(schema.LogicalName));
        }

        public Guid Create(TableSchema schema, IDictionary<string, object> values)
        {
            Fail("Create", schema.LogicalName, values);
            var real = GetSchemaInternal(schema.LogicalName);
            var r = new Record { Id = Guid.NewGuid() };
            r.Values[real.PrimaryId] = r.Id.ToString();
            if (real.Attributes.ContainsKey("ismanaged")) r.Values["ismanaged"] = false;
            Apply(r, real, values, create: true);
            Rows[schema.LogicalName].Add(r);
            Writes.Add(("Create", schema.LogicalName, r.Id, values));
            OnWrite?.Invoke("Create", schema.LogicalName, r);

            if (ProvisionRoutingContract && schema.LogicalName == "msdyn_liveworkstream" && Rows.ContainsKey("msdyn_decisioncontract"))
            {
                var c = Add("msdyn_decisioncontract", new Dictionary<string, object> { ["msdyn_name"] = "new_" + Guid.NewGuid().ToString("N"), ["msdyn_uniquename"] = "new_" + Guid.NewGuid().ToString("N") });
                SetLookup(r, "msdyn_routingcontractid", "msdyn_decisioncontract", c);
            }
            return r.Id;
        }

        public void Update(TableSchema schema, Guid id, IDictionary<string, object> values)
        {
            Fail("Update", schema.LogicalName, values);
            var r = Find(schema.LogicalName, id) ?? throw new DataverseException($"{schema.LogicalName} With Id = {id} Does Not Exist");
            Apply(r, GetSchemaInternal(schema.LogicalName), values, create: false);
            Writes.Add(("Update", schema.LogicalName, id, values));
            OnWrite?.Invoke("Update", schema.LogicalName, r);
        }

        public void Delete(TableSchema schema, Guid id)
        {
            var r = Find(schema.LogicalName, id) ?? throw new DataverseException($"{schema.LogicalName} With Id = {id} Does Not Exist");
            Rows[schema.LogicalName].Remove(r);
            Writes.Add(("Delete", schema.LogicalName, id, null));
        }

        public void Associate(ManyToManyInfo m, Guid id1, Guid id2)
        {
            Fail("Associate", m.SchemaName, null);
            if (Find(m.Entity1, id1) == null) throw new DataverseException($"{m.Entity1} With Id = {id1} Does Not Exist");
            if (Find(m.Entity2, id2) == null) throw new DataverseException($"{m.Entity2} With Id = {id2} Does Not Exist");
            if (Links(m).Any(r => Same(r, m, id1, id2))) throw new DataverseException("Cannot insert duplicate key.");
            AddLink(m, id1, id2);
            Writes.Add(("Associate", m.SchemaName, id1, new Dictionary<string, object> { [m.Entity2Attribute] = id2 }));
        }

        public void Disassociate(ManyToManyInfo m, Guid id1, Guid id2)
        {
            var row = Links(m).FirstOrDefault(r => Same(r, m, id1, id2)) ?? throw new DataverseException("The association does not exist.");
            Rows[m.IntersectEntity].Remove(row);
            Writes.Add(("Disassociate", m.SchemaName, id1, new Dictionary<string, object> { [m.Entity2Attribute] = id2 }));
        }

        IEnumerable<Record> Links(ManyToManyInfo m) => Rows.TryGetValue(m.IntersectEntity, out var rows) ? rows : Enumerable.Empty<Record>();
        static bool Same(Record r, ManyToManyInfo m, Guid id1, Guid id2) =>
            string.Equals(r.Get(m.Entity1Attribute)?.ToString(), id1.ToString(), StringComparison.OrdinalIgnoreCase) &&
            string.Equals(r.Get(m.Entity2Attribute)?.ToString(), id2.ToString(), StringComparison.OrdinalIgnoreCase);

        void AddLink(ManyToManyInfo m, Guid id1, Guid id2)
        {
            var schema = GetSchemaInternal(m.IntersectEntity);
            var r = new Record { Id = Guid.NewGuid() };
            r.Values[schema.PrimaryId] = r.Id.ToString();
            r.Values[m.Entity1Attribute] = id1.ToString();
            r.Values[m.Entity2Attribute] = id2.ToString();
            Rows[m.IntersectEntity].Add(r);
        }

        /// <summary>Links two records directly, for building test data.</summary>
        public void Link(string schemaName, Guid id1, Guid id2)
        {
            var m = _metadata.Keys.Select(GetSchemaInternal).Where(s => s.Exists).SelectMany(s => s.ManyToMany).First(x => x.SchemaName == schemaName);
            AddLink(m, id1, id2);
        }

        void Fail(string method, string table, IDictionary<string, object> values)
        {
            var msg = FailWhen?.Invoke(method, table, values);
            if (msg != null) throw new DataverseException(msg);
        }

        void Apply(Record r, TableSchema schema, IDictionary<string, object> values, bool create)
        {
            foreach (var kv in values)
            {
                if (!schema.Attributes.TryGetValue(kv.Key, out var a)) throw new DataverseException($"'{schema.LogicalName}' entity doesn't contain attribute with Name = '{kv.Key}'.");
                if (create && !a.Create) throw new DataverseException($"Field '{kv.Key}' is not valid for create.");
                if (!create && !a.Update) throw new DataverseException($"Field '{kv.Key}' is not valid for update.");
                if (kv.Value is LookupValue lv)
                {
                    if (!schema.Lookups.TryGetValue(kv.Key, out var lk) || !lk.Targets.Contains(lv.Table)) throw new DataverseException($"'{kv.Key}' cannot point at a {lv.Table}.");
                    if (Find(lv.Table, lv.Id) == null) throw new DataverseException($"{lv.Table} With Id = {lv.Id} Does Not Exist");
                    SetLookup(r, kv.Key, lv.Table, lv.Id);
                    continue;
                }
                r.Values[kv.Key] = kv.Value;
                r.Formatted.Remove(kv.Key);   // the label read back belonged to the old value
            }
        }

        // --- Building test data ----------------------------------------------------------------------

        public Record Find(string table, Guid id) => Rows.TryGetValue(table, out var rows) ? rows.FirstOrDefault(r => r.Id == id) : null;

        public void SetLookup(Record r, string column, string table, Guid id)
        {
            if (id == Guid.Empty) { r.Values[column] = null; return; }
            var target = Find(table, id);
            var schema = GetSchemaInternal(table);
            r.Values[column] = new LookupValue(table, id, target?.Get(schema.PrimaryName) as string);
        }

        /// <summary>Puts a record straight in, for building test data. Lookups as column → id.</summary>
        public Guid Add(string table, IDictionary<string, object> values, IDictionary<string, Guid> lookups = null, bool managed = false, Guid? id = null)
        {
            var schema = GetSchemaInternal(table);
            if (!schema.Exists) throw new InvalidOperationException($"The fake has no table {table}.");
            var r = new Record { Id = id ?? Guid.NewGuid() };
            r.Values[schema.PrimaryId] = r.Id.ToString();
            if (schema.Attributes.ContainsKey("ismanaged")) r.Values["ismanaged"] = managed;
            foreach (var kv in values)
            {
                if (!schema.Attributes.ContainsKey(kv.Key)) throw new InvalidOperationException($"Table {table} has no column {kv.Key}.");
                r.Values[kv.Key] = kv.Value;
            }
            foreach (var kv in lookups ?? new Dictionary<string, Guid>())
            {
                if (!schema.Lookups.TryGetValue(kv.Key, out var lk)) throw new InvalidOperationException($"Table {table} has no lookup {kv.Key}.");
                var target = lk.Targets.FirstOrDefault(t => Find(t, kv.Value) != null) ?? lk.Targets[0];
                SetLookup(r, kv.Key, target, kv.Value);
            }
            Rows[table].Add(r);
            return r.Id;
        }

        /// <summary>A deep copy under another URL, to keep the before state of a target that is then written to.</summary>
        public FakeDataverse Copy(string url)
        {
            var c = new FakeDataverse(Name + " (before)", url, _metadata) { ProvisionRoutingContract = ProvisionRoutingContract };
            foreach (var kv in Rows) c.Rows[kv.Key] = kv.Value.Select(r => r.Clone()).ToList();
            return c;
        }

        public IEnumerable<Record> Where(string table, string column, object value) =>
            Rows[table].Where(r => Equals(Normal(r.Get(column)), Normal(value)));
    }
}
