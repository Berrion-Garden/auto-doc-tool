# SchemaParser

## Class: `AutoDoc::Analyzer::SchemaParser`

**File:** `lib/auto_doc/analyzer/schema_parser.rb`

### Purpose

Parses Rails `db/schema.rb` and `db/migrate/` to extract table schemas, column definitions, indexes, foreign keys, and migration timestamps. Used for ERD generation in Rails projects.

### Constructor

```ruby
def initialize(project_dir)
  @project_dir = project_dir
end
```

### API

```ruby
tables = SchemaParser.parse(project_dir)
# Returns: Array<Hash> — table definitions

# Instance method
tables = SchemaParser.new(project_dir).parse
# Returns: Array<Hash>
```

### Return Value

Each table hash:

```ruby
{
  table_name:           "users",
  columns:              [{ name: "id", type: "integer", null: false, default: nil }, ...],
  indexes:              [{ name: "index_users_email", columns: ["email"] }],
  foreign_keys:         [{ from_table: "posts", to_table: "users", column: "user_id" }],
  migration_timestamps: ["20260101120000", ...]
}
```

### `parse`

1. Checks `db/schema.rb` exists and is non-empty.
2. Parses tables via `parse_tables(content)`.
3. Parses foreign keys via `parse_foreign_keys!(content, tables)`.
4. Extracts migration timestamps via `migration_timestamps`.
5. Adds migration timestamps to each table hash.
6. Returns tables array.

### `parse_tables(content)`

Line-by-line parsing of `schema.rb`:

- `create_table "tablename"` → starts a new table record
- `end` → closes current table record
- Column lines matching `\At\.(string|integer|datetime|boolean|text|bigint|float|decimal|date|time|binary)\s+` → extracted as `{name:, type:, null:, default:}`
- Index lines matching `\At\.index\s+\["col"\](?:,\s*name:\s+"name")?` → extracted as `{name:, columns:}`

Supported column types: `string`, `integer`, `datetime`, `boolean`, `text`, `bigint`, `float`, `decimal`, `date`, `time`, `binary`.

### `parse_foreign_keys!(content, tables)`

Post-processing pass over schema content:
- Matches `\Aadd_foreign_key\s+"from",\s+"to"` patterns.
- Infers FK column name: singularize `to_table` + `_id` (if `to_table` ends with 's', strips it).
- Adds to the `from_table`'s `foreign_keys` array.

### `migration_timestamps`

Scans `db/migrate/*.rb` files, extracts 14-digit timestamp prefixes from filenames (e.g., `20260101120000_create_users.rb`), returns sorted array.

### Edge Cases

- Skips empty lines and comment lines in schema.
- Handles both quoted (`"column"`) and symbol (`:column`) column names.
- Extracts `default:` value via regex `\bdefault:\s+([^,\s]+)`.
- Foreign key column name inference is heuristic (singularize by stripping trailing 's').