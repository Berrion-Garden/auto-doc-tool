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

  describe ".generate_directory with llm_summaries" do
    let(:dir_analyses) do
      { "/project/lib/foo.rb" => analyses["/project/lib/foo.rb"] }
    end
    let(:llm_summaries) { { "class_Foo" => "Foo handles business logic" } }

    it "passes llm_summaries through to build_vector_entry" do
      result = described_class.generate_directory("lib", dir_analyses, nil, llm_summaries: llm_summaries)
      foo_entry = result[:symbols].find { |s| s[:symbol] == "Foo" }
      expect(foo_entry).to have_key(:llm_summary)
      expect(foo_entry[:llm_summary]).to eq("Foo handles business logic")
    end

    it "is backward compatible: no llm_summaries parameter works as before" do
      result = described_class.generate_directory("lib", dir_analyses)
      expect(result[:symbols].size).to eq(1)
      expect(result[:symbols].first).not_to have_key(:llm_summary)
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

    it "merges keywords from name and summary text when summary_text provided" do
      keywords = generator.keyword_extraction("Parser", "transforms raw data into structured objects")
      expect(keywords).to include("parser")
      expect(keywords).to include("transforms")
      expect(keywords).to include("raw")
      expect(keywords).to include("data")
      expect(keywords).to include("structured")
      expect(keywords).to include("objects")
    end

    it "returns only name-derived keywords when summary_text is nil" do
      keywords = generator.keyword_extraction("Parser", nil)
      expect(keywords).to eq(["parser"])
    end

    it "returns only name-derived keywords when summary_text is empty" do
      keywords = generator.keyword_extraction("Parser", "")
      expect(keywords).to eq(["parser"])
    end

    it "returns at most 15 keywords even with long summaries" do
      keywords = generator.keyword_extraction("VeryLongCamelCaseName", "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen")
      expect(keywords.size).to be <= 15
    end
  end

  describe ".extract_keywords_from_text" do
    it "extracts keywords from descriptive text" do
      keywords = generator.extract_keywords_from_text("Handles HTTP request routing and controller dispatch")
      expect(keywords).to include("handles")
      expect(keywords).to include("http")
      expect(keywords).to include("request")
      expect(keywords).to include("routing")
      expect(keywords).to include("controller")
      expect(keywords).to include("dispatch")
    end

    it "removes stop words" do
      keywords = generator.extract_keywords_from_text("the and for routing")
      expect(keywords).not_to include("the")
      expect(keywords).not_to include("and")
      expect(keywords).not_to include("for")
      expect(keywords).to include("routing")
    end

    it "removes short words" do
      keywords = generator.extract_keywords_from_text("a at do routing")
      expect(keywords).not_to include("a")
      expect(keywords).not_to include("at")
      expect(keywords).not_to include("do")
      expect(keywords).to include("routing")
    end

    it "returns empty array for empty text" do
      expect(generator.extract_keywords_from_text("")).to eq([])
    end

    it "deduplicates keywords" do
      keywords = generator.extract_keywords_from_text("routing HTTP routing controller HTTP")
      expect(keywords.count("routing")).to eq(1)
    end

    it "returns at most 15 keywords" do
      text = "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen"
      expect(generator.extract_keywords_from_text(text).size).to be <= 15
    end
  end

  describe ".build_vector_entry with llm_summaries" do
    let(:defn) { { name: "Foo", type: :class, line: 1, has_doc?: true, signature: "class Foo", visibility: "public" } }
    let(:doc_index) { { class_Foo: { target_name: "Foo", target_type: :class, summary: "YARD summary" } } }
    let(:llm_summaries) { { "class_Foo" => "Handles HTTP request routing and controller dispatch" } }

    it "includes llm_summary field when summary is available" do
      entry = generator.send(:build_vector_entry, defn, "/project/lib/foo.rb", doc_index, llm_summaries)
      expect(entry).to have_key(:llm_summary)
      expect(entry[:llm_summary]).to eq("Handles HTTP request routing and controller dispatch")
    end

    it "uses keywords from LLM summary text when available" do
      entry = generator.send(:build_vector_entry, defn, "/project/lib/foo.rb", doc_index, llm_summaries)
      expect(entry[:keywords]).to include("handles")
      expect(entry[:keywords]).to include("routing")
      expect(entry[:keywords]).not_to include("foo")  # Not derived from symbol name
    end

    it "keeps summary field from doc_index unchanged" do
      entry = generator.send(:build_vector_entry, defn, "/project/lib/foo.rb", doc_index, llm_summaries)
      expect(entry[:summary]).to eq("YARD summary")
    end

    it "does NOT include llm_summary field when not in llm_summaries" do
      entry = generator.send(:build_vector_entry, defn, "/project/lib/foo.rb", doc_index, nil)
      expect(entry).not_to have_key(:llm_summary)
    end

    it "uses keyword_extraction from symbol name when llm_summaries is nil" do
      entry = generator.send(:build_vector_entry, defn, "/project/lib/foo.rb", doc_index, nil)
      expect(entry[:keywords]).to include("foo")
    end

    it "uses keyword_extraction from symbol name when symbol not in llm_summaries" do
      entry = generator.send(:build_vector_entry, defn, "/project/lib/foo.rb", doc_index, { "other_Symbol" => "nothing" })
      expect(entry[:keywords]).to include("foo")
      expect(entry).not_to have_key(:llm_summary)
    end
  end

  describe ".build_vector_entry with doc_index summary" do
    context "with doc_index summary" do
      let(:defn) { { name: "DataTransformer", type: :class, line: 1, has_doc?: true, signature: "class DataTransformer", visibility: "public" } }
      let(:doc_index) { { class_DataTransformer: { target_name: "DataTransformer", target_type: :class, summary: "Transforms raw data into structured objects" } } }
      let(:llm_summaries) { nil }

      it "includes keywords from both symbol name and doc summary" do
        entry = generator.send(:build_vector_entry, defn, "/project/lib/transformer.rb", doc_index, llm_summaries)
        expect(entry[:keywords]).to include("data")
        expect(entry[:keywords]).to include("transformer")
        expect(entry[:keywords]).to include("transforms")
        expect(entry[:keywords]).to include("raw")
        expect(entry[:keywords]).to include("structured")
        expect(entry[:keywords]).to include("objects")
      end

      it "preserves summary field from doc_index" do
        entry = generator.send(:build_vector_entry, defn, "/project/lib/transformer.rb", doc_index, llm_summaries)
        expect(entry[:summary]).to eq("Transforms raw data into structured objects")
      end
    end

    context "without doc_index summary" do
      let(:defn) { { name: "Foo", type: :class, line: 1, has_doc?: true, signature: "class Foo", visibility: "public" } }
      let(:doc_index) { { class_Foo: { target_name: "Foo", target_type: :class, summary: "" } } }
      let(:llm_summaries) { nil }

      it "derives keywords from symbol name only when summary is empty" do
        entry = generator.send(:build_vector_entry, defn, "/project/lib/foo.rb", doc_index, llm_summaries)
        expect(entry[:keywords]).to include("foo")
        expect(entry[:keywords].size).to eq(1)
      end
    end
  end

  describe ".generate_project with llm_summaries" do
    let(:llm_summaries) { { "class_Foo" => "Main Foo class handles business logic" } }

    it "passes llm_summaries through to build_vector_entry" do
      result = generator.generate_project(analyses, nil, llm_summaries: llm_summaries)
      foo_entry = result[:symbols].find { |s| s[:symbol] == "Foo" }
      expect(foo_entry).to have_key(:llm_summary)
      expect(foo_entry[:llm_summary]).to eq("Main Foo class handles business logic")
    end

    it "does not add llm_summary to entries not in llm_summaries" do
      result = generator.generate_project(analyses, nil, llm_summaries: llm_summaries)
      utils_entry = result[:symbols].find { |s| s[:symbol] == "Utils" }
      expect(utils_entry).not_to have_key(:llm_summary)
    end

    it "backward compatible: no llm_summaries parameter works as before" do
      result = generator.generate_project(analyses)
      expect(result[:symbols].size).to eq(3)
      result[:symbols].each do |entry|
        expect(entry).not_to have_key(:llm_summary)
      end
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
