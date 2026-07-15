# C4DiagramGenerator

## Class: `AutoDoc::Generator::C4DiagramGenerator`

**File:** `lib/auto_doc/generator/c4_diagram_generator.rb`

### Purpose

Generates C4 context and container Mermaid diagrams from project metadata. Supports two distinct templates: `c4_context_template.erb` (external systems and internal system) and `c4_container_template.erb` (internal modules and data flows).

### Pattern

Standard generator pattern with dual-template support: `TEMPLATES_DIR` + `CONTEXT_TEMPLATE` / `CONTAINER_TEMPLATE` constants, two class methods (`generate_context` / `generate_container`), instance `generate` with optional `output_path`, includes `TemplateHelper`.

### Constructor

```ruby
def initialize(template_key, title, **data)
  @template_key = template_key  # :context or :container
  @title = title
  @data = data
end
```

### API

```ruby
# Context diagram — external systems
C4DiagramGenerator.generate_context(title, external_systems, internal_system, output_path: nil)
# Returns: rendered mermaid markdown string

# Container diagram — internal modules
C4DiagramGenerator.generate_container(title, modules, data_flows, output_path: nil)
# Returns: rendered mermaid markdown string
```

### Template Data (Context)

| Variable | Type | Source |
|----------|------|--------|
| `title` | String | Constructor arg |
| `external_systems` | Array<Hash> | `{name:, interaction:}` |
| `internal_system` | Hash | `{name:}` |
| `modules` | Array | Always empty (`[]`) |
| `data_flows` | Array | Always empty (`[]`) |
| `generated_at` | String | `Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")` |

### Template Data (Container)

| Variable | Type | Source |
|----------|------|--------|
| `title` | String | Constructor arg |
| `external_systems` | Array | Always empty (`[]`) |
| `internal_system` | Hash | `{name: @title}` (defaults to title) |
| `modules` | Array<Hash> | `{name:, description:}` |
| `data_flows` | Array<Hash> | `{from:, to:, label:}` |
| `generated_at` | String | `Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")` |

### Template Paths

- **Context**: `ENV.fetch("AUTO_DOC_TEMPLATE_C4_CONTEXT", CONTEXT_TEMPLATE)` → `templates/c4_context_template.erb`
- **Container**: `ENV.fetch("AUTO_DOC_TEMPLATE_C4_CONTAINER", CONTAINER_TEMPLATE)` → `templates/c4_container_template.erb`

### Usage

Called by `Orchestrator#generate` which builds external system data from project structure and data flow data from cross-module imports via `build_container_data_flows`.