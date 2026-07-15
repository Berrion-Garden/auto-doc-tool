# SourceParser

## Class: `AutoDoc::Analyzer::SourceParser`

**File:** `lib/auto_doc/analyzer/source_parser.rb`

### Purpose

Parses Ruby source files using Ripper.sexp to extract classes, modules, and method definitions. Returns structured analysis data without requiring external dependencies. Uses Ripper's S-expression AST output.

### Nested Struct

```ruby
Definition = Struct.new(:name, :type, :line, :parent_modules, :methods) do
  def to_h
    {
      name:           name,
      type:           type,
      line:           line,
      parent_modules: parent_modules.dup,
      methods:        methods.map(&:to_h)
    }
  end
end
```

Fields:
- `name` — Symbol/class name or method name
- `type` — `:class`, `:module`, `:method`, `:top_level`, `:class_body`, `:module_body`
- `line` — Line number where the definition starts
- `parent_modules` — Array of ancestor module names (for nested classes like `Outer::Inner`)
- `methods` — Array of method hashes `{name:, type: :method, line:}`

### API

```ruby
# Class method: entry point
definitions = SourceParser.parse_file("/path/to/file.rb")
# Returns: Array<Hash> — parsed definitions

# Instance method (rarely used directly)
parser = SourceParser.new(file_path)
definitions = parser.parse
```

### S-Expression Walking

The `walk_sexp` method recursively traverses the Ripper AST:

| S-Expression Type | Action |
|-------------------|--------|
| `:program` | Creates top-level scope, walks children, concatenates methods |
| `:class` | Extracts name, line, parent class; creates body scope; records definition |
| `:module` | Extracts name, line; creates body scope with child_modules; records definition; walks body again for nested defs |
| `:def`, `:defs` | Extracts method name, line; adds to enclosing scope's methods or records as top-level |
| Other (`:sclass`, `:alias`, `:cdecl`, `:massign`, `:vasgn`, `:const_path_ref`) | Passed to `handle_top_level_node` or recursed into |

### Name Extraction

| Node Type | Extraction |
|-----------|------------|
| `:@const`, `:@ident` | Returns `node[1]` directly |
| `:const_ref` | Unwraps inner node and delegates |
| `:const_path_ref` | Resolves `::A::B` references by joining with `::` |
| `:const_path_field` | Same as `:const_path_ref` |

### Line Number Extraction

- `extract_line(node)` — Handles `:const_ref` wrapper, extracts from `node.last` array `[line, col]`.
- `extract_line_from_sexp(sexp)` — Extracts from `sexp.last` for `:def` nodes.

### Parse Flow

1. `parse_file` checks file exists, calls `new(path).parse`.
2. `new` reads file as UTF-8, parses via `Ripper.sexp`.
3. `parse` returns `[]` if `@sexp` is nil/not an Array.
4. Calls `walk_sexp(@sexp, Definition.new(nil, :top_level, 0, [], []))`.
5. Returns `@definitions.map(&:to_h)`.

### Template Data for Consumers

Each returned definition hash:

```ruby
{
  name: "MyClass",
  type: :class,
  line: 1,
  parent_modules: [],       # or ["OuterModule"] for nested
  methods: [
    { name: "my_method", type: :method, line: 5 },
    ...
  ]
}
```