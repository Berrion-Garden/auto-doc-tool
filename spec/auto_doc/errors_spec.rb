# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::LLMError do
  it "inherits from StandardError" do
    expect(described_class).to be < StandardError
  end

  it "uses default message" do
    expect { raise described_class }.to raise_error("LLM call failed")
  end

  it "accepts custom message" do
    expect { raise described_class, "custom error" }.to raise_error("custom error")
  end
end
