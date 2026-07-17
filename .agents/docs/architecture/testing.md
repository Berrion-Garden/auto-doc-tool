# Auto-Doc Tool — Testing Strategy

## Test Suite Overview

- **Framework:** RSpec
- **Example count:** 832
- **Failures:** 0
- **Persistence:** `spec/examples.txt` for example status tracking

The test count increased from 811 (pre-milestone) to 832 (post-milestone 3-R remediation). All milestones completed without retry — the final count reflects all added test files for schema_parser, response_parser, prompt_builder, enricher, summarizer, base_step, and transformer builders.

## Test Organization

```
spec/
├── spec_helper.rb                          # Shared configuration, LLM mock helpers
├── support/llm_mock_helper.rb              # LLM mocking utilities
├── auto_doc_spec.rb                        # Top-level gem loading tests
├── auto_doc/                               # Unit tests mirroring lib/ structure
│   ├── agent_query_service_spec.rb
│   ├── cli_spec.rb
│   ├── config_spec.rb
│   ├── documentation_index_spec.rb
│   ├── errors_spec.rb
│   ├── search_service_spec.rb
│   ├── server_spec.rb
│   ├── llm/
│   │   ├── client_spec.rb
│   │   ├── enricher_spec.rb                # Enricher unit tests (new in Milestone 2)
│   │   ├── prompt_builder_spec.rb           # PromptBuilder tests (new in Milestone 2)
│   │   ├── response_parser_spec.rb          # ResponseParser tests (new in Milestone 2)
│   │   ├── summarizer_spec.rb               # Summarizer tests (new in Milestone 2)
│   │   ├── integration_spec.rb              # LLM integration tests
│   │   └── llm_spec.rb
│   ├── generator/
│   │   ├── vector_generator_spec.rb        # VectorGenerator tests
│   │   ├── agents_md_generator_spec.rb     # AgentsMdGenerator tests
│   │   ├── agents_overview_generator_spec.rb
│   │   ├── architecture_generator_spec.rb
│   │   ├── c4_diagram_generator_spec.rb
│   │   ├── class_diagram_generator_spec.rb
│   │   ├── diagram_generator_spec.rb
│   │   ├── erd_generator_spec.rb
│   │   ├── index_generator_spec.rb
│   │   ├── map_generator_spec.rb
│   │   ├── readme_generator_spec.rb
│   │   ├── summary_generator_spec.rb
│   │   └── template_helper_spec.rb
│   ├── orchestrator/
│   │   ├── orchestrator_spec.rb
│   │   ├── pipeline_spec.rb
│   │   ├── base_step_spec.rb                # BaseStep collect_symbol_summaries (new in M3-R)
│   │   ├── agents_md_step_spec.rb           # AgentsMdStep tests (new in Milestone 3)
│   │   ├── diagram_step_spec.rb
│   │   ├── metrics_helper_spec.rb
│   │   └── index_summary_vectors_step_spec.rb
│   ├── reporter/
│   │   ├── audit_reporter_spec.rb
│   │   └── completeness_checker_spec.rb
│   ├── transformer/
│   │   ├── graph_data_builder_spec.rb       # New in Milestone 3
│   │   ├── files_data_builder_spec.rb       # New in Milestone 3
│   │   ├── class_hierarchy_builder_spec.rb
│   │   ├── container_data_flow_builder_spec.rb
│   │   └── erd_relationship_builder_spec.rb
│   ├── analyzer/
│   │   ├── schema_parser_spec.rb            # New in Milestone 1
│   │   ├── model_association_parser_spec.rb
│   │   ├── analysis_pipeline_spec.rb
│   │   ├── analysis_cache_spec.rb
│   │   ├── source_parser_spec.rb
│   │   ├── yard_reader_spec.rb
│   │   ├── import_extractor_spec.rb
│   │   ├── generic_scanner_spec.rb
│   │   ├── diff_service_spec.rb
│   │   └── orphans_service_spec.rb
│   └── utils/
│       ├── yaml_config_loader_spec.rb
│       ├── file_tree_builder_spec.rb
│       ├── timestamp_tracker_spec.rb
│       ├── output_formatter_spec.rb
│       └── markdown_helper_spec.rb
├── e2e/
│   └── self_test_spec.rb                    # E2E tests using E2ERunner
└── scripts/                                 # Test utility scripts
```

## Test Configuration (`spec_helper.rb`)

```ruby
# Loads the gem
require "auto_doc"
require "rack/test"
require_relative "support/llm_mock_helper"

# LLM protection: stub Client.build_if_configured to return nil by default
config.before(:each) do
  allow(AutoDoc::LLM::Client).to receive(:build_if_configured).and_return(nil)
end

# Cache clearing between tests
config.before(:each) do
  AutoDoc::Analyzer::AnalysisCache.clear!
end

# Formatter: doc format when running single spec file
config.filter_run_when_matching :focus       # Focus filtering
config.profile_examples = 10                # Profile top 10 examples
```

## LLM Mocking Strategy

### `LlmMockHelper` (spec/support/llm_mock_helper.rb)

Provides test doubles for LLM integration testing:

**`mock_llm_client(response_map = {}, primary: false)`**
- Creates a `Client` instance double
- Stubs `#chat(messages)` to match against `response_map` keys (substring matching on prompt content)
- Stubs `Client.build_if_configured(config)` to return the mock client
- Returns the mock client for further configuration

**`primary_llm_config`**
- Creates a `Config` double with `llm_primary?` returning `true`
- Returns a valid `llm_config` hash

**`standard_llm_config`**
- Creates a `Config` double with `llm_primary?` returning `false`
- Returns a valid `llm_config` hash

### Default Behavior

By default (spec_helper `before(:each)`), `Client.build_if_configured` returns `nil`, which means:
- Enricher returns analyses unchanged
- No LLM calls are made in tests unless explicitly mocked
- Tests can verify non-LLM behavior without interference

### Explicit LLM Mocking

Tests that need LLM behavior call `mock_llm_client(response_map)` to override the default stub:

```ruby
# In enricher_spec.rb:
before do
  mock_llm_client({
    "app" => "UsersController: Handles HTTP requests\nUser: Represents user data",
    "lib" => "UserService: Orchestrates user-related business logic"
  })
end
```

The mock client matches LLM prompts by checking if the prompt content includes any key in `response_map`.

## Test Coverage Highlights

### Enricher (`spec/auto_doc/llm/enricher_spec.rb`)

245 lines, tests the following scenarios:
- **LLM primary + configured:** Populates docs arrays with summaries, preserves hash identity
- **Config guard:** Returns analyses unchanged when `llm_primary? == false`
- **Client unavailable:** Returns analyses unchanged when `build_if_configured` returns nil
- **Nil LLM response:** Logs warning, continues processing other modules
- **Empty LLM response:** Does not modify docs arrays
- **Namespaced symbols:** Handles `::` in symbol names (converts to `_` in entry_id)
- **Module root filtering:** Files outside module roots are not enriched

### VectorGenerator (`spec/auto_doc/generator/vector_generator_spec.rb`)

Tests keyword extraction, doc index construction, vector entry building with and without summaries, merged keyword behavior.

### SearchService (`spec/auto_doc/search_service_spec.rb`)

Tests all search strategies: symbol exact, dependency match, keyword overlap (high/low), summary match, summary text, source grep. Includes edge cases: empty summary, missing summary field, keyword overlap >3 scoring.

### Orchestrator (`spec/auto_doc/orchestrator_spec.rb`)

82 lines, tests Enricher wiring in both LLM-primary and non-primary paths.

## Tagging Strategy

Tests use RSpec tags for selective execution:
- `~integration` — Exclude integration/e2e tests during fast unit test runs
- Custom tags may be added for specific module groups

## Test Fixtures

Fixture files are stored in `fixtures/` directory (referenced via `FIXTURES_DIR` constant and `fixture_path` helper). Used for integration tests that need realistic source files.

## E2E Testing

End-to-end tests in `spec/e2e/` run the full generation pipeline against fixture projects and verify output artifacts. The `Tester::E2ERunner` class orchestrates these tests.