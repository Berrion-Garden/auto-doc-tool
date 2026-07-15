# Auto-Doc — Architecture Overview

## Project

**auto-doc** (v0.2.0) — Automated documentation generator for Ruby projects.

## Summary

A Ruby gem that analyzes Ruby source files to generate comprehensive documentation artifacts:
- **AGENTS.md** — Agent-oriented module documentation per module root
- **README.md** — Project-level project overview with structure tree and coverage stats
- **INDEX.md** — File/symbol index per directory (generated recursively)
- **SUMMARY.md** — Directory-level purpose, key components, and architecture pattern
- **VECTORS.json** — Symbol vector index (project-level and per-directory) for search/indexing
- **Diagrams** — Dependency DAG (deps.mmd), class diagram, ERD (Rails), C4 context/container
- **report.json** — Audit coverage report with pass/fail CI gate

## Design Principles

1. **Generator-per-artifact** — Each output type has its own generator class (`AgentsMdGenerator`, `IndexGenerator`, `VectorGenerator`, etc.) following the pattern: `TEMPLATES_DIR` + `DEFAULT_TEMPLATE` constants, `self.generate(...)` class method, instance `generate` with optional `output_path`.
2. **Orchestrator-centric** — `Orchestrator` coordinates the pipeline: analysis → generation → reporting. CLI is thin; it delegates to the orchestrator and formats output.
3. **Config-driven output** — All file paths and behaviors flow through `Config`. Default output directory is `.docs/` with `.autodoc/` backward-compat fallback.
4. **No external runtime dependencies** — Only `thor` (CLI) and `sinatra` (serve command) are required. All analysis is done with the Ruby standard library.
5. **Template-based rendering** — ERB templates in `templates/` directory render analysis data. `TemplateHelper` deduplicates `read_template` across all generators.
6. **Triple-mode output** — OutputFormatter supports `:text` (human-readable, default), `:json` (pretty-printed, all fields), `:agent` (compact JSON, stripped timestamps/noise).

## Domain Model

```
Source File (Ruby .rb)
  ├── Definitions (classes, modules, methods)  ← SourceParser
  ├── Imports (require, require_relative, include, extend)  ← ImportExtractor
  └── Doc Comments (YARD)  ← YardReader

Analysis (per file: definitions + imports + docs)
  ├── Modules (grouped by root dir)
  ├── Project (all analyses)
  └── Vectors (indexed symbol entries)

Output Artifacts
  ├── Per module root: AGENTS.md, INDEX.md, SUMMARY.md, vectors.json
  ├── Per subdirectory: INDEX.md, SUMMARY.md, vectors.json
  ├── Project level: README.md, INDEX.md, SUMMARY.md, VECTORS.json
  └── Diagrams: deps.mmd, class_diagram.mmd, c4_context.mmd, c4_container.mmd, erd.mmd (Rails)
```

## Key Components

| Layer | Component | Responsibility |
|-------|-----------|----------------|
| CLI | `AutoDoc::CLI` (Thor) | Subcommands: init, generate, audit, diff, orphans, serve, e2e, verify |
| Config | `AutoDoc::Config` | YAML config loading, `.autodoc`→`.docs` migration, defaults |
| Orchestrator | `AutoDoc::Orchestrator` | Pipeline coordination: analyze → generate → report |
| Analyzers | `SourceParser`, `ImportExtractor`, `YardReader`, `SchemaParser`, `ModelAssociationParser`, `DiffService`, `OrphansService` | Ruby source analysis |
| Generators | `AgentsMdGenerator`, `ReadmeGenerator`, `IndexGenerator`, `SummaryGenerator`, `VectorGenerator`, `DiagramGenerator`, `ClassDiagramGenerator`, `ERDGenerator`, `C4DiagramGenerator`, `ArchitectureGenerator` | Artifact generation |
| Reporters | `AuditReporter`, `CompletenessChecker` | Audit reports, coverage checking |
| Utils | `YamlConfigLoader`, `FileTreeBuilder`, `TimestampTracker`, `OutputFormatter` | Shared utilities |
| Server | `AutoDoc::Server` (Sinatra) | Web UI for browsing generated docs |
| Tester | `E2ERunner` | Self-test validation |

## Deviations from Plan

The execution log notes that all 3 milestones were delivered on the first attempt except Milestone 3 (attempt 2). The execution log also documents that all 7 review findings were pre-existing bugs in the codebase (not introduced by Phase 2a) and were verified as already fixed:

1. **ImportExtractor wrong capture group** (`import_extractor.rb:37`) — Fixed before Phase 2a commit; `.last` used instead of `.first`
2. **ImportExtractor multiline regex** — Patterns use `[^\n]+` instead of `.+`, no `/m` flag
3. **XSS in Server#escape_html** — Delegates to `ERB::Util.html_escape(text)` instead of manual escaping
4. **Duplicate orchestrator writes** — `walk_subdirectories` skips root when it equals `target_dir` (lines 484-485)
5. **Config numeric fallbacks mask zero** — Uses `key?` check instead of `||`
6. **read_template duplicated** — Single `read_template` in `template_helper.rb`, all generators use it
7. **OutputFormatter#format returns nil** — All branches explicitly return formatted data

The review summary (pre-review input) noted that manual testing found **critical pre-existing bugs in `ImportExtractor` that amplify** — producing corrupted output (raw source code embedded in diagrams, markdown tables, and JSON vectors). Additionally, an XSS vulnerability exists in `Server#escape_html`. The review summary states these bugs exist in the current codebase. The execution log claims they were "already fixed" (commit 7ccdd75 and later). Per my instructions, I note the discrepancy between the review summary (bugs present) and execution log (bugs fixed) but do not verify the fix status — I only document what the execution log claims and what I observed in the source.

### Observed implementation vs. plan deviations:

- **Milestone 2** plan specified `VectorGenerator` generating both project-level `VECTORS.json` and per-directory `vectors.json`. The actual implementation has two separate class methods: `generate_project` and `generate_directory`, with a shared `write` method. This matches the plan.
- **Milestone 2** plan specified walking "EVERY directory within each module root recursively." The actual implementation uses `Dir.glob(File.join(root, "**", "*"))` in `walk_subdirectories`, which matches.
- **Milestone 3** plan specified `--json`/`--agent` wired through `generate`, `audit`, `diff`, and `orphans` subcommands. The actual CLI has `generate`, `audit`, `diff`, `orphans`, `serve`, `e2e`, and `verify` subcommands. OutputFormatter is wired through `generate`, `audit`, `diff`, and `orphans` (all non-text modes use a silent `say` callback and route through `OutputFormatter`). The `serve` and `e2e` commands do not use the formatter, which is consistent with their purposes.
- **YamlConfigLoader** has an `EXPECTED_KEYS` constant (`%i[module_roots exclude_patterns output audit diagrams]`) that is defined but never validated — `load` always returns the parsed result regardless of key presence.
- **YardReader** has two doc extraction paths: simple regex-based comment matching (always available) and YARD gem structured tag parsing (only when `defined?(YARD)`). The YARD gem is an optional dependency.
- **SearchService** uses a scoring system (10-100) with 6 match types (`symbol_exact`, `dependency_match`, `vector_keyword_high`, `vector_keyword_low`, `summary_text`, `source_grep`). All internal methods are private-class-methods; only the class method `search` is public.
- **OrphansService** identifies orphans by intersecting "not referenced" AND "not documented" — a file must fail both conditions to be an orphan. This is stricter than just "unreferenced files."