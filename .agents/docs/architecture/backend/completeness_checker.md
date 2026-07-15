# CompletenessChecker

## Class: `AutoDoc::Reporter::CompletenessChecker`

**File:** `lib/auto_doc/reporter/completeness_checker.rb`

### Purpose

Calculates per-symbol documentation coverage percentage. Checks public symbols (classes, modules, methods) against whether they have YARD doc comments. Used as the single source of truth for coverage percentage when `AuditReporter` receives Hash-format analyses.

### Constructor

```ruby
def initialize(analyses)
  @analyses = analyses || {}
end
```

### API

```ruby
# Class method
result = CompletenessChecker.check(analyses, threshold = 80)
# Returns: Hash

# Instance method
checker = CompletenessChecker.new(analyses)
result = checker.check(threshold = 80)
# Returns: Hash
```

### Return Value

```ruby
{
  total:        Integer    # Total public symbol count
  documented:   Integer    # Number of documented symbols
  undocumented: Array<Hash>  # Each: {name:, type:, file:, line:}
  coverage_pct: Float      # Percentage, rounded to 1 decimal place
}
```

### `check(threshold = 80)`

Iterates `@analyses` (Hash keyed by file path, each value is an analysis hash):

1. **Extracts symbols** from each analysis via `extract_symbols` (supports array, nested analysis with `:symbols`, or nested analysis with `:definitions`).
2. For each symbol, checks if `:has_doc?` is truthy.
3. Documented symbols increment `documented` counter.
4. Undocumented symbols are collected with `{name:, type:, file:, line:}`.
5. Coverage: `documented / total * 100`, rounded to 1 decimal. Returns 100.0 if total is 0.

### `extract_symbols(analysis)`

Handles multiple input formats:

| Input | Returns |
|-------|---------|
| Array | Returns as-is |
| Hash with `:symbols` key | Returns `analysis[:symbols]` |
| Hash with `:definitions` key | Returns definitions mapped to hashes (`d.is_a?(Hash) ? d : d.to_h`) |
| Other | Returns `[]` |

### Type Flexibility

The `sym_name`, `sym_type`, and `sym_line` helper methods handle both:
- **Hash symbols**: `sym[:name]`, `sym[:type]`, `sym[:line]` / `sym[:line_number]`
- **Object symbols**: `sym.name`, `sym.type`, `sym.line` / `sym.line_number`
- **Unknown**: Returns `"unknown"` for name/type, `0` for line

### `symbol_documented?(sym)`

Checks `sym[:has_doc?]` for hash symbols. Handles non-Hash symbols that respond to `to_h` by converting them first. Rescues `TypeError` / `ArgumentError` and returns `false`.