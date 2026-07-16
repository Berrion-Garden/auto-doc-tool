# frozen_string_literal: true

ENV["AUTO_DOC_DISABLE_LLM"] = "true"

require "auto_doc"
require "rack/test"

RSpec.configure do |config|
  config.include Rack::Test::Methods

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!

  if config.files_to_run.one?
    config.default_formatter = "doc"
  end

  config.profile_examples = 10

  # Clear in-process analysis cache between tests
  config.before(:each) do
    AutoDoc::Analyzer::AnalysisCache.clear!
  end
end

# Path helpers for test fixtures
FIXTURES_DIR = File.expand_path("../fixtures", __dir__).freeze

def fixture_path(*parts)
  File.join(FIXTURES_DIR, *parts)
end
