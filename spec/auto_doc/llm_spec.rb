# frozen_string_literal: true

require "spec_helper"

RSpec.describe "AutoDoc::LLM module" do
  it "defines AutoDoc::LLM" do
    expect(defined?(AutoDoc::LLM)).to eq("constant")
    expect(AutoDoc::LLM).to be_a(Module)
  end

  it "defines AutoDoc::LLM::Client" do
    expect(defined?(AutoDoc::LLM::Client)).to eq("constant")
    expect(AutoDoc::LLM::Client).to be_a(Class)
  end

  it "defines AutoDoc::LLM::Summarizer" do
    expect(defined?(AutoDoc::LLM::Summarizer)).to eq("constant")
    expect(AutoDoc::LLM::Summarizer).to be_a(Class)
  end
end
