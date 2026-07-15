# TemplateHelper

## Module: `AutoDoc::Generator::TemplateHelper`

**File:** `lib/auto_doc/generator/template_helper.rb`

### Purpose

Shared template reading logic included by all generator classes to avoid duplicating `read_template`.

### Constant

None (module mixin only).

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `read_template(path)` | String | Reads a template file from disk, forces UTF-8 encoding |

### Implementation

```ruby
def read_template(path)
  raise "Template not found: #{path}" unless File.exist?(path)

  content = File.read(path)
  content.force_encoding("UTF-8")
rescue Errno::ENOENT
  raise
end
```

- Raises `"Template not found: #{path}"` if file doesn't exist.
- Calls `File.read(path)` then `force_encoding("UTF-8")` on the result.
- Re-raises `Errno::ENOENT` (which is a subclass of `SystemCallError`, not `StandardError` — the explicit `rescue` is redundant but safe).

### Usage

Included by all generator classes:

```ruby
class AgentsMdGenerator
  include TemplateHelper
  # ...
  template_text = read_template(template_path)
end
```

### Phase 2a

Execution log lists this as fix #6: "read_template duplicated — FIXED (single read_template in template_helper.rb, all generators use it)." This was already fixed before Phase 2a. The template helper is present and used by all generators.