# YardReader

## Class: `AutoDoc::Analyzer::YardReader`

**File:** `lib/auto_doc/analyzer/yard_reader.rb`

### Purpose

Extracts YARD doc comments from Ruby source files. Matches consecutive comment lines (`# ...`) immediately preceding class/module/method definitions, and returns structured records for each documented symbol found. Supports YARD gem for structured tag extraction when available.

### Constants

```ruby
YARD_AVAILABLE = defined?(YARD)  # Boolean — true if YARD gem is loaded
```

### Nested Struct

```ruby
Comment = Struct.new(:target_type, :target_name, :text, :line, :has_summary?,
                     :params, :return_type, :yield_type, :tags) do
  def to_h
    {
      target_type:  target_type,
      target_name:  target_name,
      text:         text,
      line:         line,
      has_summary?: has_summary?,
      params:       params,
      return_type:  return_type,
      yield_type:   yield_type,
      tags:         tags
    }
  end
end
```

Fields:
- `target_type` — `:class`, `:module`, or `:method`
- `target_name` — Name of the documented symbol
- `text` — Full comment block text (without leading `#` markers)
- `line` — Line number where the comment block starts (1-indexed)
- `has_summary?` — Whether the comment block contains non-whitespace content
- `params` — Array of `{name:, types:, description:}`
- `return_type` — Documented return type string, or nil
- `yield_type` — Documented yield type string, or nil
- `tags` — Array of `{tag_name:, text:}` for unrecognized tags

### API

```ruby
comments = YardReader.extract("/path/to/file.rb")
# Returns: Array<Hash> — comment records
```

### `extract(file_path)`

Checks file exists, calls `new(path).extract_doc_comments`, returns array of comment hashes.

### `extract_doc_comments`

Main scanning loop:

1. Iterates through lines of the source file.
2. At each position, calls `collect_comment_block(i)` to get consecutive comment lines.
3. Checks if the line immediately after the comment block is a class/module/def definition via `identify_target`.
4. If so, strips leading `#` markers from comments, checks for non-whitespace content (`has_summary?`).
5. If YARD gem is available and the block has content, parses structured tags:
   - `:param` → `{name:, types:, description:}`
   - `:return` → `return_type` from `types.first`
   - `:yieldreturn`, `:yield`, `:yieldparam` → `yield_type` from `types.first`
   - Other tags → `{tag_name:, text:}` stored in `tags`
6. Records the comment with `start_idx + 1` as line number.
7. Advances past the comment block AND the target line (`i = next_line_index + 1`).

### `collect_comment_block(start)`

Collects consecutive lines matching `/^\s*#/` starting at index `start`. Returns `[lines, start]` tuple where `lines` is an array of raw comment lines and `start` is the zero-based index.

### `identify_target(line)`

Regex-based detection of definition lines:

| Pattern | Result |
|---------|--------|
| `\A\s*class\s+([A-Z]\w*(?:::\w+)*)` | `[name, :class]` |
| `\A\s*module\s+([A-Z]\w*(?:::\w+)*)` | `[name, :module]` |
| `\A\s*def\s+(?:self\.)?(\w+(?:[?!])?)` | `[name, :method]` |
| No match | `[nil, nil]` |

### Template Data for Consumers

Each returned comment hash:

```ruby
{
  target_type:  :class,
  target_name:  "MyClass",
  text:         "Main application class.\n\nThis class handles user authentication.",
  line:         1,
  has_summary?: true,
  params:       [{ name: "email", types: ["String"], description: "User email" }],
  return_type:  "Boolean",
  yield_type:   nil,
  tags:         [{ tag_name: "author", text: "John Doe" }]
}
```