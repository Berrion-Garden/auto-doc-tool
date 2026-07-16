# frozen_string_literal: true

require "spec_helper"

# Test helper that includes the MetricsHelper module
class MetricsHelperTestClass
  include AutoDoc::Orchestrator::MetricsHelper
end

RSpec.describe AutoDoc::Orchestrator::MetricsHelper do
  subject(:helper) { MetricsHelperTestClass.new }

  let(:empty_analyses) { {} }

  let(:analyses_with_classes) do
    {
      "/path/to/file.rb" => {
        definitions: [
          { name: "MyClass", type: :class, methods: [{ name: "foo" }, { name: "bar" }] },
          { name: "MyModule", type: :module, methods: [{ name: "baz" }] }
        ]
      }
    }
  end

  let(:analyses_with_no_methods) do
    {
      "/path/to/file.rb" => {
        definitions: [
          { name: "MyClass", type: :class, methods: [] }
        ]
      }
    }
  end

  describe "#count_classes_and_methods" do
    it "counts classes and modules" do
      cls, methods = helper.count_classes_and_methods(analyses_with_classes)
      expect(cls).to eq(2)
    end

    it "counts methods within each class/module" do
      cls, methods = helper.count_classes_and_methods(analyses_with_classes)
      expect(methods).to eq(3)
    end

    it "returns [0, 0] for empty analyses" do
      cls, methods = helper.count_classes_and_methods(empty_analyses)
      expect(cls).to eq(0)
      expect(methods).to eq(0)
    end

    it "skips nil definitions" do
      analyses = {
        "file.rb" => { definitions: [nil, { name: "Real", type: :class, methods: [] }] }
      }
      cls, methods = helper.count_classes_and_methods(analyses)
      expect(cls).to eq(1)
    end

    it "skips string definitions (not Hash)" do
      analyses = {
        "file.rb" => { definitions: ["string_defn", { name: "Real", type: :class, methods: [] }] }
      }
      cls, methods = helper.count_classes_and_methods(analyses)
      expect(cls).to eq(1)
    end
  end

  describe "#calculate_coverage" do
    it "returns coverage percentage as string" do
      analyses = {
        "file.rb" => { definitions: [{ name: "Docd", type: :class, has_doc?: true }] }
      }
      result = helper.calculate_coverage(analyses)
      expect(result).to be_a(String)
    end

    it "returns 100 when all documented" do
      analyses = {
        "file.rb" => { definitions: [{ name: "Docd", type: :class, has_doc?: true }] }
      }
      expect(helper.calculate_coverage(analyses)).to eq("100.0")
    end

    it "returns 0 when none documented" do
      analyses = {
        "file.rb" => { definitions: [{ name: "NoDoc", type: :class, has_doc?: false }] }
      }
      # The CompletenessChecker returns 0.0 when total > 0 and documented == 0
      result = helper.calculate_coverage(analyses)
      expect(result).to eq("0.0")
    end
  end
end
