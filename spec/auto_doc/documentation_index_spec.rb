# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require "json"

RSpec.describe AutoDoc::DocumentationIndex do
  subject(:index) { described_class.new(docs_dir) }

  let(:docs_dir) { Dir.mktmpdir("docs_index_spec") }

  before do
    FileUtils.mkdir_p(docs_dir)
  end

  after do
    FileUtils.rm_rf(docs_dir)
  end

  # ── Helper: write a file inside docs_dir ──────────────────────────────
  def write_doc(relative_path, content)
    full_path = File.join(docs_dir, relative_path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end

  describe "#initialize" do
    it "initializes with docs_dir" do
      expect(index).to be_a(described_class)
    end
  end

  describe "#symbols" do
    it "returns empty array when directory does not exist" do
      missing = described_class.new("/nonexistent/path")
      expect(missing.symbols).to eq([])
    end

    it "extracts symbol records from INDEX.md files" do
      write_doc("module/INDEX.md", <<~MD)
        ## Symbols
        | Symbol | Type | File | Line | Documented |
        |--------|------|------|------|------------|
        | User | class | user.rb | 5 | ✅ |
        | AuthHelper | module | auth.rb | 10 | ❌ |
      MD

      expect(index.symbols).to contain_exactly(
        { symbol: "User", type: "class", file: "user.rb", line: "5", documented: "✅", source_file: "module/INDEX.md" },
        { symbol: "AuthHelper", type: "module", file: "auth.rb", line: "10", documented: "❌", source_file: "module/INDEX.md" }
      )
    end

    it "skips header and separator rows" do
      write_doc("INDEX.md", <<~MD)
        ## Symbols
        | Symbol | Type | File |
        |--------|------|------|
        | Foo | class | foo.rb |
      MD

      expect(index.symbols.size).to eq(1)
      expect(index.symbols.first[:symbol]).to eq("Foo")
    end

    it "lazily parses only once" do
      write_doc("INDEX.md", <<~MD)
        ## Symbols
        | Symbol | Type | File |
        |--------|------|------|
        | Original | class | orig.rb |
      MD

      first = index.symbols
      expect(first.size).to eq(1)

      # Add another file — should not be picked up since parse is cached
      write_doc("INDEX.md", <<~MD)
        ## Symbols
        | Symbol | Type | File |
        |--------|------|------|
        | New | class | new.rb |
      MD

      second = index.symbols
      expect(second).to eq(first)
    end

    it "returns source_file relative to docs_dir" do
      write_doc("subdir/INDEX.md", <<~MD)
        ## Symbols
        | Symbol | Type | File |
        |--------|------|------|
        | Bar | class | bar.rb |
      MD

      expect(index.symbols.first[:source_file]).to eq("subdir/INDEX.md")
    end
  end

  describe "#dependencies" do
    it "extracts dependency records from INDEX.md files" do
      write_doc("INDEX.md", <<~MD)
        ## Dependencies
        | From | Type | To |
        |------|------|----|
        | user.rb | require | active_record |
        | auth.rb | include | Authenticatable |
      MD

      expect(index.dependencies).to contain_exactly(
        { from: "user.rb", type: "require", to: "active_record", source_file: "INDEX.md" },
        { from: "auth.rb", type: "include", to: "Authenticatable", source_file: "INDEX.md" }
      )
    end

    it "skips 'No dependencies detected' rows" do
      write_doc("INDEX.md", <<~MD)
        ## Dependencies
        | From | Type | To |
        |------|------|----|
        | — |  |  |
        | _No dependencies detected_ |  |  |
        | _None_ |  |  |
        | user.rb | require | active_record |
      MD

      expect(index.dependencies.size).to eq(1)
      expect(index.dependencies.first[:from]).to eq("user.rb")
    end
  end

  describe "#vectors" do
    it "returns merged symbols from vectors.json files" do
      write_doc("vectors.json", JSON.dump({ "symbols" => [{ "name" => "User" }] }))
      write_doc("sub/VECTORS.json", JSON.dump({ "symbols" => [{ "name" => "Post" }] }))

      expect(index.vectors["symbols"]).to contain_exactly(
        { "name" => "User" },
        { "name" => "Post" }
      )
    end

    it "returns empty hash when no vectors files found" do
      expect(index.vectors).to eq({})
    end

    it "handles invalid JSON gracefully" do
      write_doc("vectors.json", "not valid json")
      expect(index.vectors).to eq({})
    end
  end

  describe "#all_md_files_content" do
    it "returns SUMMARY.md files" do
      write_doc("SUMMARY.md", "# Summary")
      result = index.all_md_files_content
      expect(result).to have_key("SUMMARY.md")
      expect(result["SUMMARY.md"]).to eq("# Summary")
    end

    it "returns AGENTS.md files" do
      write_doc("AGENTS.md", "# Agents")
      result = index.all_md_files_content
      expect(result).to have_key("AGENTS.md")
      expect(result["AGENTS.md"]).to eq("# Agents")
    end

    it "includes nested md files" do
      write_doc("sub/SUMMARY.md", "# Nested Summary")
      result = index.all_md_files_content
      expect(result).to have_key("sub/SUMMARY.md")
      expect(result["sub/SUMMARY.md"]).to eq("# Nested Summary")
    end
  end
end
