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
│              LLM Layer (Off by Default)              │
│  Client (OpenAI-compatible HTTP, build_if_configured)│
│  PromptBuilder (8 generator types)                   │
│  Summarizer (delegates to PromptBuilder+ResponsePars)│
│  ResponseParser (markdown/JSON/bullet parsing)       │
│  Gated by llm_primary? (false by default)            │
│  Used by: SummaryGenerator (3 calls when primary),   │
│            ArchitectureGenerator (1 call),           │
│            AgentsMdGenerator (1 call),               │
│            ReadmeGenerator (1 call)                  │
│  Primary mode: LLM first → static fallback on fail   │
│  Non-primary mode: zero LLM calls (static only)      │
├─────────────────────────────────────────────────────┤
│              Reporter / Services                     │
│  CompletenessChecker, AuditReporter                  │
│  SearchService, AgentQueryService                    │
│  DocumentationIndex, Server (Sinatra)                │
└─────────────────────────────────────────────────────┘
```

## Inverted LLM Priority Architecture

All LLM integration follows the **Inverted Priority Pattern** — rather than always attempting LLM and silently falling back to static analysis, LLM usage is **off by default** (`llm.primary: false`) and only activates when `--llm-primary` is passed (or `llm.primary: true` is set in config). This ensures backward compatibility and zero unexpected network calls.

### Key Design Decisions

1. **LLM Primary Gate (`llm_primary?`)** — Each generator checks `llm_primary?` before making any LLM call. When `false` (default), zero LLM calls are made — generators use pure static analysis.
2. **Graceful Degradation** — When `llm.primary: true`, generators try LLM first on each section. On failure (timeout, error, empty response), they log a warning via `warn_llm_fallback` and fall through to the same static analysis used in non-primary mode.
3. **Single LLM Call per Generator** — `ArchitectureGenerator` uses one LLM call for the full structured overview (purpose, style, modules, data flows); `SummaryGenerator` uses up to 3 calls (purpose, architecture, components); `AgentsMdGenerator` and `ReadmeGenerator` use 1 call each.
4. **TemplateHelper Mixin** — Shared `llm_primary?` and `warn_llm_fallback` methods in one place, included by all four LLM-aware generators.
5. **PromptBuilder + ResponseParser** — Prompt construction and response parsing were extracted from `Summarizer` into dedicated classes for testability and separation of concerns.

### LLM Call Flow

```
Generator.render_template
    │
    ├── llm_primary? == false
    │       └── Use static analysis (zero LLM calls, backward compatible)
    │
    └── llm_primary? == true
            │
            ├── Client.build_if_configured(config)
            │       └── nil → warn_llm_fallback + static fallback
            │
            ├── Summarizer.summarize_*(...)  →  PromptBuilder.build(...)
            │       └── nil/exception → warn_llm_fallback + static fallback
            │
            └── ResponseParser.parse_*(response)
                    └── Use parsed LLM result (replaces static inference)
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
│   │   ├── summarizer.rb          # Delegates to PromptBuilder + ResponseParser
│   │   ├── prompt_builder.rb      # Prompt construction (8 generator types)
│   │   └── response_parser.rb     # Response parsing (markdown/JSON/bullets)
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

### LLM Primary Driver Architecture (Project: `2026-07-16-llm-primary-driver-architecture`)

This project refactored the LLM integration from a "try LLM first, silently fall back" pattern to an **Inverted Priority Pattern** where LLM is off by default (`llm.primary: false`) and only activates when explicitly enabled.

**Completed milestone:** LLM Primary Driver Architecture (06e6d3d → 4c04a36, remediated in a6430ae)

**Changes implemented:**
1. **Config layer:** Added `llm: { primary: false }` default and `llm_primary?` accessor to `AutoDoc::Config`
2. **CLI:** Added `--llm-primary` flag to `generate`, `verify`, and `audit` commands; `cli_overrides` maps to `{ llm: { primary: true } }`
3. **TemplateHelper mixin** (`generator/template_helper.rb`): Added `llm_primary?` gate (checks `@auto_doc_config` then `@config`) and `warn_llm_fallback` for consistent stderr warnings
4. **All 4 LLM-aware generators** now use `llm_primary?` gate — non-primary mode makes zero LLM calls
5. **ArchitectureGenerator** LLM call wrapped in `begin/rescue StandardError` with full fallback to static mode
6. **ArchitectureGenerator** parsing centralized through `Summarizer.parse_architecture_modules` and `Summarizer.parse_architecture_data_flows`
7. **PromptBuilder** (`llm/prompt_builder.rb`): Extracted prompt construction (8 generator types: agents_md, summary, architecture, components, architecture_full, system_context, containers, readme)
8. **ResponseParser** (`llm/response_parser.rb`): Extracted response parsing (markdown headings, JSON arrays, bullet lists)
9. **Summarizer** refactored to delegate to PromptBuilder and ResponseParser; added `parse_architecture_modules` and `parse_architecture_data_flows` methods
10. **ReadmeGenerator**: New signature accepts `config:` and `analyses:` kwargs; LLM enhancement for `overview_text`
11. **ReadmeStep**: Forwards config and analyses to ReadmeGenerator
12. **ArchitectureStep**: Forwards `auto_doc_config` and `analyses` to ArchitectureGenerator
13. **IndexSummaryVectorsStep/AgentsMdStep**: Forward config from context to generators
14. **DiagramStep**: LLM calls for C4 context/container gated behind `config.llm_primary?`
15. **Pipeline context**: Includes `@config` (AutoDoc::Config instance), `all_classes`, `all_methods`, `coverage_pct`

**Deviations from original plan (remediated in review):**
- **M1 (ArchitectureGenerator LLM gating)**: LLM block was initially not gated by `config.llm_primary?`. Fixed in remediation: gate is now `llm_primary? && @auto_doc_config && @analyses`.
- **M2 (ArchitectureGenerator parsing coupling)**: Parse methods were duplicated inline in ArchitectureGenerator. Fixed: centralized through `Summarizer.parse_architecture_modules` and `Summarizer.parse_architecture_data_flows`, which delegate to `ResponseParser`.
- **M3 (ArchitectureGenerator exception handling)**: No rescue wrapping. Fixed: entire LLM block wrapped in `begin/rescue StandardError` with full static fallback.
- **M5 (Integration test for ArchitectureGenerator primary mode)**: Missing. Fixed: primary-mode integration test added.
- **M4, M6 (CLI flag)**: `--llm-primary` was missing from `verify` and `audit` commands. Fixed: added to all three commands.
- **M8 (DiagramStep LLM test)**: DiagramStep LLM calls untested. Acceptable: calls are in orchestrator layer, properly gated and routed through Summarizer. Noted for future improvement.

### 1. Summarizer Self-Doc Regeneration (commit `8e7254a`)

**Plan:** The Summarizer class already has 3 public methods: `summarize_module`, `summarize_architecture`, `summarize_components`.

**Resolved:** LLM self-doc regeneration added 3 new public methods (`summarize_architecture_full`, `summarize_system_context`, `summarize_containers`) and standardized prompt text from "Ruby project" to "software project". These were later refactored during the LLM Primary Driver Architecture project to delegate to `PromptBuilder` and `ResponseParser`.

### 2. Config `llm_config` Accessor (FIXED, commit `ce3f596`)

**Plan:** Add `llm:` section to `DEFAULTS` with provider/endpoint/api_key/model. Add `llm_config` accessor method.

**Resolved:** `Config::DEFAULTS` now includes an `llm:` section with `provider: "openai"`, `endpoint: "https://llms.berrion.garden/v1"`, `api_key: "autodoc"`, `model: "summarizer"`, `timeout: 120`, `primary: false`. The `llm_config` accessor method is present alongside `llm_primary?`.

### 3. SummaryGenerator LLM Integration (FIXED, refactored in primary driver project)

**Plan:** In `render_template`, build an `AutoDoc::LLM::Client` from config if configured. Call `Summarizer` methods — only use results if non-nil; otherwise fall back to existing static methods.

**Resolved:** LLM calls now gated behind `llm_primary?`. In primary mode, attempts LLM with fallback via `warn_llm_fallback`. In non-primary mode, uses only static inference (zero LLM calls).

### 4. AgentsMdGenerator LLM Integration (FIXED, refactored in primary driver project)

**Plan:** Update `self.generate` signature to accept optional `config:` parameter. In `render_template`, use LLM for `purpose_summary`.

**Resolved:** Now uses `llm_primary?` gate. In primary mode, calls `llm_purpose_summary` with `warn_llm_fallback` on failure. In non-primary mode, `purpose_summary` is always the static placeholder.

### 5. AgentsMdStep Config Threading (FIXED)

**Plan:** Update the call to `AgentsMdGenerator.generate` to pass `config: config`.

**Resolved:** `AgentsMdStep#run` calls `AgentsMdGenerator.generate(dir_name, tree_text, files_data, config: config, output_path: output_path)`.

### 6. API Key Default Revert (FIXED, commit `ce3f596`)

**Plan:** Use `"__PLACEHOLDER__"` as default api_key value.

**Resolved:** Reverted from `"__PLACEHOLDER__"` back to `"autodoc"` for out-of-box LLM usage.

### 7. Ruby 3.4 Compatibility (VERIFIED)

**Execution Log Note:** Two source fixes: `Net::HTTPExceptions` for Ruby 3.4 compatibility and String-based type comparison in `extract_key_components`.

**Actual:** `Client#chat` rescues `Net::OpenTimeout, Net::ReadTimeout, Net::HTTPError, Net::HTTPClientException, Net::HTTPFatalError, JSON::ParserError, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET`. In `Summarizer#extract_metadata_lines`, `defn[:type].to_s` is used for safe Symbol/String comparison.

## Test Status

At the time of LLM Primary Driver Architecture final review (commit `4c04a36`, remediated in `a6430ae`):
- Total specs: 721 passing (unit + integration)
- Pre-existing failures: unchanged from baseline
- Integration tests tagged with `:integration` for selective execution
- New shared test helper `spec/support/llm_mock_helper.rb` provides `mock_llm_client`, `primary_llm_config`, `standard_llm_config` for LLM-related tests
- E2E generation verified in both primary and non-primary modes