using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.ServiceModel;
using CcAlm.Core.Model;
using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Messages;
using Microsoft.Xrm.Sdk.Metadata;
using Microsoft.Xrm.Sdk.Query;

namespace CcAlm.XrmToolBox
{
    /// <summary>
    /// The engine's view of one environment, over an XrmToolBox connection (IOrganizationService).
    /// Maps SDK types to the engine's values and back, by each column's metadata type.
    /// </summary>
    public sealed class SdkDataverse : IDataverse
    {
        readonly IOrganizationService _service;
        readonly Dictionary<string, TableSchema> _schemas = new Dictionary<string, TableSchema>();
        readonly Dictionary<string, Dictionary<string, AttributeMetadata>> _attributes = new Dictionary<string, Dictionary<string, AttributeMetadata>>();

        public SdkDataverse(IOrganizationService service, string name, string url)
        {
            _service = service ?? throw new ArgumentNullException(nameof(service));
            Name = name;
            Url = (url ?? "").TrimEnd('/');
        }

        public string Name { get; }
        public string Url { get; }

        public TableSchema GetTableSchema(string logicalName)
        {
            if (_schemas.TryGetValue(logicalName, out var cached)) return cached;
            EntityMetadata m;
            try
            {
                m = ((RetrieveEntityResponse)_service.Execute(new RetrieveEntityRequest
                {
                    LogicalName = logicalName,
                    EntityFilters = EntityFilters.Entity | EntityFilters.Attributes | EntityFilters.Relationships,
                    RetrieveAsIfPublished = false,
                })).EntityMetadata;
            }
            catch (FaultException<OrganizationServiceFault> ex) when (IsMissingTable(ex))
            {
                return _schemas[logicalName] = TableSchema.Missing(logicalName);
            }

            var s = new TableSchema
            {
                LogicalName = logicalName, Exists = true,
                EntitySet = m.EntitySetName, PrimaryId = m.PrimaryIdAttribute, PrimaryName = m.PrimaryNameAttribute,
                Label = m.DisplayCollectionName?.UserLocalizedLabel?.Label ?? logicalName,
            };
            var attrs = new Dictionary<string, AttributeMetadata>(StringComparer.OrdinalIgnoreCase);
            foreach (var a in m.Attributes)
            {
                if (!string.IsNullOrEmpty(a.AttributeOf)) continue;   // name/yomi shadows of lookups and choices
                attrs[a.LogicalName] = a;
                var level = a.RequiredLevel?.Value;
                s.Attributes[a.LogicalName] = new AttributeInfo
                {
                    Name = a.LogicalName,
                    Type = a.AttributeType?.ToString() ?? "Virtual",
                    Read = a.IsValidForRead ?? false,
                    Create = a.IsValidForCreate ?? false,
                    Update = a.IsValidForUpdate ?? false,
                    Required = level == AttributeRequiredLevel.ApplicationRequired || level == AttributeRequiredLevel.SystemRequired,
                    Label = a.DisplayName?.UserLocalizedLabel?.Label ?? a.LogicalName,
                };
            }
            foreach (var r in m.ManyToManyRelationships ?? new ManyToManyRelationshipMetadata[0])
                s.ManyToMany.Add(new ManyToManyInfo
                {
                    SchemaName = r.SchemaName, Entity1 = r.Entity1LogicalName, Entity2 = r.Entity2LogicalName, IntersectEntity = r.IntersectEntityName,
                    Entity1Attribute = r.Entity1IntersectAttribute, Entity2Attribute = r.Entity2IntersectAttribute,
                });
            foreach (var r in m.ManyToOneRelationships ?? new OneToManyRelationshipMetadata[0])
            {
                if (!s.Lookups.TryGetValue(r.ReferencingAttribute, out var lk)) s.Lookups[r.ReferencingAttribute] = lk = new LookupInfo { Column = r.ReferencingAttribute };
                if (!lk.Targets.Contains(r.ReferencedEntity)) lk.Targets.Add(r.ReferencedEntity);
                lk.Nav[r.ReferencedEntity] = r.ReferencingEntityNavigationPropertyName;
            }
            _attributes[logicalName] = attrs;
            return _schemas[logicalName] = s;
        }

        static bool IsMissingTable(FaultException<OrganizationServiceFault> ex) =>
            ex.Detail?.ErrorCode == -2147217150 || (ex.Message ?? "").IndexOf("Could not find", StringComparison.OrdinalIgnoreCase) >= 0
            || (ex.Message ?? "").IndexOf("does not exist", StringComparison.OrdinalIgnoreCase) >= 0;

        public IList<Record> GetRecords(TableSchema schema, IEnumerable<string> columns, string whereColumn = null, object whereValue = null)
        {
            var query = new QueryExpression(schema.LogicalName)
            {
                ColumnSet = new ColumnSet(columns.ToArray()),
                PageInfo = new PagingInfo { Count = 5000, PageNumber = 1 },
            };
            if (whereColumn != null) query.Criteria.AddCondition(whereColumn, ConditionOperator.Equal, whereValue);
            var rows = new List<Record>();
            while (true)
            {
                var page = Call(() => _service.RetrieveMultiple(query));
                rows.AddRange(page.Entities.Select(ToRecord));
                if (!page.MoreRecords) break;
                query.PageInfo.PageNumber++;
                query.PageInfo.PagingCookie = page.PagingCookie;
            }
            return rows;
        }

        public Record Retrieve(TableSchema schema, Guid id, IEnumerable<string> columns)
        {
            try { return ToRecord(_service.Retrieve(schema.LogicalName, id, new ColumnSet(columns.ToArray()))); }
            catch (FaultException<OrganizationServiceFault> ex) when ((ex.Message ?? "").IndexOf("Does Not Exist", StringComparison.OrdinalIgnoreCase) >= 0) { return null; }
        }

        public Guid Create(TableSchema schema, IDictionary<string, object> values) => Call(() => _service.Create(ToEntity(schema, Guid.Empty, values)));

        public void Update(TableSchema schema, Guid id, IDictionary<string, object> values) => Call(() => { _service.Update(ToEntity(schema, id, values)); return 0; });

        public void Delete(TableSchema schema, Guid id) => Call(() => { _service.Delete(schema.LogicalName, id); return 0; });

        public void Associate(ManyToManyInfo relationship, Guid id1, Guid id2) => Call(() =>
        {
            _service.Associate(relationship.Entity1, id1, new Relationship(relationship.SchemaName), new EntityReferenceCollection { new EntityReference(relationship.Entity2, id2) });
            return 0;
        });

        public void Disassociate(ManyToManyInfo relationship, Guid id1, Guid id2) => Call(() =>
        {
            _service.Disassociate(relationship.Entity1, id1, new Relationship(relationship.SchemaName), new EntityReferenceCollection { new EntityReference(relationship.Entity2, id2) });
            return 0;
        });

        static T Call<T>(Func<T> f)
        {
            try { return f(); }
            catch (FaultException<OrganizationServiceFault> ex) { throw new DataverseException(ex.Detail?.Message ?? ex.Message, ex); }
            catch (FaultException ex) { throw new DataverseException(ex.Message, ex); }
        }

        // --- SDK values → engine values -------------------------------------------------------------

        static Record ToRecord(Entity e)
        {
            var r = new Record { Id = e.Id };
            foreach (var kv in e.Attributes) r.Values[kv.Key] = FromSdk(kv.Value);
            foreach (var kv in e.FormattedValues) r.Formatted[kv.Key] = kv.Value;
            return r;
        }

        static object FromSdk(object v)
        {
            switch (v)
            {
                case null: return null;
                case EntityReference er: return new LookupValue(er.LogicalName, er.Id, er.Name);
                case OptionSetValue os: return os.Value;
                case OptionSetValueCollection many: return string.Join(",", many.Select(o => o.Value).OrderBy(x => x));
                case Money money: return money.Value;
                case AliasedValue al: return FromSdk(al.Value);
                default: return v;
            }
        }

        // --- engine values → SDK values, by the column's type ---------------------------------------

        Entity ToEntity(TableSchema schema, Guid id, IDictionary<string, object> values)
        {
            if (!_attributes.ContainsKey(schema.LogicalName)) GetTableSchema(schema.LogicalName);
            var attrs = _attributes[schema.LogicalName];
            var e = id == Guid.Empty ? new Entity(schema.LogicalName) : new Entity(schema.LogicalName, id);
            foreach (var kv in values)
            {
                attrs.TryGetValue(kv.Key, out var meta);
                e[kv.Key] = ToSdk(kv.Value, meta);
            }
            return e;
        }

        static object ToSdk(object v, AttributeMetadata meta)
        {
            if (v == null) return null;
            if (v is LookupValue lv) return new EntityReference(lv.Table, lv.Id);
            var type = meta?.AttributeType;
            var inv = CultureInfo.InvariantCulture;
            if (meta is MultiSelectPicklistAttributeMetadata)
            {
                var ints = Convert.ToString(v, inv).Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries).Select(s => new OptionSetValue(int.Parse(s.Trim(), inv)));
                return new OptionSetValueCollection(ints.ToList());
            }
            switch (type)
            {
                case AttributeTypeCode.Picklist:
                case AttributeTypeCode.State:
                case AttributeTypeCode.Status: return new OptionSetValue(Convert.ToInt32(v, inv));
                case AttributeTypeCode.Money: return new Money(Convert.ToDecimal(v, inv));
                case AttributeTypeCode.Integer: return Convert.ToInt32(v, inv);
                case AttributeTypeCode.BigInt: return Convert.ToInt64(v, inv);
                case AttributeTypeCode.Decimal: return Convert.ToDecimal(v, inv);
                case AttributeTypeCode.Double: return Convert.ToDouble(v, inv);
                case AttributeTypeCode.Boolean: return Convert.ToBoolean(v, inv);
                case AttributeTypeCode.DateTime:
                    return v is DateTime dt ? dt : DateTime.Parse(Convert.ToString(v, inv), inv, DateTimeStyles.RoundtripKind | DateTimeStyles.AdjustToUniversal);
                case AttributeTypeCode.Uniqueidentifier: return v is Guid g ? g : Guid.Parse(Convert.ToString(v, inv));
                case AttributeTypeCode.String:
                case AttributeTypeCode.Memo: return Convert.ToString(v, inv);
                default: return v;
            }
        }
    }
}
