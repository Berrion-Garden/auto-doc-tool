# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::Analyzer::SourceParser do
  describe ".parse_file" do
    context "with a file containing class definitions" do
      it "extracts class names and line numbers" do
        definitions = described_class.parse_file(fixture_path("sample_ruby_project", "app", "models", "user.rb"))

        expect(definitions).to be_an(Array)
        names = definitions.map { |d| d[:name] }
        expect(names).to include("User")
      end

      it "identifies class type" do
        definitions = described_class.parse_file(fixture_path("sample_ruby_project", "app", "models", "user.rb"))
        user_def    = definitions.find { |d| d[:name] == "User" }

        expect(user_def).not_to be_nil
        expect(user_def[:type]).to eq(:class)
        expect(user_def[:line]).to be > 0
      end

      it "returns an array of hashes" do
        definitions = described_class.parse_file(fixture_path("sample_ruby_project", "app", "models", "user.rb"))

        definitions.each do |defn|
          expect(defn).to be_a(Hash)
          expect(defn.keys).to include(:name, :type, :line)
        end
      end
    end

    context "with a file containing module definitions" do
      it "extracts module names and type" do
        definitions = described_class.parse_file(fixture_path("sample_ruby_project", "lib", "math_utils.rb"))

        math_utils = definitions.find { |d| d[:name] == "MathUtils" }

        expect(math_utils).not_to be_nil
        expect(math_utils[:type]).to eq(:module)
      end
    end

    context "with a non-existent file" do
      it "returns an empty array" do
        result = described_class.parse_file("/nonexistent/path/file.rb")
        expect(result).to eq([])
      end
    end
  end
end
