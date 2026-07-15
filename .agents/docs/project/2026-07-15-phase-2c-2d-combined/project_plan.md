# Project Plan: 2026-07-15-phase-2c-2d-combined

## Hypotheses Considered

### Hypothesis 1: Monolithic single-pass
Build AgentQueryService, all 5 CLI subcommands, 8 server endpoints, MapGenerator, orchestrator wiring, and all specs in one pass. Fastest to write but impossible to test incrementally — a single failure blocks everything.

### Hypothesis 2: Feature-centric vertical slices
Split into (a) agent query vertical: AgentQueryService + `agent` CLI + `POST /api/agent` + specs, then (b) documentation browser vertical: remaining 4 CLI subcommands + 7 server read endpoints + MapGenerator + specs. Clean separation but the "browser" slice is still large, and MapGenerator wiring into orchestrator cuts across both.

### Hypothesis 3: Stratified dependency-ordered (selected)
Split into 3 layers: (1) AgentQueryService as core domain logic, (2) MapGenerator as independent artifact layer + orchestrator wiring, (3) CLI subcommands + server endpoints + main requires as presentation layer. M1 and M2 are parallel (zero cross-dependency); M3 depends on both.

### Selected: Hypothesis 3
This is the strongest approach because AgentQueryService and MapGenerator share zero dependencies — they can be built and tested in parallel. The CLI and server are thin presentation wrappers that consume these services, so they naturally slot into the final milestone. Each milestone yields a testable increment; failures are isolated to a single layer.

**Key risk:** CLI subcommands and server endpoints are "thin" if the services are solid. If service APIs need adjustment during presentation-layer work, we'll need to revisit M1/M2. Low probability given the well-specified interfaces.

---

## Milestone 1: AgentQueryService

**Intent:** Build the intent-based query router that maps natural-language prompts to documentation retrieval strategies. This is the core domain logic for the `agent` CLI subcommand and `POST /api/agent` server endpoint.

### Implementation

#### Backend Work Items
- [ ] `lib/auto_doc/agent_query_service.rb`: Create AgentQueryService class with `self.query(project_dir, prompt)` returning `{intent:, result:, query:}`. Implement pattern matching via regex array (no LLM). Patterns in priority order:
  - `:reverse_dependency` — match "what depends on", "dependents", "who uses"; read INDEX.md Dependencies table, find rows where To matches the extracted term
  - `:forward_dependency` — match "depends on", "deps of", "dependencies"; read INDEX.md Dependencies, find rows where From matches
  - `:list_symbols` — match "list all", "symbols in"; read INDEX.md Symbols table, return all rows
  - `:describe_symbol` — match "what does", "describe", "what is"; look up VECTORS.json entry by symbol name
  - `:architecture` — match "architecture of", "arch of"; return architecture.md content + diagram links
  - `:diagram_lookup` — match "diagram for", "show diagram"; find matching .mmd file in diagrams/
  - `:schema_lookup` — match "schema for", "table"; look up table in schema.json
  - Fallback: delegate to SearchService.search when no pattern matches
- [ ] `lib/auto_doc.rb`: Add `require_relative "auto_doc/agent_query_service"` in the appropriate section (after SearchService)

#### Frontend Work Items
N/A (backend-only milestone)

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | "what depends on X" pattern matching | Returns :reverse_dependency intent, queries INDEX.md Dependencies |
| Unit | "show me deps of X" pattern matching | Returns :forward_dependency intent |
| Unit | "list all classes in lib" pattern matching | Returns :list_symbols intent |
| Unit | "what does Foo do" pattern matching | Returns :describe_symbol intent, looks up VECTORS.json |
| Unit | "architecture of app" pattern matching | Returns :architecture intent, reads architecture.md |
| Unit | "diagram for deps" pattern matching | Returns :diagram_lookup intent |
| Unit | "schema for users" pattern matching | Returns :schema_lookup intent |
| Unit | Unrecognized prompt ("blah blah whatever") | Falls back to SearchService.search |
| Unit | Missing project_dir or missing docs artifacts | Returns graceful empty/error responses, no crashes |
| Unit | Case-insensitive pattern matching | "WHAT DEPENDS ON Foo" matches :reverse_dependency |
| Integration | Full query against fixture project with real .docs/ | Returns populated result hash with correct intent |

### Verification Criteria
- [ ] `bundle exec rspec spec/auto_doc/agent_query_service_spec.rb` — all tests pass
- [ ] AgentQueryService.query returns the documented `{intent:, result:, query:}` shape for all 8 patterns
- [ ] Unrecognized prompts fall back to SearchService without errors
- [ ] Missing files (no .docs/, no INDEX.md, etc.) return graceful empty responses

---

## Milestone 2: MapGenerator + Orchestrator Wiring

**Intent:** Build the `.map.json` generator that inventories all generated documentation artifacts, then wire it into the orchestrator's `generate()` method as the final step. This is independent of AgentQueryService.

### Implementation

#### Backend Work Items
- [ ] `lib/auto_doc/generator/map_generator.rb`: Create MapGenerator class with `self.generate(project_dir, output_dir, project_name, coverage_pct, total_symbols)` that:
  - Walks the output_dir recursively to inventory all generated files
  - Categorizes files into: indexes, summaries, vectors, diagrams, agents_docs, architecture, schema, audit
  - Counts total_symbols from VECTORS.json if available
  - Writes `.map.json` to the output_dir
  - Returns the map data hash
- [ ] `lib/auto_doc/orchestrator.rb`: At the end of `generate()`, after the manifest save, call `MapGenerator.generate(...)` and emit a "Created" message via the `say` callable
- [ ] `lib/auto_doc.rb`: Add `require_relative "auto_doc/generator/map_generator"` in the generators section

#### Frontend Work Items
N/A (backend-only milestone)

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | Generate map.json from a mock .docs/ tree | Categories correctly: indexes, summaries, vectors, diagrams, etc. |
| Unit | Map JSON schema fields | Contains schema_version, generated_at, project, artifacts, module_roots, coverage_pct, total_symbols |
| Unit | Empty output directory | Returns empty artifact arrays, no crash |
| Unit | Missing optional artifacts (no schema/, no architecture.md) | Omits those categories gracefully |
| Integration | orchestrator.generate() produces .map.json at the end | File exists at .docs/.map.json with correct structure |

### Verification Criteria
- [ ] `bundle exec rspec spec/auto_doc/generator/map_generator_spec.rb` — all tests pass
- [ ] `bundle exec rspec spec/auto_doc/cli_spec.rb` — existing generate specs still pass, and new specs verify .map.json is generated
- [ ] `.map.json` schema matches the specification: schema_version, generated_at, project, artifacts hash with all categories, module_roots, coverage_pct, total_symbols
- [ ] `orchestrator.generate` produces the map as the last step before returning

---

## Milestone 3: CLI Subcommands + Server Expansion + Main Wiring

**Intent:** Add 5 new CLI subcommands (search, query, tree, diagram, agent) and 8 new server API endpoints. Wire AgentQueryService into the `agent` subcommand and `POST /api/agent`. Update `lib/auto_doc.rb` with all new requires. Depends on M1 (AgentQueryService) and M2 (MapGenerator).

### Implementation

#### Backend Work Items
- [ ] `lib/auto_doc/cli.rb`: Add 5 subcommands:
  - `search TERM` — delegates to SearchService.search; supports `--source`, `--limit` options; uses `output_format_for` for --json/--agent
  - `query MODULE` — reads INDEX.md, SUMMARY.md, VECTORS.json for the module, returns structured summary; supports --json/--agent
  - `tree [PATH]` — delegates to FileTreeBuilder.build; supports `--depth` option; supports --json/--agent
  - `diagram NAME` — finds .mmd file in .docs/diagrams/, outputs content; supports `--format` option (mermaid/ascii); supports --json/--agent
  - `agent PROMPT` — splats args, delegates to AgentQueryService.query; supports --json/--agent
- [ ] `lib/auto_doc/server.rb`: Add 8 endpoints:
  - `GET /api/index?path=` — reads INDEX.md for path, renders as HTML
  - `GET /api/summary?path=` — reads SUMMARY.md for path, renders as HTML
  - `GET /api/vectors?path=` — reads vectors.json for path, returns as JSON
  - `GET /api/query?q=` — delegates to SearchService.search with source:true, returns enhanced results page as HTML
  - `GET /api/diagram/:name` — returns diagram content (Mermaid source)
  - `GET /api/schema` — returns schema.json as JSON
  - `GET /api/architecture` — returns architecture.md as HTML
  - `POST /api/agent` — accepts JSON body `{prompt:"..."}`, delegates to AgentQueryService.query, returns result as JSON
- [ ] `lib/auto_doc.rb`: Verify all new requires are in place (AgentQueryService and MapGenerator — added in M1/M2)

#### Frontend Work Items
N/A (backend-only milestone)

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit (CLI) | `search` subcommand with term | Outputs search results; --json outputs JSON |
| Unit (CLI) | `query` subcommand with module name | Outputs structured summary |
| Unit (CLI) | `tree` subcommand with path | Outputs indented directory tree |
| Unit (CLI) | `diagram` subcommand with name | Outputs diagram content |
| Unit (CLI) | `agent` subcommand with prompt | Delegates to AgentQueryService, outputs result |
| Unit (CLI) | --json flag on all new subcommands | JSON output via OutputFormatter |
| Unit (CLI) | --agent flag on all new subcommands | Compact JSON output |
| Integration (Server) | GET /api/index?path=lib | Returns INDEX.md as HTML |
| Integration (Server) | GET /api/summary?path=lib | Returns SUMMARY.md as HTML |
| Integration (Server) | GET /api/vectors?path=lib | Returns vectors.json |
| Integration (Server) | GET /api/query?q=term | Returns enhanced search results |
| Integration (Server) | GET /api/diagram/deps | Returns diagram content |
| Integration (Server) | GET /api/schema | Returns schema.json |
| Integration (Server) | GET /api/architecture | Returns architecture.md |
| Integration (Server) | POST /api/agent {prompt:"describe Foo"} | Calls AgentQueryService, returns JSON |
| Integration (Server) | New endpoints with missing files | Returns graceful 404/error responses |
| Regression | All existing CLI and Server specs still pass | No existing functionality broken |

### Verification Criteria
- [ ] `bundle exec rspec spec/auto_doc/cli_spec.rb` — all tests pass (existing + new subcommands)
- [ ] `bundle exec rspec spec/auto_doc/server_spec.rb` — all tests pass (existing + new endpoints)
- [ ] `bundle exec rspec` — full suite green, no regressions
- [ ] CLI `auto-doc search AutoDoc` returns ranked results
- [ ] CLI `auto-doc agent "what depends on SearchService"` returns dependency information
- [ ] Server `POST /api/agent` with body `{"prompt":"describe Orchestrator"}` returns JSON with intent and result
- [ ] All new CLI subcommands support --json and --agent flags
