# AuditReporter

## Class: `AutoDoc::Reporter::AuditReporter`

**File:** `lib/auto_doc/reporter/audit_reporter.rb`

### Purpose

Generates audit reports summarizing documentation coverage across a project. Accepts analysis data in two formats (Array of hashes or Hash keyed by file path), calculates overall and per-module coverage, and formats output as text or JSON.

### Constructor

```ruby
def initialize(project_dir, config)
  @project_dir = project_dir
  @config      = config
end
```

### API

```ruby
# Class method: delegates to instance
AuditReporter.generate(project_dir, config, analyses)
# Returns: Hash — audit report

# Instance method: takes analyses directly
reporter = AuditReporter.new(project_dir, config)
report = reporter.generate(analyses)
# Returns: Hash — audit report

# Static formatting
AuditReporter.format_text(report)  # => String (human-readable)
AuditReporter.format_json(report)  # => String (JSON string)
```

### `generate(analyses)` — Report Structure

Returns a hash with the following keys:

```ruby
{
  project:            String    # @project_dir
  generated_at:       String    # ISO8601 timestamp
  overall_coverage:   Float     # 0.0-100.0, rounded to 2 decimals
  total_symbols:      Integer
  documented_symbols: Integer
  undocumented:       Array<String>  # symbol names like "class_Foo"
  modules:            Hash<String, Hash>  # module_name → {file, total, documented, coverage_pct}
  failures:           Array<Hash>       # [{file, reason, ...}]
  passed:             Boolean           # overall_coverage >= min_coverage && failures.empty?
  min_coverage:       Integer           # from config or 80
}
```

### Input Format Handling

The `generate` method accepts two formats:

1. **Array of hashes** (legacy format): Each element has `:file`, `:symbols`, `:documented` keys.
2. **Hash of hashes** (new format, from CLI): Keyed by file path, each value has `:definitions`. When in Hash format, delegates overall coverage calculation to `CompletenessChecker` and converts to the legacy format internally.

### Failure Detection

Two failure types are checked per module:

| Reason | Condition | Fields |
|--------|-----------|--------|
| `low_coverage` | `coverage_pct < min_coverage` (from config, default 80) | `file`, `coverage_pct`, `threshold` |
| `module_too_large` | `symbols.size > max_module_size` (from config, default 50) | `file`, `size`, `limit` |

### `format_text(report)`

Generates human-readable text with section header `====`, project info, coverage stats, per-module details, failure list, and `RESULT: PASSED` or `RESULT: FAILED`.

### `format_json(report)`

Deduplicates the report hash and pretty-prints via `JSON.pretty_generate`.

### Coverage Calculation

- **Hash input format**: Delegates to `CompletenessChecker.check(analyses)` for overall coverage (single source of truth).
- **Array input format**: Inline calculation: `documented.size / all_symbols.size * 100` (legacy string symbols).
- Both per-module and overall coverage use the same formula, but Hash format delegates to `CompletenessChecker` which handles nested `definitions` arrays.