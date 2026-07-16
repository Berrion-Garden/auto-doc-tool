# frozen_string_literal: true

require "auto_doc"
require "rack/test"
require_relative "support/llm_mock_helper"

RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.include LlmMockHelper

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

  # Prevent real LLM HTTP calls in every spec by default.
  # Individual specs can call mock_llm_client to set up a specific mock.
  config.before(:each) do
    allow(AutoDoc::LLM::Client).to receive(:build_if_configured).and_return(nil)
  end
end

# Path helpers for test fixtures
FIXTURES_DIR = File.expand_path("../fixtures", __dir__).freeze

def fixture_path(*parts)
  File.join(FIXTURES_DIR, *parts)
end
