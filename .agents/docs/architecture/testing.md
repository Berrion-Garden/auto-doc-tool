# Auto-Doc Tool — Testing Strategy

## Test Suite Overview

- **Framework:** RSpec
- **Example count:** 811
- **Failures:** 0
- **Persistence:** `spec/examples.txt` for example status tracking

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
│   │   ├── enricher_spec.rb                # Enricher unit tests (new)
│   │   └── ...
│   ├── generator/
│   │   ├── vector_generator_spec.rb        # VectorGenerator tests
│   │   └── ...
│   ├── orchestrator/
│   │   ├── index_summary_vectors_step_spec.rb
│   │   └── ...
│   ├── reporter/
│   │   └── ...
│   └── utils/
│       └── ...
├── e2e/                                    # End-to-end integration tests
└── scripts/                                # Test utility scripts
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