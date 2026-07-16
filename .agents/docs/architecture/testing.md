# Auto-Doc — Testing Strategy

## Test Framework

- **RSpec** 3.x with `rspec-core`, `rspec-expectations`, `rspec-mocks`
- **Rack::Test** for HTTP integration tests (server specs)
- Test fixtures in `fixtures/` directory

## Spec Configuration (`spec/spec_helper.rb`)

```ruby
RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.mock_with :rspec { |m| m.verify_partial_doubles = true }
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.profile_examples = 10

  # Clear analysis cache between every test
  config.before(:each) { AutoDoc::Analyzer::AnalysisCache.clear! }
end
```

## Test Suite Inventory

### Unit Tests

| Spec File | Target | Coverage |
|-----------|--------|----------|
| `spec/auto_doc/llm_spec.rb` | `AutoDoc::LLM`, `Client`, `Summarizer` constants | Module loading |
| `spec/auto_doc/config_spec.rb` | `Config.load`, defaults, YAML merge, CLI overrides, output_dir fallback | Full |
| `spec/auto_doc/generator/summary_generator_spec.rb` | `SummaryGenerator.generate` with various inputs | Full |
| `spec/auto-doc/generator/agents_md_generator_spec.rb` | `AgentsMdGenerator.generate` with various inputs | Full |
| `spec/auto_doc/analyzer/source_parser_spec.rb` | `SourceParser.parse_file` on various Ruby files | Full |
| `spec/auto_doc/analyzer/yard_reader_spec.rb` | YARD comment extraction | Full |
| `spec/auto_doc/analyzer/import_extractor_spec.rb` | Import statement extraction | Full |
| `spec/auto_doc/analyzer/schema_parser_spec.rb` | Rails schema parsing | Full |
| `spec/auto_doc/analyzer/model_association_parser_spec.rb` | Rails model associations | Full |
| `spec/auto_doc/analyzer/orphans_service_spec.rb` | Orphan file detection | Full |
| `spec/auto_doc/utils/file_tree_builder_spec.rb` | Directory tree generation | Full |
| `spec/auto_doc/utils/output_formatter_spec.rb` | Text/JSON/agent output formatting | Full |
| `spec/auto_doc/utils/markdown_helper_spec.rb` | Markdown utilities | Full |
| `spec/auto_doc/utils/timestamp_tracker_spec.rb` | Mtime-based change detection | Full |
| `spec/auto_doc/utils/yaml_config_loader_spec.rb` | YAML loading with fallback | Full |
| `spec/auto_doc/reporter/completeness_checker_spec.rb` | Coverage calculation | Full |
| `spec/auto_doc/reporter/audit_reporter_spec.rb` | Audit report generation | Full |
| `spec/auto_doc/search_service_spec.rb` | Full-text search | Full |
| `spec/auto_doc/agent_query_service_spec.rb` | Natural-language queries | Full |
| `spec/auto_doc/transformer/graph_data_builder_spec.rb` | DAG graph building | Full |

### Generator Tests

| Spec File | Target |
|-----------|--------|
| `spec/auto_doc/generator/readme_generator_spec.rb` | `ReadmeGenerator` |
| `spec/auto_doc/generator/index_generator_spec.rb` | `IndexGenerator` |
| `spec/auto_doc/generator/diagram_generator_spec.rb` | `DiagramGenerator` |
| `spec/auto_doc/generator/c4_diagram_generator_spec.rb` | `C4DiagramGenerator` |
| `spec/auto_doc/generator/class_diagram_generator_spec.rb` | `ClassDiagramGenerator` |
| `spec/auto_doc/generator/erd_generator_spec.rb` | `ErdGenerator` |
| `spec/auto_doc/generator/architecture_generator_spec.rb` | `ArchitectureGenerator` |
| `spec/auto_doc/generator/vector_generator_spec.rb` | `VectorGenerator` |
| `spec/auto_doc/generator/map_generator_spec.rb` | `MapGenerator` |

### Integration Tests

| Spec File | Target |
|-----------|--------|
| `spec/auto_doc/llm/integration_spec.rb` | Full LLM chain: Config → Client → Summarizer → Generator. 15 examples, `:integration` tag for selective execution. Tests LLM success, fallback, ENV guard, and backward compatibility. |
| `spec/auto_doc/cli_spec.rb` | CLI command execution |
| `spec/auto_doc/server_spec.rb` | Sinatra server HTTP endpoints |
| `spec/e2e/self_test_spec.rb` | End-to-end self-test against project source |

## Stubbing Policy

### LLM Tests

The `llm_spec.rb` only verifies that constants are defined. It does NOT test `Client#chat` or `Summarizer` methods against real or mocked HTTP responses.

The `spec/auto_doc/llm/integration_spec.rb` provides integration-level coverage of the LLM chain. It mocks `Net::HTTP` directly (not via WebMock/VCR) to test:
- `Client.from_config` builds correctly from Config with LLM settings
- `Client.chat` returns mocked responses
- `Summarizer.summarize_module/architecture/components` return client response text
- `SummaryGenerator` integrates LLM (3 chat calls) and falls back to static inference
- `AgentsMdGenerator` integrates LLM (1 chat call) and falls back to placeholder text
- `AUTO_DOC_DISABLE_LLM` environment variable disables LLM in both generators
- Backward compatibility when no config is passed to `AgentsMdGenerator`

### Config Tests

### Config Tests

Config specs create temporary directories with `Dir.mktmpdir` and write `.autodoc.yml` files. Directories are cleaned up in `after` blocks.

### Generator Tests

Generator specs use in-memory analysis data (hardcoded hashes) rather than reading from disk. Output file tests use `Dir.mktmpdir` for temporary output paths.

## Test Fixtures

Fixtures are in `fixtures/` and `test_fixtures/` directories. Used by generator specs and E2E tests.

## Known Test Status

At time of final review (commit `18a75b3`):
- **589 specs passing** (includes 15 integration tests)
- **42 pre-existing failures** (not introduced by LLM work):
  - `server_spec.rb`: 36 failures (Sinatra server test issues)
  - `cli_spec.rb`: 1 failure
  - `self_test_spec.rb`: 5 failures
- These failures are confirmed unchanged from the baseline before the LLM project.
- Integration tests are tagged with `:integration` for selective execution via `rspec --tag integration`