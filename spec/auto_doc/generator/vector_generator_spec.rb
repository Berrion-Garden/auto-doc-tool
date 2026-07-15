# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

RSpec.describe AutoDoc::Generator::VectorGenerator do
  subject(:generator) { described_class }

  let(:analyses) do
    {
      "/project/lib/foo.rb" => {
        definitions: [
          { name: "Foo", type: :class, line: 1, has_doc?: true, signature: "class Foo", visibility: "public" }
        ],
        imports: [],
        docs: [
          { target_name: "Foo", target_type: :class, has_summary?: true, summary: "Main Foo class" }
        ]
      },
      "/project/lib/utils.rb" => {
        definitions: [
          { name: "Utils", type: :module, line: 10, has_doc?: false, signature: "module Utils", visibility: "public" }
        ],
        imports: [],
        docs: []
      },
      "/project/app/controller.rb" => {
        definitions: [
          { name: "Controller", type: :class, line: 5, has_doc?: true, signature: "class Controller", visibility: "public" }
        ],
        imports: [],
        docs: [
          { target_name: "Controller", target_type: :class, has_summary?: true, summary: "Handles requests" }
        ]
      }
    }
  end

  describe ".generate_project" do
    it "returns a Hash with a symbols array" do
      result = generator.generate_project(analyses)
      expect(result).to be_a(Hash)
      expect(result[:symbols]).to be_an(Array)
    end

    it "includes all symbols from all files" do
      result = generator.generate_project(analyses)
      expect(result[:symbols].size).to eq(3)
    end

    it "includes correct schema for each entry (id, symbol, type, file, line)" do
      result = generator.generate_project(analyses)
      entry = result[:symbols].first
      expect(entry).to have_key(:id)
      expect(entry).to have_key(:symbol)
      expect(entry).to have_key(:type)
      expect(entry).to have_key(:file)
      expect(entry).to have_key(:line)
      expect(entry).to have_key(:keywords)
      expect(entry).to have_key(:dependencies)
      expect(entry).to have_key(:consumed_by)
    end

    it "generates correct unique IDs" do
      result = generator.generate_project(analyses)
      ids = result[:symbols].map { |e| e[:id] }
      expect(ids).to include("class_Foo")
      expect(ids).to include("module_Utils")
    end

    it "includes generated_at timestamp" do
      result = generator.generate_project(analyses)
      expect(result[:generated_at]).to be_a(String)
    end
  end

  describe ".generate_directory" do
    it "returns only symbols for the given directory" do
      dir_analyses = {
        "/project/lib/foo.rb" => analyses["/project/lib/foo.rb"],
        "/project/lib/utils.rb" => analyses["/project/lib/utils.rb"]
      }
      result = generator.generate_directory("lib", dir_analyses)
      expect(result[:symbols].size).to eq(2)
    end

    it "excludes symbols outside the directory" do
      result = generator.generate_directory("lib", analyses.select { |fp, _| fp.start_with?("/project/lib") })
      symbols = result[:symbols]
      expect(symbols.none? { |s| s[:symbol] == "Controller" }).to be true
    end
  end

  describe ".keyword_extraction" do
    it "splits CamelCase names" do
      keywords = generator.keyword_extraction("AgentsMdGenerator")
      expect(keywords).to include("agents")
      expect(keywords).to include("md")
      expect(keywords).to include("generator")
    end

    it "splits snake_case names" do
      keywords = generator.keyword_extraction("foo_bar_baz")
      expect(keywords).to include("foo")
      expect(keywords).to include("bar")
      expect(keywords).to include("baz")
    end

    it "deduplicates keywords" do
      keywords = generator.keyword_extraction("FooFoo")
      expect(keywords).to eq(keywords.uniq)
    end

    it "returns at most 15 keywords" do
      keywords = generator.keyword_extraction("VeryLongCamelCaseNameWithManyWordsInItForTesting")
      expect(keywords.size).to be <= 15
    end
  end

  describe ".write" do
    let(:output_dir) { Dir.mktmpdir }
    let(:output_path) { File.join(output_dir, "VECTORS.json") }

    after { FileUtils.remove_entry(output_dir) }

    it "creates a valid JSON file" do
      data = generator.generate_project(analyses)
      generator.write(output_path, data)
      expect(File.exist?(output_path)).to be true

      parsed = JSON.parse(File.read(output_path))
      expect(parsed).to have_key("symbols")
      expect(parsed["symbols"]).to be_an(Array)
      expect(parsed["symbols"].size).to eq(3)
    end

    it "writes pretty-printed JSON" do
      data = generator.generate_project(analyses)
      generator.write(output_path, data)
      content = File.read(output_path)
      expect(content).to include("\n") # Pretty-printed has newlines
    end
  end
end
