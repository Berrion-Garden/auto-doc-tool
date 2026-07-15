# Testing

## Framework

RSpec 3.x with `spec_helper.rb` (standard Rails gem layout).

## Test Files

| File | Purpose |
|------|---------|
| `spec/auto_doc_spec.rb` | Top-level gem load test |
| `spec/e2e/self_test_spec.rb` | E2E self-test integration spec |

### CLI

| File | Tests |
|------|-------|
| `spec/auto_doc/cli_spec.rb` | Thor CLI subcommand registration, help text |

### Analyzers

| File | Tests |
|------|-------|
| `spec/auto_doc/analyzer/source_parser_spec.rb` | Class/module/method parsing from Ruby source |
| `spec/auto_doc/analyzer/import_extractor_spec.rb` | require/include/extend/prepend extraction |
| `spec/auto_doc/analyzer/yard_reader_spec.rb` | YARD comment extraction |
| `spec/auto_doc/analyzer/schema_parser_spec.rb` | Rails schema.rb table extraction |
| `spec/auto_doc/analyzer/model_association_parser_spec.rb` | Rails model association extraction |

### Generators

| File | Tests |
|------|-------|
| `spec/auto_doc/generator/agents_md_generator_spec.rb` | AGENTS.md generation |
| `spec/auto_doc/generator/readme_generator_spec.rb` | README.md generation |
| `spec/auto_doc/generator/index_generator_spec.rb` | INDEX.md generation |
| `spec/auto_doc/generator/summary_generator_spec.rb` | SUMMARY.md generation |
| `spec/auto_doc/generator/vector_generator_spec.rb` | VECTORS.json generation |
| `spec/auto_doc/generator/diagram_generator_spec.rb` | Dependency DAG diagram generation |
| `spec/auto_doc/generator/class_diagram_generator_spec.rb` | Class diagram generation |
| `spec/auto_doc/generator/erd_generator_spec.rb` | ERD diagram generation |
| `spec/auto_doc/generator/c4_diagram_generator_spec.rb` | C4 diagram generation |
| `spec/auto_doc/generator/architecture_generator_spec.rb` | architecture.md generation |

### Reporters

| File | Tests |
|------|-------|
| `spec/auto_doc/reporter/audit_reporter_spec.rb` | Audit report generation and formatting |
| `spec/auto_doc/reporter/completeness_checker_spec.rb` | Coverage percentage calculation |

### Utils

| File | Tests |
|------|-------|
| `spec/auto_doc/utils/yaml_config_loader_spec.rb` | YAML file reading with error handling |
| `spec/auto_doc/utils/file_tree_builder_spec.rb` | Tree text generation |
| `spec/auto_doc/utils/timestamp_tracker_spec.rb` | Manifest-based incremental tracking |
| `spec/auto_doc/utils/output_formatter_spec.rb` | Text/JSON/Agent mode formatting |

### Server

| File | Tests |
|------|-------|
| `spec/auto_doc/server_spec.rb` | Sinatra route handling via rack-test |

### Search

| File | Tests |
|------|-------|
| `spec/auto_doc/search_service_spec.rb` | Full-text search across docs |

## Test Strategy

- **Unit tests**: Each analyzer, generator, reporter, and utility class has a corresponding spec file. Tests verify the class's primary method(s) with realistic fixtures.
- **E2E test**: `E2ERunner` runs `auto-doc generate` and `auto-doc audit` against itself via subprocess, then validates output artifacts exist and contain expected content.
- **Integration test**: `spec/e2e/self_test_spec.rb` runs the same E2E self-test as the CLI `e2e` command, verifying the full pipeline end-to-end.
- **Server tests**: Use `Rack::Test::Methods` to make HTTP requests against the Sinatra server and verify response bodies.

## Running Tests

```bash
rspec
rspec spec/auto_doc/analyzer/source_parser_spec.rb  # single file
rspec spec/ --format documentation  # verbose
```

## Test Data

Tests use inline Ruby source strings and mock analysis results. No external project fixtures are required — all test data is defined within the spec files themselves.