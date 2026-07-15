# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::Utils::MarkdownHelper do
  describe ".parse_pipe_row" do
    it "splits a pipe-delimited row into trimmed columns" do
      result = described_class.parse_pipe_row("| Name | Type | File | Line | Doc |")
      expect(result).to eq(%w[Name Type File Line Doc])
    end

    it "handles rows without leading/trailing pipes" do
      result = described_class.parse_pipe_row("Name | Type | File")
      expect(result).to eq(%w[Name Type File])
    end

    it "trims whitespace from each column" do
      result = described_class.parse_pipe_row("  foo  |  bar  |  baz  ")
      expect(result).to eq(%w[foo bar baz])
    end

    it "handles a row with a single column" do
      result = described_class.parse_pipe_row("| single |")
      expect(result).to eq(["single"])
    end

    it "handles a row with only pipes" do
      result = described_class.parse_pipe_row("|||")
      expect(result).to eq([])
    end

    it "strips leading and trailing pipes" do
      result = described_class.parse_pipe_row("|a|b|c|")
      expect(result).to eq(%w[a b c])
    end
  end
end
