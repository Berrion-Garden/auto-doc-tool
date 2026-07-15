# Server

## Class: `AutoDoc::Server < Sinatra::Base`

**File:** `lib/auto_doc/server.rb`

### Purpose

Sinatra web server that serves generated documentation as HTML. Used by the `auto-doc serve` subcommand.

### Configuration

```ruby
set :port, 4567
set :bind, "0.0.0.0"
set :public_folder, nil
```

### Routes

| Route | Description |
|-------|-------------|
| `GET /` | Root index page listing all documented module directories |
| `GET /README` | Renders `README.md` in `<pre>` tag |
| `GET /:module` | Renders `{module}/AGENTS.md` in `<pre>` tag |
| `GET /diagrams/:name` | Renders `{name}.mmd` Mermaid diagram in `<pre>` tag |
| `GET /api/stats` | Returns `report.json` as JSON content-type |
| `GET /api/search?q=term` | Full-text search across all `.md` and `.mmd` files |

### Search API

`GET /api/search?q=term` — Searches all `.md` and `.mmd` files in the docs directory. Returns:

```json
{
  "query": "term",
  "results": [
    {
      "file": "lib/AGENTS.md",
      "matches": [
        { "line": 3, "text": "  ...matching line..." }
      ]
    }
  ],
  "total": 1
}
```

### Private Methods

- **`find_docs_dir`** — Walks up from `Dir.pwd` looking for `.docs/` first, falls back to `.autodoc/`, returns `.docs/` as default if neither exists.
- **`escape_html(text)`** — Delegates to `ERB::Util.html_escape(text)`.

### Phase 2a Changes

**Critical Bug Fix (#3):** XSS vulnerability in `escape_html` was fixed. The method now delegates to Ruby's built-in `ERB::Util.html_escape(text)` instead of manual string escaping. The review summary notes that "an XSS vulnerability exists in Server#escape_html" — the execution log claims this was "already fixed in current codebase (commit 7ccdd75 and later)." This discrepancy is noted but not resolved.

Also: Method renamed from `find_autodoc_dir` to `find_docs_dir` (Phase 2a Milestone 1).