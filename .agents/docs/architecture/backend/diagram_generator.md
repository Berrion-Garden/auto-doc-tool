# DiagramGenerator

## Class: `AutoDoc::Generator::DiagramGenerator`

**File:** `lib/auto_doc/generator/diagram_generator.rb`

### Purpose

Generates a Mermaid dependency DAG diagram (`deps.mmd`) from import analysis data. Renders `templates/diagram_dag_template.erb`.

### Pattern

Standard generator pattern: `TEMPLATES_DIR` + `DEFAULT_TEMPLATE` constants, `self.generate(...)` class method, instance `generate` with optional `output_path`, includes `TemplateHelper`.

### Constructor

```ruby
def initialize(title, graph_nodes, graph_edges)
  @title       = title
  @graph_nodes = Array(graph_nodes)
  @graph_edges = Array(graph_edges)
end
```

### API

```ruby
DiagramGenerator.generate(title, graph_nodes, graph_edges, output_path: nil)
# Returns: rendered mermaid markdown string
```

### Template Data

| Variable | Type | Source |
|----------|------|--------|
| `title` | String | Constructor arg |
| `graph_nodes` | Array<String> | Node labels (file paths or names) |
| `graph_edges` | Array<Hash> | Edge records: `{from:, to:, type:}` |
| `generated_at` | String | `Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")` |

### Private Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `render_template` | String | Sets up binding, renders ERB from `ENV.fetch("AUTO_DOC_TEMPLATE_DIAGRAM", DEFAULT_TEMPLATE)` |

### Template Path

Overridable via `ENV["AUTO_DOC_TEMPLATE_DIAGRAM"]`. Falls back to `templates/diagram_dag_template.erb`.

### Usage

Called by `Orchestrator#build_graph_data` which extracts nodes and edges from `analyses` data (definitions and imports per file).