# ArchitectureGenerator

## Class: `AutoDoc::Generator::ArchitectureGenerator`

**File:** `lib/auto_doc/generator/architecture_generator.rb`

### Purpose

Generates an architecture.md document from project analysis data. Renders `templates/architecture_template.erb` with sections for overview, architecture style, module map, data flow, design decisions, and diagram links.

### Pattern

Standard generator pattern: `TEMPLATES_DIR` + `DEFAULT_TEMPLATE` constants, `self.generate(...)` class method, instance `generate` with optional `output_path`, includes `TemplateHelper`.

### Constructor

```ruby
def initialize(project_name, schema_tables, models, class_hierarchy, config = {})
  @project_name   = project_name
  @schema_tables  = Array(schema_tables)
  @models         = Array(models)
  @class_hierarchy = Array(class_hierarchy)
  @config         = config
end
```

### API

```ruby
ArchitectureGenerator.generate(project_name, schema_tables, models, class_hierarchy, config = {}, output_path: nil)
# Returns: rendered markdown string
```

### Template Data

| Variable | Type | Source |
|----------|------|--------|
| `title` | String | `@project_name` |
| `overview` | String | `@config[:overview]` or `"No overview provided."` |
| `design_decisions` | Array | `@config[:design_decisions]` or `[]` |
| `diagram_links` | Array | `@config[:diagram_links]` or `[]` |
| `modules` | Array<Hash> | Derived from `@models`: `{name:, responsibility:}` (associations mapped to responsibility string, or "Core entity") |
| `architecture_style` | String | `@config[:architecture_style]` or `detect_architecture_style(modules.size)` |
| `data_flows` | Array<Hash> | Derived from model associations: `{from:, to:, description:}` |
| `generated_at` | String | `Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")` |

### `detect_architecture_style(module_count)`

Heuristic-based detection:
- ≤ 1 module → "Monolithic"
- ≤ 3 modules → "Modular Monolith"
- > 3 modules → "Microservices"

### `render_template`

1. Resolves template from `ENV.fetch("AUTO_DOC_TEMPLATE_ARCHITECTURE", DEFAULT_TEMPLATE)`.
2. Builds `modules` from model data — each model becomes a module entry with responsibility derived from associations.
3. Detects architecture style via `detect_architecture_style`.
4. Builds `data_flows` by iterating model associations and creating `{from:, to:, description: "X relationship"}` entries.
5. Renders ERB with all variables.

### Private Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `render_template` | String | Sets up binding, renders ERB |
| `detect_architecture_style(module_count)` | String | Heuristic-based architecture style detection |

### Template Path

Overridable via `ENV["AUTO_DOC_TEMPLATE_ARCHITECTURE"]`. Falls back to `templates/architecture_template.erb`.