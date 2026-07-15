# IndexGenerator

## Class: `AutoDoc::Generator::IndexGenerator`

**File:** `lib/auto_doc/generator/index_generator.rb`

### Purpose

Generates INDEX.md documentation for a Ruby directory. Renders `templates/index_template.erb` with analysis data including files table, symbols table, dependencies, and cross-references.

### Pattern

Follows the established generator pattern:
- `TEMPLATES_DIR` and `DEFAULT_TEMPLATE` constants
- `self.generate(...)` class method → delegates to instance
- Instance `initialize(dir_name, analyses, config)` + `generate(output_path = nil)`
- Includes `TemplateHelper` for `read_template`

### API

```ruby
IndexGenerator.generate(dir_name, analyses, config, output_path: nil)
# Returns: rendered markdown string

instance = IndexGenerator.new(dir_name, analyses, config)
instance.generate(output_path: "/path/to/INDEX.md")
# Returns: rendered markdown string, writes to disk if output_path given
```

### Parameters

| Param | Type | Description |
|-------|------|-------------|
| `dir_name` | String | Directory name (used as INDEX header) |
| `analyses` | Hash | `{ file_path => { definitions:, imports:, docs: } }` |
| `config` | AutoDoc::Config | Configuration object (passed to template) |
| `output_path` | String, nil | File path to write; nil = return string only |

### Template Data

The template receives:

| Variable | Type | Source |
|----------|------|--------|
| `dir_name` | String | Constructor arg |
| `files` | Array<Hash> | `build_files_table` — files with name, classes, modules, methods, documented |
| `symbols` | Array<Hash> | `build_symbols_table` — symbols with name, type, file, line, doc |
| `dependencies` | Array<Hash> | `build_dependencies` — from import data, with from, type, to |
| `cross_references` | Hash | `build_cross_references` — parent and sibling dirs with links |
| `coverage_pct` | Integer | `calculate_coverage` — % of documented symbols |
| `generated_at` | String | ISO timestamp |
| `AutoDoc::VERSION` | String | Gem version |

### Template Sections

1. **Header** — Directory name, version, file/symbol count, coverage %, timestamp
2. **Files table** — Numbered rows: name, classes, modules, methods, documented (✅/❌)
3. **Symbols table** — Alphabetical: name, type, file, line, documented
4. **Dependencies table** — From/type/to from import data
5. **Cross-References** — Parent dir link, sibling dir links

### Private Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `build_files_table` | Array<Hash> | Files with class/module/method counts and documented status |
| `build_symbols_table` | Array<Hash> | All symbols (class/module/method) sorted alphabetically |
| `build_dependencies` | Array<Hash> | Import dependencies deduplicated and sorted |
| `build_cross_references` | Hash | Parent and sibling directory links for cross-indexing |
| `calculate_coverage` | Integer | % of documented symbols (0-100) |

### Template Path

Overridable via `ENV["AUTO_DOC_TEMPLATE_INDEX"]`. Falls back to `templates/index_template.erb`.