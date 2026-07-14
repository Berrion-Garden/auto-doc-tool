# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::Reporter::CompletenessChecker do
  subject(:checker) { described_class }

  describe ".check" do
    context "with all symbols documented" do
      let(:analyses) do
        {
          "/path/app/models/user.rb" => {
            symbols: [
              { name: "User", type: :class, has_doc?: true },
              { name: "find", type: :method, has_doc?: true }
            ]
          }
        }
      end

      it "returns 100% coverage" do
        result = checker.check(analyses)
        expect(result[:coverage_pct]).to eq(100.0)
        expect(result[:total]).to eq(2)
        expect(result[:documented]).to eq(2)
      end

      it "returns empty undocumented array" do
        result = checker.check(analyses)
        expect(result[:undocumented]).to be_empty
      end
    end

    context "with no symbols" do
      let(:analyses) { {} }

      it "returns 100% coverage" do
        result = checker.check(analyses)
        expect(result[:coverage_pct]).to eq(100.0)
        expect(result[:total]).to eq(0)
      end
    end

    context "with mix of documented and undocumented" do
      let(:analyses) do
        {
          "user.rb" => {
            symbols: [
              { name: "User", type: :class, has_doc?: true },
              { name: "find", type: :method, has_doc?: false },
              { name: "save", type: :method, has_doc?: false }
            ]
          }
        }
      end

      it "calculates correct coverage percentage" do
        result = checker.check(analyses)
        expect(result[:coverage_pct]).to eq(33.3)
        expect(result[:total]).to eq(3)
        expect(result[:documented]).to eq(1)
      end

      it "lists undocumented symbols with file info" do
        result = checker.check(analyses)
        expect(result[:undocumented].size).to eq(2)
        names = result[:undocumented].map { |s| s[:name] }
        expect(names).to include("find", "save")
      end
    end

    context "with nil analyses" do
      it "handles nil gracefully" do
        result = checker.check(nil)
        expect(result[:coverage_pct]).to eq(100.0)
        expect(result[:total]).to eq(0)
      end
    end

    context "with analyses in :definitions format" do
      let(:analyses) do
        {
          "math.rb" => {
            definitions: [
              { name: "MathUtils", type: :module, has_doc?: true },
              { name: "add", type: :method, has_doc?: false }
            ]
          }
        }
      end

      it "extracts symbols from definitions" do
        result = checker.check(analyses)
        expect(result[:total]).to eq(2)
        expect(result[:documented]).to eq(1)
      end
    end
  end
end
