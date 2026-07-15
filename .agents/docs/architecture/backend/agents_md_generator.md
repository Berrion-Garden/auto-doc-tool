# AgentsMdGenerator

## Class: `AutoDoc::Generator::AgentsMdGenerator`

**File:** `lib/auto_doc/generator/agents_md_generator.rb`

### Purpose

Generates AGENTS.md documentation for a Ruby module directory. Renders `templates/agents_md_template.erb` with file analysis data. This is the primary output — each module root (e.g., `lib/`, `app/`) gets its own AGENTS.md.

### Pattern

Standard generator pattern: `TEMPLATES_DIR` + `DEFAULT_TEMPLATE` constants, `self.generate(...)` class method, instance `generate` with optional `output_path`, includes `TemplateHelper`.

### Constructor

```ruby
def initialize(module_name, tree_text, files)
  @module_name = module_name
  @tree_text   = tree_text
  @files       = files
end
```

### API

```ruby
AgentsMdGenerator.generate(module_name, tree_text, files, output_path: nil)
# Returns: rendered markdown string
```

### Template Data

The template receives variables via `binding`:

| Variable | Type | Source |
|----------|------|--------|
| `module_name` | String | Constructor arg |
| `tree_text` | String | Directory tree representation |
| `files` | Array<Hash> | File analysis records: `{name:, path:, classes:[], imports:[]}` |
| `source_file_count` | Integer | `files.size` |
| `public_symbols` | Array<Hash> | `build_public_symbols` — extracted from files, sorted |
| `public_symbol_count` | Integer | `public_symbols.size` |
| `purpose_summary` | Nil | Always nil (no auto-inference) |
| `dependencies` | Array | Always empty (no extraction) |
| `generated_at` | String | `Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")` |

### `build_public_symbols(files)`

Extracts public symbols from file analysis records:
1. Iterates `files` array.
2. For each file, iterates `:classes` (supports both `Hash` and `Array` elements).
3. Filters to `:class`, `:module`, `:method` types only.
4. Builds `{name:, type:, line:, has_doc?:}` entries.
5. Sorts alphabetically by name (case-insensitive).

### Private Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `render_template` | String | Sets up binding variables, renders ERB from `ENV.fetch("AUTO_DOC_TEMPLATE", DEFAULT_TEMPLATE)` |
| `build_public_symbols(files)` | Array<Hash> | Extracts and sorts class/module/method symbols from files |

### Template Path

Overridable via `ENV["AUTO_DOC_TEMPLATE"]`. Falls back to `templates/agents_md_template.erb`.