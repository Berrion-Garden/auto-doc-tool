# Auto-Doc — Infrastructure

## Dependencies

### Runtime

| Dependency | Version | Purpose |
|------------|---------|---------|
| Ruby | >= 3.0.0 | Runtime |
| thor | ~> 1.0 | CLI framework |
| sinatra | ~> 4.0 | Web server |

### Development

| Dependency | Version | Purpose |
|------------|---------|---------|
| rake | ~> 13.0 | Build tool |
| rspec | — | Test framework |
| rack-test | — | HTTP testing |

### stdlib (no external gems)

| Module | Used By |
|--------|---------|
| `ripper` | `SourceParser` — Ruby AST parsing |
| `net/http` | `LLM::Client` — HTTP requests |
| `json` | `LLM::Client`, `VectorGenerator` — JSON serialization |
| `uri` | `LLM::Client` — URL parsing |
| `erb` | All generators — template rendering |
| `fileutils` | CLI, orchestrator, generators — file operations |
| `pathname` | CLI, orchestrator — path manipulation |
| `shellwords` | CLI — shell argument handling |
| `yaml` | Config — YAML config loading |
| `time` | Generators — timestamp generation |

## Boot Sequence

```
require 'auto_doc'
    │
    ├── auto_doc/version.rb → VERSION constant
    │
    ├── auto_doc/config.rb → Config class
    │   └── utils/yaml_config_loader.rb → YAML parser
    │
    ├── auto_doc/utils/* → Utility modules
    │
    ├── auto_doc/documentation_index.rb → Index builder
    │
    ├── auto_doc/analyzer/* → Analysis modules
    │   ├── analysis_cache.rb → Cache
    │   ├── source_parser.rb → Ripper parser
    │   ├── schema_parser.rb → Rails schema parser
    │   ├── model_association_parser.rb → Rails associations
    │   ├── import_extractor.rb → Import extraction
    │   ├── yard_reader.rb → YARD reader
    │   ├── analysis_pipeline.rb → Pipeline
    │   ├── diff_service.rb → Diff detection
    │   └── orphans_service.rb → Orphan finder
    │
    ├── auto_doc/llm.rb → LLM module loader
    │   ├── llm/client.rb → HTTP client
    │   └── llm/summarizer.rb → Prompt builder
    │
    ├── auto_doc/generator/* → Document generators
    │   ├── template_helper.rb → Template mixin
    │   ├── agents_md_generator.rb
    │   ├── readme_generator.rb
    │   ├── index_generator.rb
    │   ├── summary_generator.rb
    │   ├── vector_generator.rb
    │   ├── diagram_generator.rb
    │   ├── c4_diagram_generator.rb
    │   ├── class_diagram_generator.rb
    │   ├── erd_generator.rb
    │   ├── architecture_generator.rb
    │   └── map_generator.rb
    │
    ├── auto_doc/reporter/* → Reporting
    ├── auto_doc/search_service.rb → Search
    ├── auto_doc/agent_query_service.rb → Query
    ├── auto_doc/transformer.rb → Transform module loader
    │   ├── files_data_builder.rb
    │   ├── class_hierarchy_builder.rb
    │   ├── erd_relationship_builder.rb
    │   ├── container_data_flow_builder.rb
    │   └── graph_data_builder.rb
    │
    ├── auto_doc/orchestrator.rb → Orchestrator
    │
    ├── auto_doc/orchestrator/* → Pipeline steps
    │   ├── base_step.rb
    │   ├── agents_md_step.rb
    │   ├── readme_step.rb
    │   ├── index_summary_vectors_step.rb
    │   ├── diagram_step.rb
    │   ├── architecture_step.rb
    │   ├── manifest_step.rb
    │   └── pipeline.rb
    │
    ├── auto_doc/cli.rb → CLI (Thor)
    ├── auto_doc/tester/e2e_runner.rb → E2E tests
    └── auto_doc/server.rb → Sinatra server
```

## Development Setup

```bash
# Clone and install
git clone https://github.com/pik-ai/auto-doc
cd auto-doc
bundle install

# Run tests
bundle exec rspec

# Run end-to-end self-test
bundle exec rake e2e

# Run against a project
ruby -I lib exe/auto-doc generate path/to/project
ruby -I lib exe/auto-doc audit path/to/project

# Lint check
rubocop --lint lib/
```

## Configuration

### `.autodoc.yml`

```yaml
module_roots:
  - app
  - lib
  - bin

exclude_patterns:
  - vendor/**/*
  - node_modules/**/*
  - spec/**/*

output:
  directory: .docs
  format: markdown

audit:
  min_doc_coverage: 80
  max_module_size: 50

diagrams:
  generate_dag: true
  diagram_directory: diagrams

llm:
  provider: openai
  endpoint: https://llms.berrion.garden/v1
  api_key: autodoc
  model: summarizer
  timeout: 120
```

### LLM Configuration

The `llm:` section enables optional LLM-powered summarization for `SUMMARY.md` and `AGENTS.md` generation. When `endpoint` and `api_key` are both present and non-empty, LLM calls are attempted with graceful fallback to static inference on any failure. Default config uses `https://llms.berrion.garden/v1` with model `summarizer` and api_key `autodoc`.

Set `AUTO_DOC_DISABLE_LLM=true` to disable LLM calls regardless of config.

Config is discovered by walking up from the target directory. CLI flags override config values.

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `AUTO_DOC_TEMPLATE` | Override template path for AgentsMdGenerator |
| `AUTO_DOC_TEMPLATE_SUMMARY` | Override template path for SummaryGenerator |
| `AUTO_DOC_SERVE_DIR` | Target directory for serve mode (set by CLI) |
| `AUTO_DOC_DISABLE_LLM` | When set, disables all LLM calls in generators (falls back to static inference) |

## Deployment

The gem is packaged as `auto-doc-*.gem` and published to RubyGems.

```bash
# Build gem
gem build auto-doc.gemspec

# Install from source
gem install ./auto-doc-*.gem

# Global CLI
auto-doc generate
```

### CI Integration

```yaml
# .github/workflows/docs.yml
name: Documentation Check
on: [push, pull_request]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
      - run: gem install auto-doc
      - run: auto-doc verify --ci --threshold 80
```

## Performance Characteristics

- **Cold analysis** (193-file project): ~5-10 seconds
- **Cached analysis** (warm): ~0.03 seconds (173x faster)
- **Incremental generation**: Only re-analyses changed files
- **Analysis cache scope**: In-process only (not persisted to disk)