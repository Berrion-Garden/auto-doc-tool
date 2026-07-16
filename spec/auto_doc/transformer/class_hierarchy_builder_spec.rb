# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::Transformer::ClassHierarchyBuilder do
  subject(:builder) { described_class }

  let(:analyses_with_classes) do
    {
      "/path/to/user.rb" => {
        definitions: [
          {
            name: "User",
            type: :class,
            parent: "ApplicationRecord",
            includes: ["Authenticatable", "SoftDeletable"],
            extends: [],
            methods: [
              { name: "find_by_email" },
              { name: "full_name" }
            ]
          }
        ]
      }
    }
  end

  describe ".build" do
    it "build extracts class records from analyses" do
      result = builder.build(analyses_with_classes)
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq("User")
    end

    it "skips non-class definitions" do
      analyses = {
        "file.rb" => {
          definitions: [
            { name: "MyModule", type: :module },
            { name: "MyClass", type: :class }
          ]
        }
      }
      result = builder.build(analyses)
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq("MyClass")
    end

    it "skips nil definitions" do
      analyses = {
        "file.rb" => {
          definitions: [nil, { name: "RealClass", type: :class }]
        }
      }
      result = builder.build(analyses)
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq("RealClass")
    end

    it "skips string definitions" do
      analyses = {
        "file.rb" => {
          definitions: ["just a string", { name: "RealClass", type: :class }]
        }
      }
      result = builder.build(analyses)
      expect(result.size).to eq(1)
      expect(result.first[:name]).to eq("RealClass")
    end

    it "includes parent class information" do
      result = builder.build(analyses_with_classes)
      expect(result.first[:parent]).to eq("ApplicationRecord")
    end

    it "includes includes and extends arrays" do
      result = builder.build(analyses_with_classes)
      expect(result.first[:includes]).to eq(["Authenticatable", "SoftDeletable"])
      expect(result.first[:extends]).to eq([])
    end

    it "formats methods as Mermaid-compatible strings" do
      result = builder.build(analyses_with_classes)
      expect(result.first[:methods]).to contain_exactly("+find_by_email()", "+full_name()")
    end

    it "returns empty array when no classes found" do
      analyses = {
        "file.rb" => { definitions: [{ name: "Mod", type: :module }] }
      }
      result = builder.build(analyses)
      expect(result).to eq([])
    end

    it "handles analyses with empty definitions" do
      analyses = { "file.rb" => { definitions: [] } }
      result = builder.build(analyses)
      expect(result).to eq([])
    end
  end

  describe ".format_methods" do
    it "produces +name() format" do
      methods = [{ name: "foo" }, { name: "bar" }]
      result = builder.send(:format_methods, methods)
      expect(result).to contain_exactly("+foo()", "+bar()")
    end

    it "handles non-hash method entries" do
      methods = [{ name: "foo" }, "string_method", { name: "bar" }]
      result = builder.send(:format_methods, methods)
      expect(result).to contain_exactly("+foo()", "+string_method()", "+bar()")
    end

    it "handles empty methods array" do
      expect(builder.send(:format_methods, [])).to eq([])
    end
  end
end
