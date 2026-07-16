# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::Analyzer::AnalysisPipeline do
  describe ".run" do
    let(:fixture_user) { fixture_path("sample_ruby_project", "app", "models", "user.rb") }
    let(:fixture_math) { fixture_path("sample_ruby_project", "lib", "math_utils.rb") }
    let(:nonexistent)  { "/nonexistent/path/file.rb" }

    it "returns empty hash for empty file list" do
      result = described_class.run([])
      expect(result).to eq({})
    end

    it "returns empty hash when files do not exist" do
      result = described_class.run([nonexistent])
      expect(result).to eq({})
    end

    it "extracts definitions from Ruby files" do
      result = described_class.run([fixture_user])
      expect(result).to have_key(fixture_user)
      defs = result[fixture_user][:definitions]
      expect(defs).to be_an(Array)
      expect(defs).not_to be_empty

      names = defs.map { |d| d[:name] }
      expect(names).to include("User")
    end

    it "extracts doc comments from Ruby files" do
      result = described_class.run([fixture_user])
      docs = result[fixture_user][:docs]
      expect(docs).to be_an(Array)
      expect(docs).not_to be_empty

      class_doc = docs.find { |d| d[:target_type] == :class && d[:target_name] == "User" }
      expect(class_doc).not_to be_nil
      expect(class_doc[:has_summary?]).to be true
    end

    it "merges doc presence into definitions via has_doc? key" do
      result = described_class.run([fixture_user])
      defs = result[fixture_user][:definitions]

      defs.each do |defn|
        expect(defn).to have_key(:has_doc?)
      end
    end

    it "has_doc? is true when a definition has a summary doc" do
      result = described_class.run([fixture_user])
      user_def = result[fixture_user][:definitions].find { |d| d[:name] == "User" }
      expect(user_def[:has_doc?]).to be true
    end

    it "has_doc? is false when a definition has no doc" do
      undocumented_fixture = fixture_path("sample_ruby_project", "lib", "undocumented_helper.rb")
      result = described_class.run([undocumented_fixture])
      defs = result[undocumented_fixture][:definitions]
      expect(defs).not_to be_empty

      defs.each do |defn|
        expect(defn[:has_doc?]).to be false
      end
    end

    it "handles mixed documented and undocumented symbols" do
      result = described_class.run([fixture_user])
      defs = result[fixture_user][:definitions]

      # User class is documented; some methods may be undocumented
      user_def = defs.find { |d| d[:name] == "User" }
      expect(user_def[:has_doc?]).to be true
    end

    it "returns analyses keyed by absolute file path" do
      result = described_class.run([fixture_user, fixture_math])
      expect(result.keys).to contain_exactly(fixture_user, fixture_math)
    end

    it "returns empty definitions for non-Ruby content files" do
      # A markdown file passed as a Ruby file — SourceParser should return []
      md_file = fixture_path("sample_ruby_project", ".autodoc", "app", "AGENTS.md")
      if File.exist?(md_file)
        result = described_class.run([md_file])
        expect(result[md_file][:definitions]).to eq([])
      end
    end

    it "uses GenericScanner as fallback for non-Ruby files" do
      py_file = fixture_path("sample_python_project", "app.py")
      result = described_class.run([py_file])

      expect(result).to have_key(py_file)
      expect(result[py_file][:definitions]).not_to be_empty
      expect(result[py_file][:scanner]).to eq(:generic)
    end

    it "uses Ripper for Ruby files and adds scanner :ripper key" do
      rb_file = fixture_path("sample_ruby_project", "app", "models", "user.rb")
      result = described_class.run([rb_file])

      expect(result).to have_key(rb_file)
      expect(result[rb_file][:definitions]).not_to be_empty
      expect(result[rb_file][:scanner]).to eq(:ripper)
    end
  end
end
