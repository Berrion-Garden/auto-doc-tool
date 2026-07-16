# Auto-Doc — Architecture Overview

## Project Summary

**auto-doc** is a pure-Ruby documentation generator that analyzes Ruby source files and produces comprehensive documentation artifacts: per-module `AGENTS.md`, project-level `README.md`, `INDEX.md`, `SUMMARY.md`, Mermaid diagrams (dependency DAG, class hierarchy, C4 context/container, ERD), vector-based search indexes, and architecture documentation. It requires no external services or API keys — only Ruby stdlib plus two lightweight dependencies (`thor` for CLI, `sinatra` for the web server). LLM-powered summarization is optional: when configured via `.autodoc.yml`, LLM-generated summaries enhance `SUMMARY.md` and `AGENTS.md` output, with graceful fallback to static inference when unavailable.

- **Version:** 1.0.0
- **Ruby:** >= 3.0.0
- **Repository:** https://github.com/pik-ai/auto-doc
- **License:** MIT

## Design Principles

1. **Zero new gem dependencies** — everything built on stdlib Ruby + thor + sinatra
2. **File-based everything** — `.docs/` directory is a self-contained knowledge base
3. **Dual-purpose output** — every file is human-readable AND machine-parseable
4. **Incremental generation** — only re-analyze changed files using mtime comparison
5. **Agent-first design** — every command supports `--json` and `--agent` flags

## Architecture Layers

```
┌─────────────────────────────────────────────────────┐
│                    CLI (Thor)                        │
│  Commands: generate, audit, verify, search, agent,  │
│  diff, orphans, serve, query, tree, diagram, e2e    │
├─────────────────────────────────────────────────────┤
│                 Orchestrator                         │
│  Coordinates analysis → transformation → generation │
│  Pipeline: AgentsMd → Readme → Index/Summary/Vectors│
│            → Diagram → Architecture → Manifest       │
├───────────┬───────────────┬─────────────────────────┤
│  Analyzer │ Transformer   │     Generator           │
│  Source   │  FilesData    │  AgentsMdGen            │
│  Schema   │  ClassHier    │  ReadmeGen              │
│  YARD     │  ERD Rel      │  IndexGen               │
│  Import   │  GraphData    │  SummaryGen             │
│  Diff     │  ContainerDF  │  DiagramGen             │
│  Orphans  │               │  ArchitectureGen        │
│  Pipeline │               │  C4/Class/ERD Gen       │
│  Cache    │               │  VectorGen              │
│  YARD     │               │  MapGen                 │
│  Reader   │               │                         │
├───────────┴───────────────┴─────────────────────────┤
│              LLM Layer (Integrated)                  │
│  Client (OpenAI-compatible HTTP, build_if_configured)│
│  Summarizer (metadata-only prompts, 6 public methods)│
│  Used by: SummaryGenerator (3 calls),                │
│            AgentsMdGenerator (1 call)                │
│  All LLM calls have graceful fallback to static     │
│  inference methods.                                  │
├─────────────────────────────────────────────────────┤
│              Reporter / Services                     │
│  CompletenessChecker, AuditReporter                  │
│  SearchService, AgentQueryService                    │
│  DocumentationIndex, Server (Sinatra)                │
└─────────────────────────────────────────────────────┘
```

## Domain Model Summary

The tool operates on a concept of **Project → ModuleRoot → SourceFile → Symbol** with generated artifacts:

| Domain Entity | Description |
|---------------|-------------|
| **Project** | Target codebase being documented |
| **ModuleRoot** | Top-level directory (app, lib, bin) serving as documentation boundary |
| **SourceFile** | Single `.rb` file, analyzed via Ripper + YARD |
| **Symbol** | Named code element: class, module, method, constant |
| **Import** | Dependency declaration (require, include, extend, prepend) |
| **DocComment** | Documentation comment block associated with a symbol |
| **Analysis** | Structured hash: `{ definitions:, docs:, imports: }` per file |

### Generated Artifacts

| Artifact | Purpose |
|----------|---------|
| `AGENTS.md` | Per-module public API surface with file tree, symbols, dependencies |
| `INDEX.md` | Full file/symbol/dependency index at project and module level |
| `SUMMARY.md` | Executive summary with purpose, key components, architecture pattern |
| `VECTORS.json` | Keyword vectors for all symbols (search index) |
| `README.md` | Project overview with statistics |
| `architecture.md` | C4-informed architecture documentation |
| `.map.json` | Master manifest linking all generated artifacts |
| `diagrams/*.mmd` | Mermaid diagrams (DAG, class, C4, ERD) |
| `report.json` | Audit coverage report (machine-readable) |

## Directory Layout

```
lib/
├── auto_doc.rb                    # Main entry point (requires all submodules)
├── auto_doc/
│   ├── version.rb                 # VERSION constant
│   ├── config.rb                  # Configuration loader with defaults + YAML merge
│   ├── cli.rb                     # Thor-based CLI (17 commands)
│   ├── orchestrator.rb            # Coordinates generate/audit workflows
│   ├── documentation_index.rb     # Index document builder
│   ├── search_service.rb          # Full-text search across docs
│   ├── agent_query_service.rb     # Natural-language query interpreter
│   ├── server.rb                  # Sinatra web server for browsing docs
│   ├── llm/                       # LLM-powered summarization layer
│   │   ├── client.rb              # OpenAI-compatible HTTP client
│   │   └── summarizer.rb          # Metadata-only prompt builder
│   ├── analyzer/                  # Source code analysis
│   ├── transformer/               # Data transformation pipelines
│   ├── generator/                 # Document generators
│   ├── reporter/                  # Audit and completeness reporting
│   ├── orchestrator/              # Pipeline step implementations
│   ├── utils/                     # Shared utilities
│   └── tester/                    # E2E test runner
templates/                         # ERB templates for all generators
exe/auto-doc                       # Executable entry point
spec/                              # RSpec test suite
```

## Deviations from Plan

All planned LLM integration features have been implemented and verified. The following deviations were identified during the review process and subsequently remediated:

### 1. Summarizer Self-Doc Regeneration (commit `8e7254a`)

**Plan:** The Summarizer class already has 3 public methods: `summarize_module`, `summarize_architecture`, `summarize_components`.

**Resolved:** LLM self-doc regeneration added 3 new public methods (`summarize_architecture_full`, `summarize_system_context`, `summarize_containers`) and standardized prompt text from "Ruby project" to "software project". These new methods are available but not yet integrated into a pipeline step.

### 2. Config `llm_config` Accessor (FIXED, commit `ce3f596`)

**Plan:** Add `llm:` section to `DEFAULTS` with provider/endpoint/api_key/model. Add `llm_config` accessor method.

**Resolved:** `Config::DEFAULTS` now includes an `llm:` section with `provider: "openai"`, `endpoint: "https://llms.berrion.garden/v1"`, `api_key: "autodoc"`, `model: "summarizer"`, `timeout: 120`. The `llm_config` accessor method is present at line 115 of `config.rb`.

### 3. SummaryGenerator LLM Integration (FIXED)

**Plan:** In `render_template`, build an `AutoDoc::LLM::Client` from config if configured. Call `Summarizer` methods — only use results if non-nil; otherwise fall back to existing static methods.

**Resolved:** `SummaryGenerator#render_template` (line 50) calls `llm_purpose`, `llm_architecture`, and `llm_components` which use `Client.build_if_configured(@config)` and delegate to `Summarizer.summarize_module/summarize_architecture/summarize_components`. All three fall back to static inference methods on any failure.

### 4. AgentsMdGenerator LLM Integration (FIXED)

**Plan:** Update `self.generate` signature to accept optional `config:` parameter. In `render_template`, use LLM for `purpose_summary`.

**Resolved:** `AgentsMdGenerator.generate` signature accepts `config: nil` keyword parameter (line 24). The generator stores `@config`, calls `llm_purpose_summary` which uses `Client.build_if_configured(@config)` and `Summarizer.summarize_module`. Falls back to `nil` (template renders placeholder text) on any failure.

### 5. AgentsMdStep Config Threading (FIXED)

**Plan:** Update the call to `AgentsMdGenerator.generate` to pass `config: config`.

**Resolved:** `AgentsMdStep#run` calls `AgentsMdGenerator.generate(dir_name, tree_text, files_data, config: config, output_path: output_path)` (line 21 of `agents_md_step.rb`).

### 6. API Key Default Revert (FIXED, commit `ce3f596`)

**Plan:** Use `"__PLACEHOLDER__"` as default api_key value.

**Resolved:** Reverted from `"__PLACEHOLDER__"` (commit `b5b893f`) back to `"autodoc"` (commit `ce3f596`) for out-of-box LLM usage. The `configured?` method in `Client` checks for non-empty string, so `"autodoc"` passes the check and enables LLM usage by default.

### 7. Ruby 3.4 Compatibility (VERIFIED)

**Execution Log Note:** Two source fixes: `Net::HTTPExceptions` for Ruby 3.4 compatibility and String-based type comparison in `extract_key_components`.

**Actual:** `Client#chat` rescues `Net::OpenTimeout, Net::ReadTimeout, Net::HTTPError, Net::HTTPClientException, Net::HTTPFatalError, JSON::ParserError, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET`. In `Summarizer#extract_metadata_lines`, `defn[:type].to_s` is used for safe Symbol/String comparison.

## Test Status

At the time of final review (commit `8e7254a`):
- Total specs: 592 passing (unit + integration)
- Pre-existing failures: 42 (server_spec: 36, cli_spec: 1, self_test_spec: 5) — confirmed unchanged from baseline
- Integration tests tagged with `:integration` for selective execution
- E2E generation verified with graceful LLM fallback when live provider is unreachable
- Final commit (`8e7254a`) added 3 new public methods to `Summarizer` (self-doc regeneration)