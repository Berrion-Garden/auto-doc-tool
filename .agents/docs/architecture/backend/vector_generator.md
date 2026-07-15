# VectorGenerator

## Class: `AutoDoc::Generator::VectorGenerator`

**File:** `lib/auto_doc/generator/vector_generator.rb`

### Purpose

Generates VECTORS.json files for project-level and directory-level symbol indexing. Each vector entry contains metadata about a symbol (class, module, or method) for cross-referencing and search.

### Entry Schema

Each vector entry contains:

```ruby
{
  id:            "class_Foo",              # type_prefix + "_" + name (doubled :: → _)
  symbol:        "Foo",                     # Full symbol name
  type:          "class",                   # "class", "module", or "method"
  scope:         "public",                  # Always "public" (no private detection)
  file:          "/path/to/foo.rb",        # Full file path
  line:          1,                         # Line number (0 if unknown)
  summary:       "Main application class",  # YARD doc summary or ""
  signature:     "class Foo",               # Signature string or name
  visibility:    "public",                  # From source analysis
  keywords:      ["main", "application"],  # Up to 15 split, deduped, stop-word-free
  dependencies:  [],                        # From source analysis
  consumed_by:   [],                        # Populated by cross-reference pass (empty)
  parent_module: "MyModule"                 # Nested class/module parent
}
```

### API

```ruby
# Project-level vectors (all files)
data = VectorGenerator.generate_project(analyses, config)
# Returns: { symbols: [...], generated_at: "ISO8601" }

# Directory-level vectors (filtered analyses)
data = VectorGenerator.generate_directory("lib", dir_analyses, config)
# Returns: { symbols: [...], generated_at: "ISO8601" }

# Write to disk
VectorGenerator.write("/path/to/VECTORS.json", data)
# Creates directory, writes JSON.pretty_generate(data)

# Keyword extraction (callable from anywhere)
keywords = VectorGenerator.keyword_extraction("AgentsMdGenerator")
# => ["agents", "md", "generator"]
```

### Public Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `generate_project(analyses, _config=nil)` | Hash | Project-level vector data from all analyses |
| `generate_directory(_dir_name, dir_analyses, _config=nil)` | Hash | Directory-level vector data |
| `write(output_path, data)` | void | Writes pretty-printed JSON to file |
| `keyword_extraction(name)` | Array<String> | Up to 15 keywords from CamelCase/snake_case |
| `build_doc_index(docs)` | Hash | Lookup index keyed by ":type_name" symbols (used internally) |

### Private Class Methods

- **`build_vector_entry(defn, file_path, doc_index)`** — Builds a single vector entry from a definition hash, file path, and doc lookup index.
- **`build_vectors(analyses)`** — Shared method called by both `generate_project` and `generate_directory`. Iterates definitions, builds entries via `build_vector_entry`.

### Keyword Extraction

1. Split CamelCase: `AgentsMdGenerator` → `["Agents", "Md", "Generator"]`
2. Split snake_case: `"foo_bar"` → `["foo", "bar"]`
3. Split non-word chars: `"v2.0"` → `["v", "2", "0"]`
4. Remove empty strings, stop words (the, a, an, and, or, of, in, to, for, on, with, at, by, from, as, is, it, be, has, have, do, does, not, no, yes, this, that, these, those)
5. Downcase, deduplicate
6. Return top 15

### Stop Words

Defined as a frozen constant at class level.

### Template Path

Not template-based. Generates JSON directly via `JSON.pretty_generate`.