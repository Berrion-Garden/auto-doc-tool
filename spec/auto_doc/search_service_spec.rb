# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"
require "fileutils"

RSpec.describe AutoDoc::SearchService do
  subject(:service) { described_class }

  # Helper: create a temporary project directory with .docs/ contents
  def with_project_dir
    dir = Dir.mktmpdir("search_spec")
    FileUtils.mkdir_p(File.join(dir, ".docs"))
    yield dir
  ensure
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end

  # Helper: create a nested .docs subdirectory
  def with_nested_project_dir
    dir = Dir.mktmpdir("search_spec")
    FileUtils.mkdir_p(File.join(dir, ".docs", "module", "submodule"))
    yield dir
  ensure
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end

  # ── Test 1: Exact symbol match in INDEX.md ─────────────────────────

  describe "symbol exact match" do
    it "returns score 100 and match_type 'symbol_exact' when term matches a symbol name exactly" do
      with_project_dir do |dir|
        index_content = <<~MD
          # INDEX: test

          ## Symbols

          | Name | Type | File | Line | Doc |
          | --- | --- | --- | --- | --- |
          | MySymbol | class | my_symbol.rb | 5 | true |
          | OtherThing | module | other.rb | 10 | false |

          ## Dependencies

          | From | Type | To |
          | --- | --- | --- |
          | foo.rb | require | bar |
        MD
        File.write(File.join(dir, ".docs", "INDEX.md"), index_content)

        result = service.search(dir, "MySymbol")

        expect(result[:total]).to eq(1)
        expect(result[:results].first).to include(
          score: 100,
          match_type: "symbol_exact",
          file: ".docs/INDEX.md"
        )
      end
    end
  end

  # ── Test 2: Keyword overlap ≥3 in vectors.json ─────────────────────

  describe "vector keyword high match" do
    it "returns score 60 and match_type 'vector_keyword_high' when overlap is 3+" do
      with_project_dir do |dir|
        vectors = {
          "symbols" => [
            { "symbol" => "MySymbol", "keywords" => %w[auto doc test search] }
          ]
        }
        File.write(File.join(dir, ".docs", "vectors.json"), JSON.pretty_generate(vectors))

        # "auto doc test" overlaps 3 keywords
        result = service.search(dir, "auto doc test")

        expect(result[:total]).to be >= 1
        match = result[:results].find { |r| r[:match_type] == "vector_keyword_high" }
        expect(match).not_to be_nil
        expect(match[:score]).to eq(60)
      end
    end
  end

  # ── Test 3: Full-text match in SUMMARY.md ───────────────────────────

  describe "summary text match" do
    it "returns score 20 and match_type 'summary_text' when term is found in SUMMARY.md" do
      with_project_dir do |dir|
        summary_content = <<~MD
          # SUMMARY

          ## Purpose
          This is an important documentation file.
        MD
        File.write(File.join(dir, ".docs", "SUMMARY.md"), summary_content)

        result = service.search(dir, "important")

        expect(result[:total]).to be >= 1
        match = result[:results].find { |r| r[:match_type] == "summary_text" }
        expect(match).not_to be_nil
        expect(match[:score]).to eq(20)
        expect(match[:context]).to include("important")
      end
    end
  end

  # ── Test 4: Source flag enables grep in .rb files ───────────────────

  describe "source grep match" do
    it "returns score 10 and match_type 'source_grep' when source: true and term found in .rb file" do
      with_project_dir do |dir|
        # Create a .rb file outside .docs/
        File.write(File.join(dir, "app.rb"), <<~RUBY)
          class MyApp
            def process
              puts "processing data"
            end
          end
        RUBY

        result = service.search(dir, "processing", options: { source: true })

        expect(result[:total]).to be >= 1
        match = result[:results].find { |r| r[:match_type] == "source_grep" }
        expect(match).not_to be_nil
        expect(match[:score]).to eq(10)
        expect(match[:file]).to eq("app.rb")
      end
    end

    it "does NOT include source matches when source: false" do
      with_project_dir do |dir|
        File.write(File.join(dir, "app.rb"), <<~RUBY)
          class MyApp
            def process
              puts "processing data"
            end
          end
        RUBY

        result = service.search(dir, "processing", options: { source: false })

        matches = result[:results].select { |r| r[:match_type] == "source_grep" }
        expect(matches).to be_empty
      end
    end

    it "returns source matches even when .docs/ directory does not exist" do
      dir = Dir.mktmpdir("search_spec_no_docs")
      begin
        File.write(File.join(dir, "app.rb"), <<~RUBY)
          class MyApp
            def process
              puts "processing data"
            end
          end
        RUBY

        result = service.search(dir, "processing", options: { source: true })

        expect(result[:query]).to eq("processing")
        expect(result[:total]).to be >= 1
        match = result[:results].find { |r| r[:match_type] == "source_grep" }
        expect(match).not_to be_nil
        expect(match[:score]).to eq(10)
        expect(match[:file]).to eq("app.rb")
      ensure
        FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
      end
    end
  end

  # ── Test 5: Missing .docs/ directory ────────────────────────────────

  describe "missing .docs/ directory" do
    it "returns empty results hash" do
      nonexistent = "/tmp/nonexistent_project_#{Process.pid}_#{rand(10_000)}"

      result = service.search(nonexistent, "test")

      expect(result).to eq({ query: "test", results: [], total: 0 })
    end
  end

  # ── Test 6: Results sorted by descending score ──────────────────────

  describe "result sorting" do
    it "returns results sorted by descending score" do
      with_nested_project_dir do |dir|
        # Create source file with matching content (score 10)
        File.write(File.join(dir, "code.rb"), "def some_function; end")

        # Create SUMMARY.md with matching term (score 20)
        File.write(File.join(dir, ".docs", "SUMMARY.md"), "SomeFunction is documented here")

        # Create vectors.json with keyword overlap (score 40/60)
        vectors = {
          "symbols" => [
            { "symbol" => "SomeFunction", "keywords" => %w[some function documented] }
          ]
        }
        File.write(File.join(dir, ".docs", "vectors.json"), JSON.pretty_generate(vectors))

        # Create INDEX.md with symbol exact match (score 100)
        index_content = <<~MD
          # INDEX: test

          ## Symbols

          | Name | Type | File | Line | Doc |
          | --- | --- | --- | --- | --- |
          | SomeFunction | method | code.rb | 1 | false |
        MD
        File.write(File.join(dir, ".docs", "INDEX.md"), index_content)

        # Use source: true to get source_grep results too
        result = service.search(dir, "SomeFunction", options: { source: true })

        expect(result[:results]).not_to be_empty
        scores = result[:results].map { |r| r[:score] }
        expect(scores).to eq(scores.sort.reverse),
          "Expected scores #{scores} to be sorted descending"

        # The highest score should be from symbol_exact (100)
        expect(result[:results].first[:score]).to eq(100)
      end
    end
  end

  # ── Test 7: limit option caps results ───────────────────────────────

  describe "limit option" do
    it "returns at most `limit` results" do
      with_project_dir do |dir|
        # Create vectors.json with many entries that match
        symbols = (1..10).map do |i|
          { "symbol" => "Symbol#{i}", "keywords" => %w[match term] }
        end
        vectors = { "symbols" => symbols }
        File.write(File.join(dir, ".docs", "vectors.json"), JSON.pretty_generate(vectors))

        # Create SUMMARY.md and AGENTS.md with the term
        File.write(File.join(dir, ".docs", "SUMMARY.md"), "match term appears here")
        File.write(File.join(dir, ".docs", "AGENTS.md"), "match term appears here too")

        result = service.search(dir, "match term", options: { limit: 3 })

        expect(result[:results].size).to eq(3)
        expect(result[:total]).to eq(3)
      end
    end

    it "returns all results when limit is 999999" do
      with_project_dir do |dir|
        symbols = (1..5).map do |i|
          { "symbol" => "Symbol#{i}", "keywords" => %w[match term] }
        end
        vectors = { "symbols" => symbols }
        File.write(File.join(dir, ".docs", "vectors.json"), JSON.pretty_generate(vectors))

        result = service.search(dir, "match term", options: { limit: 999_999 })

        expect(result[:results].size).to be >= 5
      end
    end
  end

  # ── Test 8: Integration test with realistic fixture ─────────────────

  describe "integration test" do
    it "searches a realistic .docs/ structure and returns meaningful results" do
      with_nested_project_dir do |dir|
        # Root INDEX.md with symbols
        root_index = <<~MD
          # INDEX: test

          ## Symbols

          | Name | Type | File | Line | Doc |
          | --- | --- | --- | --- | --- |
          | RootModule | module | root.rb | 1 | true |

          ## Dependencies

          | From | Type | To |
          | --- | --- | --- |
          | root.rb | require | utils |
        MD
        File.write(File.join(dir, ".docs", "INDEX.md"), root_index)

        # Nested module INDEX.md with symbols
        nested_index = <<~MD
          # INDEX: module

          ## Symbols

          | Name | Type | File | Line | Doc |
          | --- | --- | --- | --- | --- |
          | NestedProcessor | class | nested.rb | 5 | true |
          | SubHelper | module | sub_helper.rb | 10 | false |

          ## Dependencies

          | From | Type | To |
          | --- | --- | --- |
          | nested.rb | require | sub_helper |
        MD
        File.write(File.join(dir, ".docs", "module", "INDEX.md"), nested_index)

        # Even more nested INDEX.md
        sub_index = <<~MD
          # INDEX: submodule

          ## Symbols

          | Name | Type | File | Line | Doc |
          | --- | --- | --- | --- | --- |
          | DeeplyNested | class | deep.rb | 3 | false |
        MD
        File.write(File.join(dir, ".docs", "module", "submodule", "INDEX.md"), sub_index)

        # Root vectors.json
        root_vectors = {
          "symbols" => [
            { "symbol" => "RootModule", "keywords" => %w[root module] }
          ]
        }
        File.write(File.join(dir, ".docs", "vectors.json"), JSON.pretty_generate(root_vectors))

        # Nested vectors.json
        nested_vectors = {
          "symbols" => [
            { "symbol" => "NestedProcessor", "keywords" => %w[nested processor helper] }
          ]
        }
        File.write(File.join(dir, ".docs", "module", "vectors.json"), JSON.pretty_generate(nested_vectors))

        # SUMMARY.md
        File.write(File.join(dir, ".docs", "SUMMARY.md"), <<~MD)
          # SUMMARY

          The project contains a NestedProcessor class.
        MD

        # Source file for source grep
        FileUtils.mkdir_p(File.join(dir, "lib"))
        File.write(File.join(dir, "lib", "nested.rb"), <<~RUBY)
          class NestedProcessor
            def run
              # process items
            end
          end
        RUBY

        # Search for "NestedProcessor" (should find symbol + summary matches)
        result = service.search(dir, "NestedProcessor")

        expect(result[:query]).to eq("NestedProcessor")
        expect(result[:results]).not_to be_empty
        expect(result[:total]).to be > 0

        # Should have at least one symbol_exact match
        symbol_match = result[:results].find { |r| r[:match_type] == "symbol_exact" }
        expect(symbol_match).not_to be_nil
        expect(symbol_match[:score]).to eq(100)
        expect(symbol_match[:file]).to match(/module\/INDEX\.md/)

        # Should have at least one summary_text match
        summary_match = result[:results].find { |r| r[:match_type] == "summary_text" }
        expect(summary_match).not_to be_nil
        expect(summary_match[:score]).to eq(20)

        # Search for "nested" with source:true should find source_grep too
        result2 = service.search(dir, "nested", options: { source: true })
        source_match = result2[:results].find { |r| r[:match_type] == "source_grep" }
        expect(source_match).not_to be_nil
        expect(source_match[:score]).to eq(10)
        expect(source_match[:file]).to match(/lib\/nested\.rb/)
      end
    end
  end

  # ── Additional edge cases ───────────────────────────────────────────

  describe "dependency match" do
    it "returns score 80 when term matches a dependency From or To column" do
      with_project_dir do |dir|
        index_content = <<~MD
          # INDEX: test

          ## Dependencies

          | From | Type | To |
          | --- | --- | --- |
          | controller.rb | require | payment_processor |
        MD
        File.write(File.join(dir, ".docs", "INDEX.md"), index_content)

        result = service.search(dir, "payment_processor")

        expect(result[:total]).to be >= 1
        match = result[:results].find { |r| r[:match_type] == "dependency_match" }
        expect(match).not_to be_nil
        expect(match[:score]).to eq(80)
      end
    end
  end

  describe "vector keyword low match" do
    it "returns score 40 when overlap is 1-2" do
      with_project_dir do |dir|
        vectors = {
          "symbols" => [
            { "symbol" => "Parser", "keywords" => %w[parse convert] }
          ]
        }
        File.write(File.join(dir, ".docs", "vectors.json"), JSON.pretty_generate(vectors))

        # "parse" overlaps 1 keyword
        result = service.search(dir, "parse transform")

        match = result[:results].find { |r| r[:match_type] == "vector_keyword_low" }
        expect(match).not_to be_nil
        expect(match[:score]).to eq(40)
      end
    end
  end

  # ── Test: vector keyword splitting (underscore / CamelCase) ─────────

  describe "vector keyword splitting" do
    it "splits on underscore boundaries: pi_manager matches keywords [pi, manager]" do
      with_project_dir do |dir|
        vectors = {
          "symbols" => [
            { "symbol" => "PiManager", "keywords" => %w[pi manager] }
          ]
        }
        File.write(File.join(dir, ".docs", "vectors.json"), JSON.pretty_generate(vectors))

        result = service.search(dir, "pi_manager")

        match = result[:results].find { |r| r[:match_type] == "vector_keyword_low" }
        expect(match).not_to be_nil
        expect(match[:score]).to eq(40)
      end
    end

    it "splits on CamelCase boundaries: OrchestratorService matches keywords [orchestrator, service]" do
      with_project_dir do |dir|
        vectors = {
          "symbols" => [
            { "symbol" => "OrchestratorService", "keywords" => %w[orchestrator service] }
          ]
        }
        File.write(File.join(dir, ".docs", "vectors.json"), JSON.pretty_generate(vectors))

        result = service.search(dir, "OrchestratorService")

        match = result[:results].find { |r| r[:match_type] == "vector_keyword_low" }
        expect(match).not_to be_nil
        expect(match[:score]).to eq(40)
      end
    end

    it "splits mixed underscore: my_symbol overlaps keywords [my, symbol, extra]" do
      with_project_dir do |dir|
        vectors = {
          "symbols" => [
            { "symbol" => "MySymbol", "keywords" => %w[my symbol extra] }
          ]
        }
        File.write(File.join(dir, ".docs", "vectors.json"), JSON.pretty_generate(vectors))

        # "my_symbol" should split to ["my", "symbol"], overlapping 2 of 3 keywords
        result = service.search(dir, "my_symbol")

        match = result[:results].find { |r| r[:match_type] == "vector_keyword_low" }
        expect(match).not_to be_nil
        expect(match[:score]).to eq(40)
      end
    end

    it "regression: single-word search still matches single keyword" do
      with_project_dir do |dir|
        vectors = {
          "symbols" => [
            { "symbol" => "Processor", "keywords" => %w[process] }
          ]
        }
        File.write(File.join(dir, ".docs", "vectors.json"), JSON.pretty_generate(vectors))

        result = service.search(dir, "process")

        match = result[:results].find { |r| r[:match_type] == "vector_keyword_low" }
        expect(match).not_to be_nil
        expect(match[:score]).to eq(40)
      end
    end

    it "handles edge-case terms with leading/trailing underscores that would produce empty strings" do
      with_project_dir do |dir|
        vectors = {
          "symbols" => [
            { "symbol" => "Processor", "keywords" => %w[processor] }
          ]
        }
        File.write(File.join(dir, ".docs", "vectors.json"), JSON.pretty_generate(vectors))

        result = service.search(dir, "_CamelCase_")

        expect(result).to be_a(Hash)
        expect(result[:results]).to be_an(Array)
      end
    end

    it "handles double underscore edge cases without crashing" do
      with_project_dir do |dir|
        vectors = {
          "symbols" => [
            { "symbol" => "Helper", "keywords" => %w[helper] }
          ]
        }
        File.write(File.join(dir, ".docs", "vectors.json"), JSON.pretty_generate(vectors))

        result = service.search(dir, "__double__")

        expect(result).to be_a(Hash)
        expect(result[:results]).to be_an(Array)
      end
    end
  end

  describe "AGENTS.md match" do
    it "finds matches in AGENTS.md files at any nesting level" do
      with_nested_project_dir do |dir|
        File.write(File.join(dir, ".docs", "module", "AGENTS.md"), <<~MD)
          # Agent Doc

          This module contains custom processing logic.
        MD

        result = service.search(dir, "processing logic")

        match = result[:results].find { |r| r[:match_type] == "summary_text" }
        expect(match).not_to be_nil
        expect(match[:score]).to eq(20)
        expect(match[:file]).to match(/module\/AGENTS\.md/)
      end
    end
  end

  describe "search result structure" do
    it "every result has the required keys" do
      with_project_dir do |dir|
        File.write(File.join(dir, ".docs", "SUMMARY.md"), "unique_search_term_xyz_123")
        result = service.search(dir, "unique_search_term_xyz_123")

        expect(result[:results]).not_to be_empty
        result[:results].each do |r|
          expect(r).to have_key(:file)
          expect(r).to have_key(:score)
          expect(r).to have_key(:match_type)
          expect(r).to have_key(:line)
          expect(r).to have_key(:context)
        end
      end
    end
  end
end
