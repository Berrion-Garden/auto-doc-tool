# Project Plan: 2026-07-15-phase-2c-search-agent

## Hypotheses Considered

### Hypothesis 1: Monolithic Service with Regex Markdown Parsing
Build SearchService and AgentQueryService as two service classes. SearchService reads VECTORS.json directly and parses INDEX.md markdown tables with regex. AgentQueryService is a thin intent-routing wrapper over SearchService for fallback. Simple, direct, minimal abstractions.

### Hypothesis 2: Pre-Loaded In-Memory Documentation Index
Add a DocIndex class that loads all `.docs/` files into memory on first query, then SearchService queries this index. Clean separation between loading and searching. But adds complexity for a CLI tool that is stateless by nature.

### Hypothesis 3: Cached File Reads per Query Session
SearchService reads files on each call but memoizes within a single query. Keeps I/O manageable without a separate index layer. Similar to Hypothesis 1 but with an unnecessary caching layer for a single-query-per-invocation CLI.

### Selected: Hypothesis 1
Simplest approach that directly implements the specification with zero new abstractions. The markdown table format is well-defined and stable — pipe-delimited columns with consistent structure across INDEX.md files. VECTORS.json is already structured JSON. AgentQueryService needs only regex-based intent detection (no LLM), keeping the surface area small. Follows KISS: files are small enough that parsing on each invocation is negligible cost.

**Key risks:**
- `architecture.md` and `schema.json` don't exist yet (Phase 2b artifacts) — AgentQueryService intents for these must handle missing files gracefully
- INDEX.md Dependencies table has malformed data in generated output (some `To` fields contain code blocks) — search needs lenient parsing

---

## Milestone 1: SearchService — Multi-Strategy Ranked Search

**Intent:** Build the core search engine that reads `.docs/` artifacts and produces ranked results. This is the foundation that AgentQueryService and all CLI search commands depend on.

### Implementation

#### Backend Work Items
- [ ] `lib/auto_doc/search_service.rb` (CREATE): Implement `SearchService.search(project_dir, term, options: {})` with 6 ranking tiers:
  - Exact symbol match in INDEX.md symbols table: score 100
  - Match in INDEX.md dependencies table: score 80  
  - Keyword overlap ≥3 in VECTORS.json: score 60
  - Keyword overlap 1-2 in VECTORS.json: score 40
  - Full-text match in SUMMARY.md/AGENTS.md: score 20
  - Full-text grep in source files (when `--source` flag on): score 10
  - Return `{query:, results: [{file:, score:, match_type:, line:, context:}], total:}`
  - Handle missing `.docs/` directory gracefully (return empty results)
  - Walk directory tree: search all INDEX.md, vectors.json, and SUMMARY.md files recursively

#### Frontend Work Items
- N/A (backend service only)

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | Exact symbol match in INDEX.md symbols table returns score 100 | Result with score 100, match_type "symbol_exact" |
| Unit | Keyword overlap ≥3 in VECTORS.json returns score 60 | Result with score 60, match_type "vector_keyword" |
| Unit | Full-text match in SUMMARY.md returns score 20 | Result with score 20, match_type "summary_text" |
| Unit | Source flag enables grep in .rb files (score 10) | Result with score 10, match_type "source_grep" |
| Unit | Missing .docs/ directory returns empty results | `{query: "foo", results: [], total: 0}` |
| Unit | Results are sorted by descending score | First result has highest score |
| Unit | `limit` option caps results | Returns at most `limit` results |
| Integration | Search with real .docs/ fixture structure | Returns meaningful results from actual generated docs |

### Verification Criteria
- [ ] `SearchService.search(project_dir, "AutoDoc")` returns results with symbol_exact match_type
- [ ] `SearchService.search(project_dir, "generator", source: true)` includes source file matches
- [ ] `SearchService.search("/nonexistent", "foo")` returns `{query: "foo", results: [], total: 0}`
- [ ] All results have `file:`, `score:`, `match_type:`, `line:`, `context:` keys

---

## Milestone 2: AgentQueryService — Intent-Based Query Routing

**Intent:** Build the pattern-matching query router that detects 7 intents from natural language prompts and delegates to the appropriate data source. No LLM required — purely regex + file reads.

### Implementation

#### Backend Work Items
- [ ] `lib/auto_doc/agent_query_service.rb` (CREATE): Implement `AgentQueryService.query(project_dir, prompt)` with intent detection:
  - "what depends on X" / "X dependents" / "who uses X" → `:reverse_dependency` — read INDEX.md Dependencies table, find rows where To column matches X
  - "show me X dependencies" / "X depends on" / "deps of X" → `:forward_dependency` — read INDEX.md Dependencies table, find rows where From column matches X
  - "list all classes in X" / "symbols in X" → `:list_symbols` — read INDEX.md Symbols table
  - "what does X do" / "describe X" / "explain X" → `:describe_symbol` — look up VECTORS.json entry by symbol
  - "architecture of X" / "arch of X" → `:architecture` — return architecture.md content + C4 diagram links (graceful missing file handling)
  - "diagram for X" / "show diagram X" → `:diagram_lookup` — find diagram by name in diagrams/ directory
  - "schema for X" / "table X" → `:schema_lookup` — look up table in schema.json (graceful missing file handling)
  - Unrecognized → fallback to SearchService
  - Return `{intent:, result:}`

#### Frontend Work Items
- N/A (backend service only)

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | "what depends on User" → :reverse_dependency intent | `intent: :reverse_dependency` |
| Unit | "show me Foo dependencies" → :forward_dependency intent | `intent: :forward_dependency` |
| Unit | "list all classes in lib" → :list_symbols intent | `intent: :list_symbols` |
| Unit | "what does PaymentProcessor do" → :describe_symbol intent | `intent: :describe_symbol` |
| Unit | "architecture of myapp" → :architecture intent | `intent: :architecture` |
| Unit | "diagram for deps" → :diagram_lookup intent | `intent: :diagram_lookup` |
| Unit | "schema for users" → :schema_lookup intent | `intent: :schema_lookup` |
| Unit | Unrecognized prompt falls back to SearchService | Result type is search result hash |
| Integration | Each intent returns expected result structure | Structured result with meaningful data |
| Integration | Missing files handled gracefully (architecture.md, schema.json) | Returns error/empty message, does not crash |

### Verification Criteria
- [ ] All 7 intents detected correctly from natural language prompts
- [ ] Unrecognized prompts fall back to SearchService.search
- [ ] Missing `.docs/` directory handled without exception
- [ ] Missing architecture.md returns clear "not yet generated" message
- [ ] Missing schema.json returns clear "not yet generated" message

---

## Milestone 3: CLI Subcommands — search, query, tree, diagram, agent

**Intent:** Wire SearchService, AgentQueryService, and existing FileTreeBuilder into the Thor CLI as new subcommands, all supporting `--json`/`--agent` output formatting.

### Implementation

#### Backend Work Items
- [ ] `lib/auto_doc/cli.rb` (MODIFY): Add 5 new subcommands:
  - `search TERM` — options: `--source`, `--limit` (default 20). Delegates to SearchService, formats via `output_format_for`
  - `query MODULE` — reads INDEX.md + SUMMARY.md + vectors.json for a module directory. Returns structured summary
  - `tree [PATH]` — options: `--depth`. Delegates to `AutoDoc::Utils::FileTreeBuilder.build`
  - `diagram NAME` — options: `--format` (mermaid/ascii). Reads from `.docs/diagrams/NAME.mmd`
  - `agent PROMPT` — Delegates to AgentQueryService, formats via `output_format_for`
- [ ] `lib/auto_doc.rb` (MODIFY): Add require_relative for search_service and agent_query_service

#### Frontend Work Items
- N/A (CLI is backend)

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | `search AutoDoc` outputs text results | Results printed to stdout |
| Unit | `search --json AutoDoc` outputs JSON | Valid JSON with query/results/total |
| Unit | `search --agent AutoDoc` outputs compact JSON | Compact JSON, no whitespace formatting |
| Unit | `search --source --limit 5 AutoDoc` includes source matches | Results include match_type "source_grep" |
| Unit | `query lib/auto_doc` returns structured module summary | Summary with symbols, deps, coverage |
| Unit | `tree lib` outputs indented directory tree | Tree with box-drawing characters |
| Unit | `tree --depth 2 lib` limits depth | Only 2 levels deep |
| Unit | `diagram deps` outputs mermaid content | Mermaid diagram text |
| Unit | `diagram --format ascii deps` outputs ASCII | ASCII art diagram |
| Unit | `diagram nonexistent` shows error | "Diagram not found" message |
| Unit | `agent "what depends on User"` returns dependency results | Structured dependency output |
| Unit | `agent --json "list classes"` returns JSON agent result | Valid JSON from AgentQueryService |
| Unit | All new subcommands appear in `--help` | Subcommands listed in help output |

### Verification Criteria
- [ ] `auto-doc search --source AutoDoc` returns relevant ranked results
- [ ] `auto-doc agent "what does PaymentProcessor do"` returns symbol description
- [ ] `auto-doc tree .docs` produces a directory tree
- [ ] `auto-doc diagram deps` prints the mermaid diagram content
- [ ] All subcommands work with `--json` and `--agent` flags
- [ ] `auto-doc --help` lists all 5 new subcommands
- [ ] Zero new gem dependencies added to gemspec or Gemfile
