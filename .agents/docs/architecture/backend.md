# Auto-Doc Tool — Backend Architecture

## Directory Layout

```
lib/auto_doc/
├── cli.rb              # Thor CLI (generate, audit, search, server, test)
├── config.rb           # Configuration loader
├── server.rb           # Sinatra server for docs serving
├── documentation_index.rb  # Unified .docs/ data access layer
├── search_service.rb   # Multi-strategy search engine
├── agent_query_service.rb # Agent query abstraction
├── transformer.rb      # Markdown transformation
├── errors.rb           # Custom errors
├── version.rb          # Gem version
├── llm/                # LLM integration
├── analyzer/           # Source code analysis
├── generator/          # Documentation generators
├── orchestrator/       # Pipeline orchestration
├── reporter/           # Audit/completeness reports
├── tester/             # E2E test runner
├── utils/              # Shared utilities
└── transformer/        # Markdown transformations
```

## Module Overview

### `cli.rb` — Command-Line Interface

Thor-based CLI with subcommands: `generate`, `audit`, `verify`, `search`, `server`, `test`. All CLI formatting and user-facing output is handled here. The CLI delegates core logic to `Orchestrator` and `Config`.

### `config.rb` — Configuration

Loads `.autodoc.yml` by walking up the directory tree from the target path. Merges file config with built-in defaults, then merges CLI overrides (which take precedence). Provides convenience accessors: `module_roots`, `exclude_patterns`, `output_dir`, `min_doc_coverage`, `llm_config`, `llm_primary?`.

Default config includes:
- Module roots: `app`, `lib`, `bin`
- Exclude patterns: `vendor/**/*`, `node_modules/**/*`, `spec/**/*`
- LLM default: `provider: openai`, `model: summarizer`, `primary: true`
- Output directory: `.docs`

### `documentation_index.rb` — Unified Data Access Layer

Provides a single interface to read all generated documentation artifacts (INDEX.md, VECTORS.json, SUMMARY.md, AGENTS.md, all markdown content) from a `.docs/` directory. Used by `SearchService` and agent query service.

### `search_service.rb` — Multi-Strategy Search Engine

Ranks results across multiple sources:
- **symbol_exact** (score 100): Exact symbol name match in INDEX.md
- **dependency_match** (score 80): Partial match in INDEX.md dependency columns
- **vector_keyword_high** (score 60): 3+ keyword overlap in vectors.json
- **vector_keyword_low** (score 40): 1-2 keyword overlap in vectors.json
- **vector_summary_match** (score 15): Full-text match in vector entry `summary` field
- **summary_text** (score 20): Full-text match in SUMMARY.md/AGENTS.md
- **source_grep** (score 10): Source file grep (opt-in via `source: true`)

Results are sorted by descending score and limited to the configured maximum.

### `server.rb` — Documentation Server

Sinatra server that serves generated documentation artifacts over HTTP. Supports the same search functionality as the CLI search command.

### `transformer.rb` — Markdown Transformation

Provides utilities for transforming and formatting markdown output during generation.

## LLM Submodule (`llm/`)

See `backend/llm.md` for detailed documentation.

## Analyzer Submodule (`analyzer/`)

See `backend/analyzer.md` for detailed documentation.

## Generator Submodule (`generator/`)

See `backend/generators.md` for detailed documentation.

## Orchestrator Submodule (`orchestrator/`)

See `backend/orchestrator.md` for detailed documentation.

## Reporter Submodule (`reporter/`)

See `backend/reporter.md` for detailed documentation.

## Utility Submodules

### `utils/yaml_config_loader.rb`
Safely loads YAML configuration files with error handling for missing or invalid files.

### `utils/file_tree_builder.rb`
Builds an indented file tree representation of a directory for use in AGENTS.md and other documentation.

### `utils/timestamp_tracker.rb`
Tracks file modification timestamps for incremental analysis. Identifies stale files that need re-analysis.

### `utils/output_formatter.rb`
Formats terminal output with colors and indentation.

### `utils/markdown_helper.rb`
Markdown formatting utilities used across generators and the search service.