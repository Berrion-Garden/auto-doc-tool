# frozen_string_literal: true

module AutoDoc
  # Raised when fail_fast mode is enabled and an LLM call fails.
  # Allows callers to abort generation early instead of silently falling back.
  class LLMError < StandardError
    def initialize(message = "LLM call failed")
      super
    end
  end
end
