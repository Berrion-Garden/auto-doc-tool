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
| `spec/auto_doc/config_spec.rb` | `Config.load`, defaults, YAML merge, CLI overrides, output_dir fallback, fail_fast | Full |
| `spec/auto_doc/generator/summary_generator_spec.rb` | `SummaryGenerator.generate` with various inputs | Full |
| `spec/auto-doc/generator/agents_md_generator_spec.rb` | `AgentsMdGenerator.generate` with various inputs | Full |
| `spec/auto_doc/analyzer/source_parser_spec.rb` | `SourceParser.parse_file` on various Ruby files | Full |
| `spec/auto_doc/analyzer/generic_scanner_spec.rb` | `GenericScanner` language detection, regex parsing, unsupported extensions | Full |
| `spec/auto_doc/analyzer/analysis_pipeline_spec.rb` | `AnalysisPipeline` fallback behavior, language/scanner keys | Full |
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
| `spec/auto_doc/errors_spec.rb` | `LLMError` class definition | Full |
| `spec/auto_doc/generator/template_helper_spec.rb` | `TemplateHelper` methods including fail_fast | Full |

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
| `spec/auto_doc/generator/vector_generator_spec.rb` | `VectorGenerator` (includes LLM summary integration tests) |
| `spec/auto_doc/generator/map_generator_spec.rb` | `MapGenerator` |
| `spec/auto_doc/generator/agents_overview_generator_spec.rb` | `AgentsOverviewGenerator` (7 sections, tech stack, conventions) |

### Integration Tests

| Spec File | Target |
|-----------|--------|
| `spec/auto_doc/llm/integration_spec.rb` | Full LLM chain: Config → Client → Summarizer → Generator. 15 examples, `:integration` tag for selective execution. Tests LLM success, fallback, ENV guard, and backward compatibility. |
| `spec/auto_doc/cli_spec.rb` | CLI command execution |
| `spec/auto_doc/server_spec.rb` | Sinatra server HTTP endpoints |
| `spec/e2e/self_test_spec.rb` | End-to-end self-test against project source |
| `spec/auto_doc/orchestrator/pipeline_spec.rb` | Pipeline step execution with context flow |
| `spec/auto_doc/orchestrator/agents_md_step_spec.rb` | AgentsMdStep orchestration |
| `spec/auto_doc/orchestrator/diagram_step_spec.rb` | DiagramStep orchestration |
| `spec/auto_doc/orchestrator/base_step_spec.rb` | BaseStep interface |
| `spec/auto_doc/orchestrator/metrics_helper_spec.rb` | MetricsHelper count_classes_and_methods, calculate_coverage |

## Stubbing Policy

### LLM Tests

The `llm_spec.rb` only verifies that constants are defined. It does NOT test `Client#chat` or `Summarizer` methods against real or mocked HTTP responses.

### `LlmMockHelper` (`spec/support/llm_mock_helper.rb`)

Shared test helper for LLM-related specs. Provides:
- `mock_llm_client` — Stubs `Client.build_if_configured` to return a mock client whose `chat` method returns configured response text
- `primary_llm_config` — Creates an `AutoDoc::Config` with `llm.primary: true`
- `standard_llm_config` — Creates an `AutoDoc::Config` with `llm.primary: false` (default)

Used by integration and unit tests to simulate both primary and non-primary modes.

### Integration Test Coverage

The `spec/auto_doc/llm/integration_spec.rb` provides integration-level coverage of the LLM chain. It mocks `Net::HTTP` directly (not via WebMock/VCR) to test:
- `Client.from_config` builds correctly from Config with LLM settings
- `Client.chat` returns mocked responses
- `Summarizer.summarize_module/architecture/components` return client response text
- `SummaryGenerator` integrates LLM (3 chat calls) and falls back to static inference
- `AgentsMdGenerator` integrates LLM (1 chat call) and falls back to placeholder text
- `ArchitectureGenerator` LLM enhancement in primary mode
- `ReadmeGenerator` LLM enhancement in primary mode
- `AUTO_DOC_DISABLE_LLM` environment variable disables LLM in all generators
- Backward compatibility when no config is passed

### Generator Tests

Generator specs use in-memory analysis data (hardcoded hashes) rather than reading from disk. Output file tests use `Dir.mktmpdir` for temporary output paths.

## Test Fixtures

Fixtures are in `fixtures/` and `test_fixtures/` directories. Used by generator specs and E2E tests.

## Known Test Status

At time of LLM Primary Driver Architecture final review (commit `4c04a36`):
- **721 specs passing** (includes enhanced integration test suite)
- Pre-existing failures unchanged from baseline
- Integration tests tagged with `:integration` for selective execution via `rspec --tag integration`
- `LlmMockHelper` provides reusable stubs for all LLM-related tests

Current state (post-project 2026-07-16-best-llm-powered-doc, commit `08bbc78`):
- **784 specs passing, 0 failures**
- New specs added by project: `generic_scanner_spec.rb`, `analysis_pipeline_spec.rb`, `errors_spec.rb`, `template_helper_spec.rb`, `agents_overview_generator_spec.rb`, `vector_generator_spec.rb` (LLM summary tests), `pipeline_spec.rb`, `agents_md_step_spec.rb`, `diagram_step_spec.rb`, `base_step_spec.rb`, `metrics_helper_spec.rb`