# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::Transformer::ContainerDataFlowBuilder do
  subject(:builder) { described_class }

  let(:module_roots) do
    ["/project/app/models", "/project/lib"]
  end

  let(:analyses) do
    {
      "/project/app/models/user.rb" => {
        definitions: [],
        imports: [
          { path: "/project/lib/math_utils", type: :require }
        ]
      },
      "/project/lib/math_utils.rb" => {
        definitions: [],
        imports: [
          { path: "json", type: :require }
        ]
      }
    }
  end

  describe ".build" do
    it "returns empty array when fewer than 2 module roots" do
      expect(builder.build(analyses, ["/project/app"])).to eq([])
    end

    it "returns empty array when no cross-module imports" do
      analyses = {
        "/project/app/models/user.rb" => {
          definitions: [],
          imports: [{ path: "active_record", type: :require }]
        },
        "/project/lib/math_utils.rb" => {
          definitions: [],
          imports: [{ path: "json", type: :require }]
        }
      }
      result = builder.build(analyses, module_roots)
      expect(result).to eq([])
    end

    it "creates flow records for cross-module imports" do
      result = builder.build(analyses, module_roots)
      expect(result).not_to be_empty
      expect(result.first[:from]).to eq("models")
      expect(result.first[:to]).to eq("lib")
      expect(result.first[:label]).to eq("imports")
    end

    it "deduplicates flows between same pair of modules" do
      # Two imports from models to lib should produce only one flow
      analyses = {
        "/project/app/models/user.rb" => {
          definitions: [],
          imports: [
            { path: "/project/lib/math_utils", type: :require },
            { path: "/project/lib/calculator", type: :require }
          ]
        }
      }
      result = builder.build(analyses, module_roots)
      expect(result.size).to eq(1)
    end

    it "excludes self-referencing flows" do
      # Import within the same module root
      analyses = {
        "/project/lib/math_utils.rb" => {
          definitions: [],
          imports: [{ path: "/project/lib/calculator", type: :require }]
        }
      }
      result = builder.build(analyses, module_roots)
      expect(result).to be_empty
    end

    it "uses module basename as flow identifier" do
      result = builder.build(analyses, module_roots)
      expect(result.first[:from]).to eq("models")
      expect(result.first[:to]).to eq("lib")
    end

    it "handles analyses with no imports" do
      analyses = {
        "/project/app/models/user.rb" => {
          definitions: [],
          imports: []
        }
      }
      result = builder.build(analyses, module_roots)
      expect(result).to eq([])
    end

    it "handles nil imports" do
      analyses = {
        "/project/app/models/user.rb" => {
          definitions: [],
          imports: nil
        }
      }
      result = builder.build(analyses, module_roots)
      expect(result).to eq([])
    end
  end
end
