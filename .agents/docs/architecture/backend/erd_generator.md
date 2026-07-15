# ERDGenerator

## Class: `AutoDoc::Generator::ERDGenerator`

**File:** `lib/auto_doc/generator/erd_generator.rb`

### Purpose

Generates a Mermaid erDiagram from Rails schema table and relationship data. Renders `templates/erd_template.erb`. Only generated for Rails projects (when schema.rb exists).

### Pattern

Standard generator pattern: `TEMPLATES_DIR` + `DEFAULT_TEMPLATE` constants, `self.generate(...)` class method, instance `generate` with optional `output_path`, includes `TemplateHelper`.

### Constructor

```ruby
def initialize(title, tables, relationships = [])
  @title         = title
  @tables        = Array(tables)
  @relationships = Array(relationships)
end
```

### API

```ruby
ERDGenerator.generate(title, tables, relationships, output_path: nil)
# Returns: rendered mermaid markdown string
```

### Template Data

| Variable | Type | Source |
|----------|------|--------|
| `title` | String | Constructor arg |
| `tables` | Array<Hash> | Table records: `{name:, columns: [{name:, type:, pk:, fk:, null:}]}` |
| `relationships` | Array<Hash> | Relationship records: `{from:, to:, cardinality_from:, cardinality_to:, label:}` |
| `generated_at` | String | `Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")` |

### Private Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `render_template` | String | Sets up binding, renders ERB from `ENV.fetch("AUTO_DOC_TEMPLATE_ERD", DEFAULT_TEMPLATE)` |

### Template Path

Overridable via `ENV["AUTO_DOC_TEMPLATE_ERD"]`. Falls back to `templates/erd_template.erb`.

### Usage

Called by `Orchestrator#generate` when Rails is detected (has `db/schema.rb`). Tables come from `SchemaParser`, relationships from `Orchestrator#build_erd_relationships` which maps association types to cardinality notation.