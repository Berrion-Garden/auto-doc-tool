# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe AutoDoc::Reporter::AuditReporter do
  subject(:reporter) { described_class }

  let(:project_dir) { Dir.mktmpdir }
  let(:config) { instance_double(AutoDoc::Config, min_doc_coverage: 80, max_module_size: 50) }
  after { FileUtils.remove_entry(project_dir) }

  describe ".generate" do
    context "with Array<Hash> format analyses" do
      let(:analyses) do
        [
          { file: "user.rb", symbols: %w[class_User method_find],
documented: %w[class_User] },
          { file: "math.rb", symbols: %w[module_MathUtils method_add],
documented: [] }
        ]
      end

      it "returns a report hash with expected keys" do
        report = reporter.generate(project_dir, config, analyses)
        expect(report).to be_a(Hash)
        expect(report).to have_key(:project)
        expect(report).to have_key(:overall_coverage)
        expect(report).to have_key(:total_symbols)
        expect(report).to have_key(:passed)
      end

      it "calculates coverage correctly" do
        report = reporter.generate(project_dir, config, analyses)
        expect(report[:total_symbols]).to eq(4)
        expect(report[:documented_symbols]).to eq(1)
        expect(report[:overall_coverage]).to eq(25.0)
      end

      it "sets passed to false when coverage below threshold" do
        report = reporter.generate(project_dir, config, analyses)
        expect(report[:passed]).to be false
      end
    end

    context "with Hash<String, Hash> format analyses (CLI format)" do
      let(:analyses) do
        {
          "user.rb" => {
            definitions: [
              { name: "User", type: :class, has_doc?: true },
              { name: "find", type: :method, has_doc?: false }
            ]
          }
        }
      end

      it "accepts hash-of-hashes format without error" do
        report = reporter.generate(project_dir, config, analyses)
        expect(report).to be_a(Hash)
        expect(report[:passed]).to_not be_nil
      end

      it "extracts symbols from definitions" do
        report = reporter.generate(project_dir, config, analyses)
        expect(report[:total_symbols]).to be > 0
      end
    end

    context "with 100% coverage" do
      let(:analyses) do
        [
          { file: "user.rb", symbols: %w[class_User],
documented: %w[class_User] }
        ]
      end

      it "sets passed to true" do
        report = reporter.generate(project_dir, config, analyses)
        expect(report[:passed]).to be true
      end

      it "sets overall_coverage to 100" do
        report = reporter.generate(project_dir, config, analyses)
        expect(report[:overall_coverage]).to eq(100.0)
      end
    end

    context "with module exceeding max size" do
      let(:big_config) { instance_double(AutoDoc::Config, min_doc_coverage: 80, max_module_size: 1) }
      let(:analyses) do
        [
          { file: "big.rb", symbols: %w[sym1 sym2 sym3],
documented: %w[sym1] }
        ]
      end

      it "reports module_too_large failure" do
        report = reporter.generate(project_dir, big_config, analyses)
        failures = report[:failures].select { |f| f[:reason] == "module_too_large" }
        expect(failures).not_to be_empty
        expect(failures.first[:size]).to eq(3)
      end
    end
  end

  describe ".format_text" do
    let(:report) do
      {
        project: "/test",
        generated_at: "2026-01-01T00:00:00Z",
        overall_coverage: 75.0,
        total_symbols: 4,
        documented_symbols: 3,
        undocumented: ["method_find"],
        min_coverage: 80,
        failures: [{ file: "user.rb", reason: "low_coverage",
coverage_pct: 50.0, threshold: 80 }],
        passed: false
      }
    end

    it "includes coverage percentage" do
      text = reporter.format_text(report)
      expect(text).to include("75.0%")
    end

    it "includes PASSED or FAILED status" do
      text = reporter.format_text(report)
      expect(text).to include("FAILED")
    end

    it "includes coverage stats" do
      text = reporter.format_text(report)
      expect(text).to include("75.0%")
      expect(text).to include("FAILED")
    end

    it "includes failure details" do
      text = reporter.format_text(report)
      expect(text).to include("50.0%")
    end
  end

  describe ".format_json" do
    let(:report) do
      {
        project: "/test",
        generated_at: "2026-01-01T00:00:00Z",
        overall_coverage: 100.0,
        total_symbols: 2,
        documented_symbols: 2,
        passed: true
      }
    end

    it "returns valid JSON" do
      json = reporter.format_json(report)
      parsed = JSON.parse(json)
      expect(parsed["project"]).to eq("/test")
    end

    it "contains all report keys" do
      json = reporter.format_json(report)
      parsed = JSON.parse(json)
      expect(parsed).to have_key("overall_coverage")
      expect(parsed).to have_key("passed")
    end
  end
end
