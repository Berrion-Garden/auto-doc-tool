# ClassDiagramGenerator

## Class: `AutoDoc::Generator::ClassDiagramGenerator`

**File:** `lib/auto_doc/generator/class_diagram_generator.rb`

### Purpose

Generates a Mermaid classDiagram from class hierarchy data. Renders `templates/class_diagram_template.erb`.

### Pattern

Standard generator pattern: `TEMPLATES_DIR` + `DEFAULT_TEMPLATE` constants, `self.generate(...)` class method, instance `generate` with optional `output_path`, includes `TemplateHelper`.

### Constructor

```ruby
def initialize(title, class_hierarchy)
  @title = title
  @class_hierarchy = Array(class_hierarchy)
end
```

### API

```ruby
ClassDiagramGenerator.generate(title, class_hierarchy, output_path: nil)
# Returns: rendered mermaid markdown string
```

### Template Data

| Variable | Type | Source |
|----------|------|--------|
| `title` | String | Constructor arg |
| `classes` | Array<Hash> | Class records: `{name:, parent:, includes: [], extends: [], methods: []}` |
| `generated_at` | String | `Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")` |

### Private Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `render_template` | String | Sets up binding, renders ERB from `ENV.fetch("AUTO_DOC_TEMPLATE_CLASS_DIAGRAM", DEFAULT_TEMPLATE)` |

### Template Path

Overridable via `ENV["AUTO_DOC_TEMPLATE_CLASS_DIAGRAM"]`. Falls back to `templates/class_diagram_template.erb`.

### Usage

Called by `Orchestrator#build_class_hierarchy` which extracts class definitions, parent classes, includes, and methods from `analyses` data.