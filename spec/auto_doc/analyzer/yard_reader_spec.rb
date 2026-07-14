# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::Analyzer::YardReader do
  describe ".extract" do
    context "with a file containing doc comments before class definitions" do
      it "extracts doc comments for classes" do
        result = described_class.extract(fixture_path("sample_ruby_project", "app", "models", "user.rb"))

        expect(result).to be_an(Array)
        expect(result.size).to be > 0

        class_comment = result.find { |c| c[:target_type] == :class }
        expect(class_comment).not_to be_nil
        expect(class_comment[:target_name]).to eq("User")
        expect(class_comment[:has_summary?]).to be true
      end
    end

    context "with a file containing doc comments before module definitions" do
      it "extracts doc comments for modules" do
        result = described_class.extract(fixture_path("sample_ruby_project", "lib", "math_utils.rb"))

        expect(result).to be_an(Array)
        expect(result.size).to be > 0

        module_comment = result.find { |c| c[:target_type] == :module }
        expect(module_comment).not_to be_nil
        expect(module_comment[:target_name]).to eq("MathUtils")
        expect(module_comment[:has_summary?]).to be true
      end
    end

    context "with a file containing doc comments before method definitions" do
      it "extracts doc comments for methods" do
        result = described_class.extract(fixture_path("sample_ruby_project", "app", "models", "user.rb"))

        method_comments = result.select { |c| c[:target_type] == :method }
        expect(method_comments.size).to be > 0

        find_comment = method_comments.find { |c| c[:target_name] == "find_by_email" }
        expect(find_comment).not_to be_nil
        expect(find_comment[:has_summary?]).to be true
      end
    end

    context "with a non-existent file" do
      it "returns an empty array" do
        result = described_class.extract("/nonexistent/path/file.rb")
        expect(result).to eq([])
      end
    end

    context "with multi-line doc comments" do
      it "extracts the full comment body" do
        result = described_class.extract(fixture_path("sample_ruby_project", "lib", "math_utils.rb"))
        expect(result.size).to be > 0

        # All comments should have non-empty text
        result.each do |comment|
          expect(comment[:text]).not_to be_nil
          expect(comment[:text]).not_to be_empty
        end
      end
    end

    context "with fixture file that has no comments" do
      it "returns an empty array" do
        result = described_class.extract(fixture_path("sample_ruby_project", ".autodoc", "app", "AGENTS.md"))
        # AGENTS.md is not a Ruby file, so if the file exists it should return []
        # if it doesn't exist it should also return []
        expect(result).to eq([])
      end
    end
  end
end
