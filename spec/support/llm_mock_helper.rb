# frozen_string_literal: true

module LlmMockHelper
  # Stubs LLM client to return pre-configured responses without real HTTP calls.
  # @param response_map [Hash{String => String}] prompt substring => response text
  # @param primary [Boolean] whether to also set up llm_primary? on the config
  def mock_llm_client(response_map = {}, primary: false)
    client = instance_double(AutoDoc::LLM::Client)
    allow(client).to receive(:chat) do |messages, **|
      prompt = messages.map { |m| m[:content] }.join(" ")
      match = response_map.find { |substring, _| prompt.include?(substring) }
      match&.last
    end
    allow(AutoDoc::LLM::Client).to receive(:build_if_configured).and_return(client)
    client
  end

  # Builds a Config double that responds to llm_primary? returning true
  # and llm_config returning a valid hash.
  def primary_llm_config
    config = instance_double(AutoDoc::Config)
    allow(config).to receive(:llm_primary?).and_return(true)
    allow(config).to receive(:llm_config).and_return({ endpoint: "https://test", api_key: "test", model: "test-model" })
    config
  end

  # Builds a Config double that responds to llm_primary? returning false
  # and llm_config returning a valid hash.
  def standard_llm_config
    config = instance_double(AutoDoc::Config)
    allow(config).to receive(:llm_primary?).and_return(false)
    allow(config).to receive(:llm_config).and_return({ endpoint: "https://test", api_key: "test", model: "test-model" })
    config
  end
end
