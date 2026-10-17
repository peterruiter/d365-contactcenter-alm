using System;
using System.Collections.Generic;

namespace CcAlm.Core.Model
{
    /// <summary>One column of a table, from the org's metadata.</summary>
    public sealed class AttributeInfo
    {
        public string Name { get; set; }
        /// <summary>The metadata AttributeType: String, Memo, Integer, Picklist, Lookup, Boolean...</summary>
        public string Type { get; set; }
        public bool Read { get; set; }
        public bool Create { get; set; }
        public bool Update { get; set; }
        public bool Required { get; set; }
        public string Label { get; set; }
    }

    /// <summary>A lookup column and the tables it can point at, with each one's navigation property.</summary>
    public sealed class LookupInfo
    {
        public string Column { get; set; }
        public List<string> Targets { get; } = new List<string>();
        public Dictionary<string, string> Nav { get; } = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    }

    /// <summary>A many-to-many relationship (a quick reply on several workstreams) and its intersect table.</summary>
    public sealed class ManyToManyInfo
    {
        public string SchemaName { get; set; }
        public string Entity1 { get; set; }
        public string Entity2 { get; set; }
        public string IntersectEntity { get; set; }
        public string Entity1Attribute { get; set; }
        public string Entity2Attribute { get; set; }
    }

    /// <summary>A table as one environment has it. Exists is false when the table is not installed.</summary>
    public sealed class TableSchema
    {
        public string LogicalName { get; set; }
        public bool Exists { get; set; }
        public string EntitySet { get; set; }
        public string PrimaryId { get; set; }
        public string PrimaryName { get; set; }
        public string Label { get; set; }
        public Dictionary<string, AttributeInfo> Attributes { get; } = new Dictionary<string, AttributeInfo>(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, LookupInfo> Lookups { get; } = new Dictionary<string, LookupInfo>(StringComparer.OrdinalIgnoreCase);
        public List<ManyToManyInfo> ManyToMany { get; } = new List<ManyToManyInfo>();

        public static TableSchema Missing(string logicalName) => new TableSchema { LogicalName = logicalName, Exists = false };
    }

    /// <summary>The value of a lookup: the record it points at.</summary>
    public sealed class LookupValue
    {
        public LookupValue(string table, Guid id, string name = null) { Table = table; Id = id; Name = name; }
        public string Table { get; }
        public Guid Id { get; }
        public string Name { get; }
        public override string ToString() => Id.ToString();
    }

    /// <summary>
    /// One record. Values are keyed by column logical name: plain values (string, int, long, decimal,
    /// double, bool, DateTime), a choice as its int value, a multi-select choice as "1,2", a lookup as a
    /// LookupValue under the lookup column's name. Formatted holds the values as Dataverse shows them.
    /// </summary>
    public sealed class Record
    {
        public Guid Id { get; set; }
        public Dictionary<string, object> Values { get; } = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, string> Formatted { get; } = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        public object Get(string column) => column != null && Values.TryGetValue(column, out var v) ? v : null;
        public LookupValue GetLookup(string column) => Get(column) as LookupValue;
        public bool Has(string column) => column != null && Values.ContainsKey(column);
        public bool IsManaged => Get("ismanaged") is bool b && b;

        public Record Clone()
        {
            var r = new Record { Id = Id };
            foreach (var kv in Values) r.Values[kv.Key] = kv.Value;
            foreach (var kv in Formatted) r.Formatted[kv.Key] = kv.Value;
            return r;
        }
    }

    /// <summary>A failed Dataverse call, with Dataverse's own message.</summary>
    public sealed class DataverseException : Exception
    {
        public DataverseException(string message, Exception inner = null) : base(message, inner) { }
    }

    /// <summary>
    /// What the engine needs from an environment. Implemented over IOrganizationService for XrmToolBox
    /// connections, and in memory for the tests.
    /// </summary>
    public interface IDataverse
    {
        /// <summary>What a person calls this environment ("Test").</summary>
        string Name { get; }
        /// <summary>The org URL; also what identifies the environment.</summary>
        string Url { get; }

        /// <summary>The table's columns and lookups. Exists = false when the table is not installed.</summary>
        TableSchema GetTableSchema(string logicalName);

        /// <summary>
        /// Every row of the table, with these columns (lookups by their column name). With
        /// whereColumn/whereValue only the rows where that column equals that value.
        /// </summary>
        IList<Record> GetRecords(TableSchema schema, IEnumerable<string> columns, string whereColumn = null, object whereValue = null);

        /// <summary>One row, or null when it does not exist.</summary>
        Record Retrieve(TableSchema schema, Guid id, IEnumerable<string> columns);

        /// <summary>Creates a row. Values as in Record.Values; a lookup as a LookupValue.</summary>
        Guid Create(TableSchema schema, IDictionary<string, object> values);

        /// <summary>Updates a row. A null value clears the column or lookup.</summary>
        void Update(TableSchema schema, Guid id, IDictionary<string, object> values);

        void Delete(TableSchema schema, Guid id);

        /// <summary>Links two records through a many-to-many relationship (record 1 is of the relationship's entity 1).</summary>
        void Associate(ManyToManyInfo relationship, Guid id1, Guid id2);

        void Disassociate(ManyToManyInfo relationship, Guid id1, Guid id2);
    }
}
