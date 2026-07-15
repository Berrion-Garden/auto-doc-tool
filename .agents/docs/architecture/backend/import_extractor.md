# ImportExtractor

## Class: `AutoDoc::Analyzer::ImportExtractor`

**File:** `lib/auto_doc/analyzer/import_extractor.rb`

### Purpose

Extracts import and dependency statements from Ruby source files. Supports `require`, `require_relative`, `include`, `prepend`, and `extend` keywords.

### IMPORT_PATTERNS

```ruby
IMPORT_PATTERNS = {
  require:          /^(?:\s*)require\s+(['"])(.*?)\1/,
  require_relative: /^(?:\s*)require_relative\s+(['"])(.*?)\1/,
  include:          /^(?:\s*)include\s+([^\n]+)$/,
  prepend:          /^(?:\s*)prepend\s+([^\n]+)$/,
  extend:           /^(?:\s*)extend\s+([^\n]+)$/
}.freeze
```

- `require` / `require_relative` — Captures string content between matching quotes.
- `include` / `prepend` / `extend` — Captures everything to end of line, then splits by comma for multiple constants.

### API

```ruby
ImportExtractor.extract("/path/to/file.rb")
# Returns: [{ path: "json", type: :require }, ...]
#          { path: "Foo, Bar", type: :include } → split to [{ path: "Foo", type: :include }, { path: "Bar", type: :include }]
```

### Implementation

```ruby
def extract_imports
  results = []
  IMPORT_PATTERNS.each do |type, pattern|
    @content.scan(pattern) do |matches|
      value = matches.flatten.compact.last.to_s.strip
      next if value.empty?

      case type
      when :require, :require_relative
        results << { path: value, type: type }
      else
        values = value.split(",").map(&:strip).reject(&:empty?)
        values.each { |v| results << { path: v, type: type } }
      end
    end
  end
  results
end
```

Uses `matches.flatten.compact.last` to get the captured group value (works for both single-capture and multi-capture regex).

### Phase 2a Bug Fix Notes

Execution log claims Critical #1 and #2 were fixed before Phase 2a:

1. **Wrong capture group (#1):** Line 37 uses `.last` instead of `.first` for extracting the captured value.
2. **Multiline regex (#2):** Patterns use `[^\n]+` instead of `.+` with no `/m` flag, preventing multiline matching issues.

**Per review summary:** Manual testing found that `ImportExtractor` has critical bugs producing corrupted output (raw source code embedded in diagrams, markdown tables, and JSON vectors). The review summary states these bugs are present in the current codebase, while the execution log claims they were fixed in commit 7ccdd75. This discrepancy is noted but not resolved — I only document what is observed.