# Auto-Doc Tool — Infrastructure

## Dependencies

### Runtime Dependencies

- **Ruby** — The gem requires a Ruby interpreter (MRI or compatible)
- **Parser** — Ruby AST parser used by `SourceParser`
- **YARD** — YARD documentation extraction (`YardReader`)
- **Thor** — CLI framework (exe/auto-doc)
- **Sinatra** — Web server for docs serving
- **Rack::Test** — HTTP test framework (test dependency)

### Standard Library Only (LLM Client)

The LLM client (`lib/auto_doc/llm/client.rb`) uses only Ruby standard library:
- `Net::HTTP` — HTTP client
- `JSON` — JSON parsing
- `URI` — URL parsing

No external HTTP gem (Faraday, HTTParty, etc.) is required.

## Boot Sequence

```
require 'auto_doc'  # or require 'auto-doc'
    │
    └→ lib/auto_doc.rb:
         ├→ version.rb
         ├→ config.rb
         ├→ errors.rb
         ├→ utils/*.rb (yaml_config_loader, file_tree_builder, timestamp_tracker, output_formatter, markdown_helper)
         ├→ documentation_index.rb
         ├→ analyzer/*.rb (analysis_cache, source_parser, schema_parser, model_association_parser, import_extractor, yard_reader, analysis_pipeline, diff_service, orphans_service, generic_scanner)
         ├→ llm.rb
         │    └→ llm/*.rb (client, summarizer, prompt_builder, response_parser, enricher)
         ├→ generator/*.rb (template_helper, all generators)
         ├→ reporter/*.rb (completeness_checker, audit_reporter)
         ├→ search_service.rb
         ├→ agent_query_service.rb
         ├→ transformer.rb
         ├→ orchestrator.rb
         ├→ orchestrator/*.rb (metrics_helper, base_step, all steps, pipeline)
         ├→ cli.rb
         ├→ tester/e2e_runner.rb
         └→ server.rb
```

All submodules are required at gem load time. The gem is designed to be loaded once at application startup.

## CLI Entry Point

```bash
exe/auto-doc generate <path> [options]   # Generate documentation
exe/auto-doc audit <path> [options]      # Audit documentation coverage
exe/auto-doc search <path> <term>        # Search generated docs
exe/auto-doc server <path> [options]     # Start docs server
exe/auto-doc test <path>                 # Run E2E tests
```

All CLI commands delegate to the appropriate service class (Orchestrator, SearchService, Server, E2ERunner).

## Configuration

### Default Configuration

Built into `Config::DEFAULTS`:

```ruby
{
  module_roots: %w[app lib bin],
  exclude_patterns: %w[vendor/**/* node_modules/**/* spec/**/*],
  output: { directory: ".docs", format: "markdown" },
  audit: { min_doc_coverage: 80, max_module_size: 50 },
  diagrams: { generate_dag: true, diagram_directory: "diagrams" },
  llm: {
    provider: "openai",
    endpoint: "https://llms.berrion.garden/v1",
    api_key: "autodoc",
    model: "summarizer",
    timeout: 120,
    primary: true,
    fail_fast: false
  }
}
```

### Config Loading

1. Walk up from target directory looking for `.autodoc.yml`
2. Merge file config with defaults
3. Merge CLI overrides on top (highest precedence)

### Environment Variables

- `AUTO_DOC_DISABLE_LLM` — Disables all LLM calls when set

## Output Directory Convention

Generated documentation goes to `<output_dir>/` (default: `.docs/`).

Structure within output dir:
```
.docs/
├── INDEX.md                          # Project-level symbol index
├── SUMMARY.md                        # Project-level summary
├── VECTORS.json                      # Project-level vector index
├── map.json                          # Cross-reference map
├── architecture.md                   # Architecture documentation
├── AGENTS.md                         # Project-level agents doc
├── README.md                         # Project README
├── diagrams/                         # Mermaid diagrams
│   ├── deps.mmd
│   ├── class.mmd
│   └── er.mmd
├── app/                              # Per-module-root directories
│   ├── INDEX.md
│   ├── SUMMARY.md
│   ├── vectors.json
│   └── AGENTS.md
└── lib/
    ├── INDEX.md
    ├── SUMMARY.md
    ├── vectors.json
    └── AGENTS.md
```

## Incremental Analysis

Uses `TimestampTracker` to track file modification times. On incremental runs (`--incremental`):

1. Compare current file mtimes against stored timestamps
2. Re-analyze only stale (changed) files
3. Skip in-process cache for incremental runs

The analysis cache (`AnalysisCache`) is in-process only and cleared between test runs.

## Deployment

The gem is distributed as a Ruby gem package:
- `auto-doc.gemspec` — Gem specification
- `auto-doc-*.gem` — Built gem files

Install via:
```bash
gem install auto-doc
```

Or from local build:
```bash
gem build auto-doc.gemspec
gem install ./auto-doc-*.gem
```