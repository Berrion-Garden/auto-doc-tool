# frozen_string_literal: true

require "spec_helper"

RSpec.describe "AutoDoc::LLM module" do
  it "loads the Client class" do
    expect(AutoDoc::LLM::Client).to be_a(Class)
    expect(AutoDoc::LLM::Client.instance_methods).to include(:chat, :configured?)
  end

  it "loads the Summarizer class" do
    expect(AutoDoc::LLM::Summarizer).to be_a(Class)
  end
end
