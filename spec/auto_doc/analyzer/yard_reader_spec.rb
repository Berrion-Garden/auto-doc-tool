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

    context "YARD enrichment" do
      let(:fixture) { fixture_path("sample_ruby_project", "lib", "yard_example.rb") }

      it "includes params/return_type/yield_type/tags fields with correct defaults" do
        result = described_class.extract(fixture_path("sample_ruby_project", "app", "models", "user.rb"))

        result.each do |comment|
          expect(comment).to have_key(:params)
          expect(comment).to have_key(:return_type)
          expect(comment).to have_key(:yield_type)
          expect(comment).to have_key(:tags)
          expect(comment[:params]).to eq([])
          expect(comment[:yield_type]).to be_nil
          expect(comment[:tags]).to eq([])
        end
      end

      it "extracts @param tags from fixture with YARD doc blocks" do
        result = described_class.extract(fixture)

        pmt = result.find { |c| c[:target_name] == "process_payment" }
        expect(pmt).not_to be_nil
        expect(pmt[:params]).to be_an(Array)
        expect(pmt[:params].size).to eq(2)

        amount_param = pmt[:params].find { |p| p[:name] == "amount" }
        expect(amount_param).not_to be_nil
        expect(amount_param[:types]).to eq(["Float"])
        expect(amount_param[:description]).to eq("The payment amount")

        currency_param = pmt[:params].find { |p| p[:name] == "currency" }
        expect(currency_param).not_to be_nil
        expect(currency_param[:types]).to eq(["String"])
      end

      it "extracts @return tag" do
        result = described_class.extract(fixture)

        pmt = result.find { |c| c[:target_name] == "process_payment" }
        expect(pmt).not_to be_nil
        expect(pmt[:return_type]).to eq("Boolean")
      end

      it "extracts @yield information" do
        result = described_class.extract(fixture)

        refund = result.find { |c| c[:target_name] == "refund" }
        expect(refund).not_to be_nil
        expect(refund[:yield_type]).to eq("Float")
      end

      it "extracts unrecognized @tags" do
        result = described_class.extract(fixture)

        history = result.find { |c| c[:target_name] == "history" }
        expect(history).not_to be_nil
        expect(history[:tags]).to be_an(Array)
        expect(history[:tags].size).to be >= 2

        example_tag = history[:tags].find { |t| t[:tag_name] == "example" }
        expect(example_tag).not_to be_nil
        expect(example_tag[:text]).to be_a(String)

        see_tag = history[:tags].find { |t| t[:tag_name] == "see" }
        expect(see_tag).not_to be_nil
      end

      it "Comment with no @tags returns empty arrays/nil" do
        result = described_class.extract(fixture)

        version = result.find { |c| c[:target_name] == "version" }
        expect(version).not_to be_nil
        expect(version[:params]).to eq([])
        expect(version[:return_type]).to be_nil
        expect(version[:yield_type]).to be_nil
        expect(version[:tags]).to eq([])
      end
    end
  end
end
