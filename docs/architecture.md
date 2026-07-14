# Auto-Doc Tool — Architecture

## SYSTEM CONTEXT (C4 Level 1)

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Developer  │     │  AI Agent    │     │ CI Pipeline │
│  (Human)    │     │  (Machine)   │     │  (Automated)│
└──────┬──────┘     └──────┬───────┘     └──────┬──────┘
       │                   │                    │
       │  CLI commands     │  CLI query / HTTP  │  CLI audit
       │  (generate,       │  (query, search)   │  (audit, orphans)
       │   audit, serve)   │                    │
       │                   │                    │
       ▼                   ▼                    ▼
┌──────────────────────────────────────────────────────┐
│                  Auto-Doc Gem                         │
│                                                      │
│  Reads source code → Produces .autodoc/ output       │
│  Serves documentation via HTTP (optional)            │
│  Embedding + search for agent queries                │
└──────────────────────────────────────────────────────┘
       │                           │
       │ Reads                     │ Writes
       ▼                           ▼
┌──────────────┐          ┌───────────────┐
│  Source Code │          │  .autodoc/    │
│  (.rb files) │          │  (output dir) │
└──────────────┘          └───────────────┘
```

**External Actors:**
- **Developer** — runs CLI commands to generate docs, run audits, serve docs
- **AI Agent** — queries documentation via CLI `query` command or HTTP `/api/query` endpoints
- **CI Pipeline** — runs `audit --threshold N` to gate PR merges on doc coverage

**External Systems:**
- **Source Code** — target project's Ruby files (read-only)
- **.autodoc/** — generated output directory (write-only)
- **Vector Store** — local FAISS index file (read/write, Phase 3)

---

## CONTAINER DIAGRAM (C4 Level 2)

```
┌──────────────────────────────────────────────────────────────────┐
│                        Auto-Doc Gem                               │
│                                                                  │
│  ┌────────────┐    ┌──────────────┐    ┌───────────────────┐    │
│  │   CLI      │    │  Web Server  │    │  Config Service   │    │
│  │  (Thor)    │    │  (Sinatra)   │    │  (.autodoc.yml)   │    │
│  └─────┬──────┘    └──────┬───────┘    └─────────┬─────────┘    │
│        │                  │                       │              │
│        │          ┌───────┴───────┐               │              │
│        │          │               │               │              │
│        ▼          ▼               ▼               ▼              │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Orchestrator Service                    │   │
│  │         Coordinates analysis → generation → output        │   │
│  └──────────────────────────┬───────────────────────────────┘   │
│                             │                                    │
│        ┌────────────────────┼────────────────────┐              │
│        ▼                    ▼                     ▼              │
│  ┌──────────┐    ┌──────────────────┐    ┌───────────────┐     │
│  │ Analyzer │    │    Generators    │    │  Query Engine │     │
│  │ Engine   │    │  (Markdown,      │    │  (Symbol,     │     │
│  │ (AST,    │    │   Diagrams,      │    │   Dependency, │     │
│  │  Imports,│    │   Indexes,       │    │   Coverage,   │     │
│  │  Docs)   │    │   Summaries,     │    │   Summary)    │     │
│  └──────────┘    │   Map)           │    └───────┬───────┘     │
│                  └────────┬─────────┘            │              │
│                           │                      │              │
│        ┌──────────────────┼──────────────────────┘              │
│        │                  │                                      │
│        ▼                  ▼                                      │
│  ┌─────────────────────────────┐    ┌──────────────────────┐    │
│  │      Search Engine          │    │    Audit Engine      │    │
│  │  (Keyword Index, Vector     │    │  (Coverage Report,   │    │
│  │   Store, Embedder,          │    │   Orphan Detection)  │    │
│  │   Hybrid Ranker)            │    │                      │    │
│  └─────────────────────────────┘    └──────────────────────┘    │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Persistence Layer                       │   │
│  │  .autodoc/*  (file system)    vector/ (FAISS index)      │   │
│  └──────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

**Container Descriptions:**

| Container | Technology | Responsibility |
|-----------|-----------|----------------|
| CLI | Thor | Command dispatch, arg parsing, exit codes. Stateless dispatcher. |
| Web Server | Sinatra | HTTP API for agent queries. Optional (only when `serve` runs). |
| Config Service | YAML + CLI merge | Loads `.autodoc.yml`, merges CLI flags, provides defaults. |
| Orchestrator | Ruby class | Coordinates the full generate pipeline: analyze → generate → write. Single entry point called by CLI. |
| Analyzer Engine | Ripper + regex | Parses Ruby source: symbols, imports, doc comments, dependency graph. |
| Generators | ERB templates + Ruby | Produces all output files: AGENTS.md, README.md, _index.md, SUMMARY.md, diagrams, map.json. |
| Query Engine | Ruby classes | Structured queries for agents: find-symbol, find-dependents, find-dependencies, coverage, summary. |
| Search Engine | FAISS + BM25 | Semantic vector search + keyword search, hybrid ranked via RRF. Phase 3. |
| Audit Engine | Ruby classes | Coverage auditing, threshold gating, orphan file detection. |
| Persistence | File system + FAISS | Reads/writes `.autodoc/` directory and vector index files. |

---

## COMPONENT BREAKDOWN (C4 Level 3)

### 1. CLI Component
```
┌─────────────────────────────────────────┐
│  CLI (Thor)                             │
│                                         │
│  Subcommands:                           │
│  • init [PATH]        → Config Init    │
│  • generate [PATH]    → Orchestrator   │
│  • audit [PATH]       → Audit Engine   │
│  • diff [SINCE]       → Diff Reporter  │
│  • version            → VERSION const  │
│  • orphans [PATH]     → Audit Engine   │
│  • serve [PATH]       → Web Server     │
│  • search QUERY       → Search Engine  │
│  • query --TYPE ARGS  → Query Engine   │
│  • e2e                → E2E Runner     │
│                                         │
│  Interface: CLI flags + args            │
│  Output: STDOUT text / JSON             │
│  Exit codes: 0=success, 1=fail,         │
│              2=orphans-found            │
└─────────────────────────────────────────┘
```

### 2. Analyzer Engine
```
┌─────────────────────────────────────────┐
│  Analyzer Engine                        │
│                                         │
│  ┌─────────────┐  ┌───────────────┐    │
│  │SourceParser │  │ImportExtractor│    │
│  │ (Ripper AST)│  │ (regex-based) │    │
│  └──────┬──────┘  └───────┬───────┘    │
│         │                  │            │
│  ┌──────┴──────────────────┴──────┐    │
│  │     DependencyGraphBuilder     │    │
│  │  (merges symbols + imports     │    │
│  │   → directed graph)            │    │
│  └────────────────────────────────┘    │
│                                         │
│  ┌────────────────────┐                │
│  │    YardReader       │                │
│  │  (doc comment       │                │
│  │   extraction)       │                │
│  └────────────────────┘                │
│                                         │
│  Public Interface:                      │
│  • analyze_directory(path) → AnalysisResult
│  • build_dependency_graph(path) → Graph
│  • extract_symbols(file) → [Symbol]
│  • extract_imports(file) → [Import]
│  • extract_docs(file) → [DocComment]
└─────────────────────────────────────────┘
```

### 3. Generator Components
```
┌──────────────────────────────────────────────┐
│  Generator Layer                             │
│                                              │
│  ┌──────────────────┐  ┌────────────────┐   │
│  │AgentsMdGenerator │  │ReadmeGenerator │   │
│  │ Per-directory    │  │ Per module root│   │
│  │ AGENTS.md files  │  │ README.md      │   │
│  └──────────────────┘  └────────────────┘   │
│                                              │
│  ┌──────────────────┐  ┌────────────────┐   │
│  │ IndexGenerator   │  │SummaryGenerator│   │
│  │ _index.md at     │  │ SUMMARY.md per │   │
│  │ every dir level  │  │ module root    │   │
│  └──────────────────┘  └────────────────┘   │
│                                              │
│  ┌──────────────────┐  ┌────────────────┐   │
│  │DiagramGenerator  │  │  MapGenerator  │   │
│  │ deps.mmd,        │  │  map.json      │   │
│  │ class.mmd,       │  │  cross-ref     │   │
│  │ er.mmd           │  │  manifest      │   │
│  └──────────────────┘  └────────────────┘   │
│                                              │
│  Public Interface:                           │
│  • generate_all(analysis_result) → OutputManifest
│  • Each generator returns {path, content}    │
│  • Orchestrator handles file I/O             │
└──────────────────────────────────────────────┘
```

### 4. Query Engine Components
```
┌──────────────────────────────────────────────┐
│  Query Engine                                │
│                                              │
│  ┌────────────────┐  ┌──────────────────┐   │
│  │ SymbolFinder   │  │DependencyResolver│   │
│  │ find-symbol    │  │ find-dependents  │   │
│  │ by name/type   │  │ find-dependencies│   │
│  └────────────────┘  └──────────────────┘   │
│                                              │
│  ┌────────────────┐  ┌──────────────────┐   │
│  │CoverageQuerier │  │ SummaryQuerier   │   │
│  │ --coverage     │  │ --summary --dir  │   │
│  │ stats by dir   │  │ structured data  │   │
│  └────────────────┘  └──────────────────┘   │
│                                              │
│  All methods return structured hashes        │
│  (JSON-serializable, no Markdown)            │
└──────────────────────────────────────────────┘
```

### 5. Search Engine (Phase 3)
```
┌──────────────────────────────────────────────┐
│  Search Engine                               │
│                                              │
│  ┌────────────┐  ┌──────────┐  ┌─────────┐  │
│  │  Embedder  │  │KeywordIdx│  │ Chunker │  │
│  │ batch      │  │ inverted │  │ AST-    │  │
│  │ embedding  │  │ index    │  │ aware   │  │
│  │ 100/batch  │  │ BM25     │  │ semantic│  │
│  └─────┬──────┘  └────┬─────┘  └────┬────┘  │
│        │               │             │       │
│  ┌─────┴───────────────┴─────────────┴─────┐ │
│  │         VectorStore (FAISS)             │ │
│  │  • create_index(chunks)                 │ │
│  │  • query(embedding, top_k) → [results]  │ │
│  │  • incremental_update(changed_files)    │ │
│  └────────────────────┬────────────────────┘ │
│                       │                      │
│  ┌────────────────────┴────────────────────┐ │
│  │         HybridRanker (RRF)              │ │
│  │  • merge(semantic_results, keyword)     │ │
│  │  • 60% semantic + 40% keyword weight    │ │
│  │  • deduplicate, re-rank, return top_k   │ │
│  └─────────────────────────────────────────┘ │
│                                              │
│  Public Interface:                           │
│  • search(query, mode: :hybrid) → [Results]  │
│  • embed_all(files) → VectorIndex            │
│  • re_embed_changed(files) → VectorIndex     │
└──────────────────────────────────────────────┘
```

---

## DATA FLOW

### Generate Pipeline
```
Source Files
    │
    ▼
┌──────────────┐
│ Analyzer      │  SourceParser → [Symbols]
│ Engine        │  ImportExtractor → [Imports]  
│               │  YardReader → [DocComments]
│               │  DependencyGraphBuilder → Graph
└──────┬───────┘
       │ AnalysisResult
       ▼
┌──────────────┐
│ Generator     │  AgentsMdGenerator → AGENTS.md per dir
│ Layer         │  ReadmeGenerator → README.md per root
│               │  IndexGenerator → _index.md per dir
│               │  SummaryGenerator → SUMMARY.md per root
│               │  DiagramGenerator → .mmd files
│               │  MapGenerator → map.json
└──────┬───────┘
       │ [OutputManifest: {path, content} pairs]
       ▼
┌──────────────┐
│ Orchestrator  │  Writes files to .autodoc/
│               │  Creates directory structure
│               │  Reports progress
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ (Optional)    │  Embedder: chunk files → batch embed
│ Search Engine │  VectorStore: create/update FAISS index
│               │  KeywordIndex: build inverted index
└──────┬───────┘
       │
       ▼
  .autodoc/ complete
```

### Query Pipeline (Agent)
```
Agent Query (CLI or HTTP)
    │
    ▼
┌──────────────────┐
│ Query Engine      │  SymbolFinder / DependencyResolver
│ (reads .autodoc/  │  / CoverageQuerier / SummaryQuerier
│  map.json +       │
│  generated files) │  Reads from generated docs and map.json
└────────┬─────────┘
         │ Structured Hash (JSON-serializable)
         ▼
    Agent receives JSON response
```

### Search Pipeline (Phase 3)
```
Agent Search Query
    │
    ▼
┌──────────────────┐
│ SearchService     │  Coordinating facade
└────────┬─────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌────────┐ ┌──────────┐
│Keyword │ │Vector    │
│Index   │ │Store     │
│(BM25)  │ │(FAISS)   │
└───┬────┘ └────┬─────┘
    │           │
    └────┬──────┘
         ▼
┌──────────────────┐
│ HybridRanker      │  RRF merge (60/40)
│ deduplicate +     │
│ re-rank           │
└────────┬─────────┘
         │
         ▼
    Ranked Results → Agent
```

---

## ARCHITECTURE DECISION RECORDS (ADRs)

### ADR-1: Output Directory Structure
**Decision:** Single `.autodoc/` directory at project root containing all generated artifacts.
**Rationale:** Single output root simplifies .gitignore (one line), agent discovery (look in one place), and cleanup. Hierarchical subdirectories mirror source structure for intuitive navigation.
**Alternatives considered:** Scattered `.agents.md` per directory (pollutes source tree), separate `docs/` directory (confusing alongside hand-written docs).

### ADR-2: Agent Query Interface — Dual CLI + HTTP
**Decision:** Agent queries available both as CLI subcommand and HTTP endpoint.
**Rationale:** CLI covers agent-in-terminal use (primary), HTTP covers agent-over-network use and integration tests. Both share the same Query Engine backend — only the transport differs.
**Alternatives considered:** CLI-only (no network access for agent orchestrators), HTTP-only (requires daemon running).

### ADR-3: Local-First Vector Store (FAISS)
**Decision:** FAISS as the primary vector store, running locally within the gem process.
**Rationale:** No network dependency, no server process to manage, works offline. FAISS is the fastest local option and supports incremental updates. LanceDB considered but adds complexity for a single-user tool.
**Alternatives considered:** Chroma (requires separate server), LanceDB (columnar, better for multi-modal but overkill), Pinecone (cloud, paid, requires network).

### ADR-4: AST-Aware Chunking (Function/Class Boundaries)
**Decision:** Chunk at function/class/method boundaries with surrounding context, not fixed-size character windows.
**Rationale:** Industry best practice (tree-sitter based chunkers). Function-level chunks map one-to-one with agent questions ("what does this method do?"). 5 lines of surrounding context provides scope (imports, class declaration) without noise.
**Alternatives considered:** Fixed-size character windows (breaks mid-function, poor relevance), file-level chunks (too coarse for search).

### ADR-5: Hybrid Search (60% Semantic + 40% Keyword)
**Decision:** Merge semantic and keyword search results via Reciprocal Rank Fusion, weighted 60/40.
**Rationale:** Pure semantic search misses exact symbol names ("User.find_by_email"). Pure keyword misses conceptual queries ("how does authentication work?"). 60/40 split validated in production benchmarks (87% precision vs 72% semantic-only).
**Alternatives considered:** Semantic-only (poor for exact matches), keyword-only (poor for conceptual queries), learned weights (requires training data).

### ADR-6: map.json as Single Source of Truth
**Decision:** map.json as the definitive cross-reference linking vector chunks to source files to generated docs.
**Rationale:** Agents need to jump from a search result (chunk) to the right documentation file. map.json provides this without parsing every generated file. Versioned schema (`schema_version: "1.0"`) for forward compatibility.
**Alternatives considered:** Frontmatter in each generated file (scattered, harder to query programmatically), no mapping file (agents must grep generated docs).

### ADR-7: Structural Summaries, Not AI-Generated
**Decision:** Module summaries generated from code structure analysis, not from LLM/AI calls.
**Rationale:** NFR-7: No external AI dependency. Summaries are deterministic, fast, and predictable. They describe what the code contains (classes, methods, dependencies) — not what it means. Developer fills in the "why" later.
**Alternatives considered:** LLM-generated summaries (requires API key, cost, latency, non-deterministic), no summaries (agents must read all AGENTS.md files to understand a module).

### ADR-8: Incremental Embedding via File Hash
**Decision:** Track SHA256 hashes of source files to determine which files need re-embedding.
**Rationale:** Embedding large codebases is expensive (45min for 10K files). Full re-embed on every `generate --embed` is wasteful. Hash comparison is fast and reliable.
**Alternatives considered:** Modification timestamps (unreliable across git operations, CI), always full re-embed (wasteful for large projects).

---

## CROSS-CUTTING CONCERNS

| Concern | Implementation |
|---------|---------------|
| Error Handling | Domain-specific error classes raised from services, caught by CLI (exit codes) or HTTP (status codes) |
| Progress Reporting | ProgressReporter utility: emits structured progress events for long operations (embedding, large generates) |
| Logging | STDOUT/STDERR for CLI, Sinatra logger for HTTP. Verbose mode (`--verbose`) enables debug output. |
| Configuration | Single `.autodoc.yml` at project root, merged with CLI flags. Read once at command start, immutable during execution. |
| Testing | RSpec with fixtures. Unit tests per component, integration tests across pipeline stages, E2E self-test. |
| Performance | Batch embedding (100 chunks/batch), streaming file writes, lazy dependency graph building. |
| Security | Reads filesystem, writes to `.autodoc/`. No network calls (except optional embedding model download). No code execution of analyzed files. |

---

## PHASE PLAN

### Phase 1 — Fix & Complete (Current)
- Fix all existing failing specs (6 existing out of 13 target)
- Complete CLI: `generate`, `audit`, `version`, `diff`, `orphans`, `e2e`
- Verify against fixtures/sample_ruby_project and self
- Exit codes correct, all subcommands functional
- **Target:** 13+ passing tests, all CLI commands work

### Phase 2 — Hierarchical Documentation & Agent API
- **New modules:** IndexGenerator, SummaryGenerator, MapGenerator, DependencyGraph, OrphanDetector
- **New templates:** index_template.erb, summary_template.erb, diagram_class_template.erb, diagram_er_template.erb
- **New query engine:** SymbolFinder, DependencyResolver, CoverageQuerier, SummaryQuerier
- **Expanded diagrams:** Class hierarchy diagrams, ER diagrams (when schema files present)
- **Expanded CLI:** `query` subcommand with --find-symbol, --find-dependents, --find-dependencies, --coverage, --summary
- **HTTP API:** serve command exposes /api/query endpoints
- **Output:** _index.md at every dir, SUMMARY.md per module root, map.json, richer diagrams
- **Target:** 40+ tests, all FR-2 through FR-10 satisfied (except embedding)

### Phase 3 — Semantic Search
- **New modules:** Embedder, Chunker, VectorStore, KeywordIndex, HybridRanker, SearchService
- **Dependencies:** FAISS binding, local embedding model (e.g., all-MiniLM-L6-v2 via ONNX or Ruby binding)
- **New CLI:** `search` subcommand with --hybrid, --semantic-only, --keyword-only
- **Output:** .autodoc/vector/ with FAISS index + metadata
- **Incremental:** Hash-based change detection for re-embedding only changed files
- **Target:** 55+ tests, FR-3, FR-6 satisfied

### Phase 4 — Polish & Ecosystem (Deferred)
- Multi-language support (tree-sitter for Python, JavaScript, TypeScript)
- Live file watcher for auto-regeneration
- Documentation diff preview
- IDE plugins and editor extensions
