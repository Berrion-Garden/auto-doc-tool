# ModelAssociationParser

## Class: `AutoDoc::Analyzer::ModelAssociationParser`

**File:** `lib/auto_doc/analyzer/model_association_parser.rb`

### Purpose

Parses Rails model files from `app/models/` to extract ActiveRecord associations (has_many, belongs_to, has_one, has_and_belongs_to_many) and their options. Used for architecture.md module mapping and ERD generation.

### Constants

```ruby
ASSOCIATION_TYPES = %w[has_many belongs_to has_one has_and_belongs_to_many].freeze
```

### Constructor

```ruby
def initialize(project_dir)
  @project_dir = project_dir
end
```

### API

```ruby
models = ModelAssociationParser.parse(project_dir)
# Returns: Array<Hash> — model definitions with associations
```

### Return Value

Each model hash:

```ruby
{
  model: "User",
  table: "users",
  associations: [
    { type: "has_many", target: "posts", options: {} },
    { type: "belongs_to", target: "company", options: { optional: true } }
  ]
}
```

### `parse`

1. Checks `app/models/` directory exists.
2. Glob's `app/models/*.rb` files.
3. For each file, calls `parse_model_file(path)` which returns a model hash or nil.
4. Returns filtered array (nils removed).

### `parse_model_file(path)`

1. Reads file as UTF-8, returns nil if empty.
2. Extracts model name via `extract_model_name`.
3. Extracts table name via `extract_table_name(content, model_name)`.
4. Extracts associations via `extract_associations(content)`.
5. Returns `{model:, table:, associations:}` hash.

### `extract_model_name(content)`

Regex: `\A\s*(?:class|module)\s+(\w+)`. Returns the first captured word.

### `extract_table_name(content, model_name)`

Priority order:
1. `self.table_name = "override"` override → returns the quoted string.
2. Standard Rails convention: CamelCase → snake_case + pluralize.
   - CamelCase split: `gsub(/([A-Z])/) { "_#{$1}" }.sub(/\A_/, "").downcase`
   - Basic pluralization:
     - `word + "s"` (default)
     - `word.sub(/y$/, "ies")` (ends with 'y')
     - `word + "es"` (ends with 's')

### `extract_associations(content)`

Line-by-line parsing:
- Matches `\A(has_many|belongs_to|has_one|has_and_belongs_to_many)\s+(?::(\w+)|"([^"]+)")`
- Extracts type, target (symbol or string), and options.
- Options parsed via `extract_options` which supports both inline hash `{ key: value }` and bare keyword arguments style.

### `extract_options(line)`

1. Finds comma-separated options after the association name via `,\s*(.*)`.
2. If options start with `{`, parses inline hash.
3. Otherwise, parses bare keyword arguments.
4. Returns `{key: parsed_value}` hash.

### `parse_option_value(value)`

Converts option string values to appropriate Ruby types:
- `true` → `true`
- `false` → `false`
- `:symbol` → `:symbol` (symbol)
- `"string"` → `string` (unquoted)
- Other → kept as string

### Edge Cases

- Only parses models in `app/models/` directory (not subdirectories).
- Simple pluralization — doesn't handle irregular English plurals (child→children, person→people).
- Association target can be a symbol (`:Company`) or string (`"Company"`).