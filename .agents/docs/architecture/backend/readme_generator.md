# ReadmeGenerator

## Class: `AutoDoc::Generator::ReadmeGenerator`

**File:** `lib/auto_doc/generator/readme_generator.rb`

### Purpose

Generates README.md at the project level. Renders `templates/readme_template.erb` with project structure and summary statistics.

### Pattern

Standard generator pattern: `TEMPLATES_DIR` + `DEFAULT_TEMPLATE` constants, `self.generate(...)` class method, instance `generate` with optional `output_path`, includes `TemplateHelper`.

### Constructor

```ruby
def initialize(project_name, structure, summary_stats = {})
  @project_name  = project_name
  @structure     = structure
  @summary_stats = summary_stats
end
```

### API

```ruby
ReadmeGenerator.generate(project_name, structure, summary_stats, output_path: nil)
# Returns: rendered markdown string
```

### Template Data

| Variable | Type | Source |
|----------|------|--------|
| `project_name` | String | Constructor arg |
| `structure` | Hash<String, String> | Root dir name → tree text mapping |
| `files` | Array<Hash> | Built from `structure` keys — each has `{name:, class_count: "-", method_count: "-", any_documented?: false}` |
| `summary_stats` | Hash | Passed-through from constructor |
| `generated_at` | String | `Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")` |

### `render_template`

1. Resolves template path from `ENV.fetch("AUTO_DOC_TEMPLATE_README", DEFAULT_TEMPLATE)`.
2. Builds `files` array from `@structure` map entries (each with placeholder counts).
3. Renders ERB with all variables bound via `binding`.

### Private Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `render_template` | String | Sets up binding, renders ERB from template |

### Template Path

Overridable via `ENV["AUTO_DOC_TEMPLATE_README"]`. Falls back to `templates/readme_template.erb`.