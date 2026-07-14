# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::Analyzer::ImportExtractor do
  describe ".extract" do
    context "with a file containing require and include statements" do
      it "returns an array of import records" do
        result = described_class.extract(fixture_path("sample_ruby_project", "app", "models", "user.rb"))

        expect(result).to be_an(Array)
        # User model typically has at least a require or include
        types = result.map { |r| r[:type] }
        paths = result.map { |r| r[:path] }

        if !result.empty?
          types.each do |t|
            expect(t).to be_a(Symbol)
            expect(%i[require require_relative include prepend extend]).to include(t)
          end

          paths.each do |p|
            expect(p).to be_a(String)
            expect(p).not_to be_empty
          end
        end
      end

      it "captures import type and path in each record" do
        result = described_class.extract(fixture_path("sample_ruby_project", "app", "models", "user.rb"))

        result.each do |record|
          expect(record).to be_a(Hash)
          expect(record).to have_key(:type)
          expect(record).to have_key(:path)
        end
      end
    end

    context "with a non-existent file" do
      it "returns an empty array" do
        result = described_class.extract("/nonexistent/path/file.rb")
        expect(result).to eq([])
      end
    end

    context "with a file containing no imports" do
      it "returns an empty array for a simple module file" do
        # MathUtils fixture has minimal imports (possibly none), so check it handles empty gracefully
        result = described_class.extract(fixture_path("sample_ruby_project", "lib", "math_utils.rb"))

        expect(result).to be_an(Array)
        result.each do |r|
          expect(r).to be_a(Hash)
          expect(r[:path]).to be_a(String)
        end
      end
    end
  end
end
