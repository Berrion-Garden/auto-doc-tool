# frozen_string_literal: true

require "spec_helper"
require "json"
require "auto_doc/utils/output_formatter"

RSpec.describe AutoDoc::Utils::OutputFormatter do
  let(:sample_data) do
    {
      project: "test_project",
      output_dir: ".docs",
      module_roots: %w[lib app],
      created_files: [
        "lib/AGENTS.md",
        "README.md",
        "diagrams/deps.mmd"
      ],
      analyses_count: 10,
      generated_at: "2026-07-15T01:00:00+00:00"
    }
  end

  describe ".format" do
    context "with format: :text" do
      it "passes through to say with the data string" do
        output = []
        say = ->(msg, _color = nil) { output << msg }
        AutoDoc::Utils::OutputFormatter.format("hello world", format: :text, say: say)
        expect(output).to contain_exactly("hello world")
      end
    end

    context "with format: :json" do
      it "produces pretty-printed JSON" do
        output = []
        say = ->(msg) { output << msg }
        AutoDoc::Utils::OutputFormatter.format(sample_data, format: :json, say: say)

        parsed = JSON.parse(output.first)
        expect(parsed).to be_a(Hash)
        expect(parsed["project"]).to eq("test_project")
        expect(parsed["module_roots"]).to match_array(%w[lib app])
        expect(parsed["created_files"]).to be_an(Array)
      end

      it "includes all fields including generated_at" do
        output = []
        say = ->(msg) { output << msg }
        AutoDoc::Utils::OutputFormatter.format(sample_data, format: :json, say: say)

        parsed = JSON.parse(output.first)
        expect(parsed).to have_key("generated_at")
        expect(parsed).to have_key("analyses_count")
      end

      it "outputs pretty-printed JSON (has newlines)" do
        output = []
        say = ->(msg) { output << msg }
        AutoDoc::Utils::OutputFormatter.format(sample_data, format: :json, say: say)

        expect(output.first).to include("\n")
      end
    end

    context "with format: :agent" do
      it "produces compact JSON (no pretty printing)" do
        output = []
        say = ->(msg) { output << msg }
        AutoDoc::Utils::OutputFormatter.format(sample_data, format: :agent, say: say)

        # Compact JSON should not have indentation newlines inside objects
        expect(output.first).not_to include("\n  ")
      end

      it "strips timestamp fields" do
        output = []
        say = ->(msg) { output << msg }
        AutoDoc::Utils::OutputFormatter.format(sample_data, format: :agent, say: say)

        parsed = JSON.parse(output.first)
        expect(parsed).not_to have_key("generated_at")
        expect(parsed).not_to have_key("timestamp")
      end

      it "converts camelCase keys to snake_case" do
        output = []
        say = ->(msg) { output << msg }
        AutoDoc::Utils::OutputFormatter.format(sample_data, format: :agent, say: say)

        parsed = JSON.parse(output.first)
        expect(parsed).to have_key("analyses_count")
      end
    end
  end

  describe ".compact_for_agent" do
    it "removes generated_at keys" do
      compact = described_class.compact_for_agent(sample_data)
      expect(compact).not_to have_key(:generated_at)
    end

    it "keeps essential keys" do
      compact = described_class.compact_for_agent(sample_data)
      expect(compact).to have_key(:project)
      expect(compact).to have_key(:module_roots)
      expect(compact).to have_key(:created_files)
    end

    it "converts camelCase keys to snake_case symbols" do
      compact = described_class.compact_for_agent(sample_data)
      expect(compact).to have_key(:analyses_count)
    end

    context "with deeply nested hashes" do
      let(:nested) do
        {
          top: {
            middle: {
              bottom: "value",
              generated_at: "stripped"
            }
          }
        }
      end

      it "strips timestamp keys at all levels" do
        compact = described_class.compact_for_agent(nested)
        expect(compact.dig(:top, :middle)).not_to have_key(:generated_at)
        expect(compact.dig(:top, :middle, :bottom)).to eq("value")
      end
    end

    context "with arrays" do
      let(:data_with_arrays) do
        {
          items: [
            { name: "one", generated_at: "2026-01-01" },
            { name: "two", generated_at: "2026-01-02" }
          ]
        }
      end

      it "processes each array element" do
        compact = described_class.compact_for_agent(data_with_arrays)
        expect(compact[:items].size).to eq(2)
        compact[:items].each do |item|
          expect(item).not_to have_key(:generated_at)
          expect(item).to have_key(:name)
        end
      end
    end

    it "handles scalar values" do
      expect(described_class.compact_for_agent("hello")).to eq("hello")
      expect(described_class.compact_for_agent(42)).to eq(42)
      expect(described_class.compact_for_agent(true)).to eq(true)
      expect(described_class.compact_for_agent(nil)).to eq(nil)
    end
  end
end
