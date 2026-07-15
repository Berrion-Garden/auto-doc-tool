# SearchService

## Class: `AutoDoc::SearchService`

**File:** `lib/auto_doc/search_service.rb`

### Purpose

Multi-strategy ranked search engine for `.docs/` documentation artifacts. Searches across INDEX.md, vectors.json, SUMMARY.md, AGENTS.md, and optionally source .rb files. Results are ranked by a score system and sorted descending.

### Constructor

None — all methods are class methods.

### API

```ruby
# Basic search
results = SearchService.search(project_dir, "AutoDoc")
# Returns: { query: "AutoDoc", results: [...], total: N }

# With options
results = SearchService.search(project_dir, "processor", options: { source: true, limit: 10 })
# Returns: { query: "processor", results: [...], total: N }
```

### Search Strategy

The `search` method walks the `.docs/` directory recursively and applies file-type-specific searchers:

| File | Searcher Method | Strategy | Max Score |
|------|----------------|----------|-----------|
| `INDEX.md` | `search_index_md` | Exact symbol match (score 100), partial dependency match (score 80) | 100 |
| `vectors.json` | `search_vectors_json` | Keyword overlap from vector entries (score 40 for 1-2 matches, 60 for 3+) | 60 |
| `SUMMARY.md` | `search_summary_md` | Full-text grep (score 20) | 20 |
| `AGENTS.md` | `search_agents_md` | Full-text grep (score 20) | 20 |
| Source files | `search_source_files` | Full-text grep (score 10), excluded when `source: false` | 10 |

### Searcher Details

#### `search_index_md(file_path, term, rel_path)`

Parses INDEX.md table rows:
- Under `## Symbols` section: case-insensitive exact match on symbol name → score 100, `match_type: "symbol_exact"`.
- Under `## Dependencies` section: case-insensitive partial match on From/To columns → score 80, `match_type: "dependency_match"`.
- Skips header rows (`|---|`), table headers (`| Name|`, `| Symbol|`, `| From|`), and non-data rows.

#### `search_vectors_json(file_path, term, rel_path)`

Parses VECTORS.json symbols array:
- Splits search term into words.
- Counts overlap between search words and vector entry keywords.
- Overlap ≥ 3 → score 60, `match_type: "vector_keyword_high"`.
- Overlap 1-2 → score 40, `match_type: "vector_keyword_low"`.

#### `search_summary_md` / `search_agents_md`

Both delegate to `grep_md_file(file_path, term, rel_path, "summary_text", 20)`.

#### `grep_md_file(file_path, term, rel_path, match_type, score)`

Line-by-line grep of markdown file. Returns matches for non-empty lines that contain the (lowercased) term.

#### `search_source_files(project_dir, term)`

Grep all `.rb` files in project dir (excluding files with `/.docs/` in path). Score 10, `match_type: "source_grep"`.

#### `parse_pipe_row(line)`

Parses a pipe-delimited markdown row into an array of trimmed column values.

### Result Format

Each result entry:

```ruby
{
  file:       String    # Path relative to docs dir (e.g., ".docs/lib/AGENTS.md")
  score:      Integer   # 10-100, higher = better match
  match_type: String    # E.g., "symbol_exact", "dependency_match", "vector_keyword_high"
  line:       Integer   # Line number in source file (0 for vectors.json)
  context:    String    # Matching line content or symbol name
}
```

### Post-Processing

1. Sort results by score descending.
2. Apply `limit` (default 20). `limit = 999_999` effectively disables limiting.
3. Return `{ query:, results:, total: }`.