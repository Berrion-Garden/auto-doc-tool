# OutputFormatter

## Class: `AutoDoc::Utils::OutputFormatter`

**File:** `lib/auto_doc/utils/output_formatter.rb`

### Purpose

Formats output data in three modes: `:text` (pass-through), `:json` (pretty-printed), `:agent` (compact JSON stripped of timestamps/noise).

### Constants

```ruby
FORMATS = %i[text json agent].freeze
```

### API

```ruby
OutputFormatter.format(data, format: :text, say: method(:puts))
# Returns: formatted string (always returns, even in :text mode)
```

### Modes

#### `:text` (default)

```ruby
# Behavior: data.to_s → say.call(formatted)
formatted = data.to_s
say.call(formatted)
formatted  # returned
```

Passes through to `say` callback. Preserves current behavior exactly.

#### `:json`

```ruby
# Behavior: JSON.pretty_generate(data) → say.call(formatted)
formatted = JSON.pretty_generate(data)
say.call(formatted)
formatted  # returned
```

Pretty-prints with all fields including timestamps.

#### `:agent`

```ruby
# Behavior: compact_for_agent(data) → JSON.generate(compact) → say.call(formatted)
compact = compact_for_agent(data)
formatted = JSON.generate(compact)
say.call(formatted)
formatted  # returned
```

Strips timestamp-like keys and formatting noise, converts camelCase to snake_case, produces compact single-line JSON via `JSON.generate` (no pretty-printing).

### `compact_for_agent(data)`

Recursively transforms data for agent-optimized output:

- **Hash:** Strips keys matching `/generated_at|timestamp|^_/i`, converts keys from camelCase to snake_case (e.g., `analysesCount` → `:analyses_count`), recursively processes values.
- **Array:** Maps each element through `compact_for_agent`.
- **Other:** Returns as-is (scalars).

### Phase 2a Changes

**Critical Bug Fix (#7):** Execution log notes "OutputFormatter#format returns nil — FIXED — all branches explicitly return formatted data." The method now returns the formatted string in all three code branches (`:json`, `:agent`, and `else`), ensuring callers receive the output.