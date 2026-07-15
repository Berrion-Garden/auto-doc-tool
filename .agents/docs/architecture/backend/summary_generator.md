# SummaryGenerator

## Class: `AutoDoc::Generator::SummaryGenerator`

**File:** `lib/auto_doc/generator/summary_generator.rb`

### Purpose

Generates SUMMARY.md documentation for a Ruby directory. Renders `templates/summary_template.erb` with inferred purpose, key components, architecture pattern, and dependencies overview.

### Pattern

Same generator pattern as IndexGenerator:
- `TEMPLATES_DIR` and `DEFAULT_TEMPLATE` constants
- `self.generate(...)` class method → delegates to instance
- Instance `initialize(dir_name, analyses, config)` + `generate(output_path = nil)`
- Includes `TemplateHelper`

### API

```ruby
SummaryGenerator.generate(dir_name, analyses, config, output_path: nil)
# Returns: rendered markdown string
```

### Template Data

| Variable | Type | Source |
|----------|------|--------|
| `dir_name` | String | Constructor arg |
| `purpose` | String | `infer_purpose` — context-aware description from dir name |
| `key_components` | Array<Hash> | `extract_key_components` — top 20 classes/modules with summaries |
| `architecture_pattern` | String | `infer_architecture_pattern` — heuristic-based pattern detection |
| `dependencies_overview` | Array<Hash> | `build_dependencies_overview` — classified by type (local/path/stdlib) |
| `generated_at` | String | ISO timestamp |
| `AutoDoc::VERSION` | String | Gem version |

### Inference Logic

#### `infer_purpose`

Built-in mappings for common directories:
- `lib` → "Core library code containing the primary implementation files."
- `app` → "Application code including controllers, models, services, and views."
- `spec`, `test` → "Test and specification files for verifying application behavior."
- `bin`, `exe` → "Executable entry points and command-line interface scripts."
- `config` → "Configuration files for environment, routing, and application setup."
- `db`, `migrate` → "Database migration files and schema definitions."
- `docs` → "Documentation files and supplementary project references."
- else → "#{DirName} module (N file(s))."

#### `extract_key_components`

Builds doc lookup index from YARD data, extracts classes and modules with summaries. Limits to top 20 to keep summary concise.

#### `infer_architecture_pattern`

Heuristic-based detection from file names:
- Contains "controller"/"model"/"view" → MVC
- Contains "service"/"interactor" → Service-oriented
- Contains "serializer"/"representer" → Presentation-focused
- `lib` → Modular library
- else → Modular composition

#### `build_dependencies_overview`

Classifies imports into categories: `local` (starts with `.`), `path` (contains `/`), or `stdlib/gem`. Deduplicates by import path.

### Template Sections

1. **Purpose** — Inferred description
2. **Key Components** — Table of top 20 classes/modules with type and summary
3. **Architecture Pattern** — Inferred pattern description
4. **Dependencies Overview** — Table of dependencies classified by type
5. **Related Documents** — Links to INDEX.md and AGENTS.md

### Template Path

Overridable via `ENV["AUTO_DOC_TEMPLATE_SUMMARY"]`. Falls back to `templates/summary_template.erb`.