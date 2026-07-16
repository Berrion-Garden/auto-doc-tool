# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::LLM::ResponseParser do
  describe ".parse_purpose" do
    it "extracts content from ## Purpose section" do
      text = "## Purpose\nThis is the project purpose."
      expect(described_class.parse_purpose(text)).to eq("This is the project purpose.")
    end

    it "falls back to first paragraph when no ## Purpose section" do
      text = "This is the first paragraph.\n\nThis is the second."
      expect(described_class.parse_purpose(text)).to eq("This is the first paragraph.")
    end

    it "returns empty string for nil input" do
      expect(described_class.parse_purpose(nil)).to eq("")
    end

    it "returns empty string for empty input" do
      expect(described_class.parse_purpose("")).to eq("")
    end
  end

  describe ".parse_components" do
    it "parses **Name** - Description format" do
      text = <<~TEXT
        - **FooService** - Handles foo operations
        - **BarModule** - Manages bar data
      TEXT
      result = described_class.parse_components(text)
      expect(result).to eq([
        { name: "FooService", description: "Handles foo operations" },
        { name: "BarModule", description: "Manages bar data" }
      ])
    end

    it "parses Name: Description format" do
      text = <<~TEXT
        - FooService: Handles foo operations
        - BarModule: Manages bar data
      TEXT
      result = described_class.parse_components(text)
      expect(result).to eq([
        { name: "FooService", description: "Handles foo operations" },
        { name: "BarModule", description: "Manages bar data" }
      ])
    end

    it "returns empty array for nil input" do
      expect(described_class.parse_components(nil)).to eq([])
    end

    it "returns empty array for empty string" do
      expect(described_class.parse_components("")).to eq([])
    end
  end

  describe ".parse_architecture_full" do
    it "returns a hash with :purpose, :style, :modules, :data_flow keys" do
      response = <<~TEXT
        ## Purpose
        The project manages widgets.

        ## Architectural Style
        Microservices

        ## Main Modules
        - IngestService: Handles data ingestion
        - ProcessPipeline: Processes data

        ## Data Flow
        - IngestService -> ProcessPipeline: Raw data flows
      TEXT
      result = described_class.parse_architecture_full(response)
      expect(result).to be_a(Hash)
      expect(result.keys).to contain_exactly(:purpose, :style, :modules, :data_flow)
    end

    it "extracts the purpose section content" do
      response = "## Purpose\nThe project manages widgets."
      result = described_class.parse_architecture_full(response)
      expect(result[:purpose]).to eq("The project manages widgets.")
    end

    it "extracts the style section content" do
      response = "## Architectural Style\nMicroservices"
      result = described_class.parse_architecture_full(response)
      expect(result[:style]).to eq("Microservices")
    end

    it "extracts the modules section content" do
      response = "## Main Modules\n- IngestService: Handles data"
      result = described_class.parse_architecture_full(response)
      expect(result[:modules]).to eq("- IngestService: Handles data")
    end

    it "extracts the data flow section content" do
      response = "## Data Flow\n- IngestService -> Pipeline: flows"
      result = described_class.parse_architecture_full(response)
      expect(result[:data_flow]).to eq("- IngestService -> Pipeline: flows")
    end

    it "puts the entire response into :purpose when no headings are present" do
      response = "Just a plain paragraph with no markdown headings."
      result = described_class.parse_architecture_full(response)
      expect(result[:purpose]).to eq(response.strip)
      expect(result[:style]).to eq("")
      expect(result[:modules]).to eq("")
      expect(result[:data_flow]).to eq("")
    end

    it "returns nil for nil response" do
      expect(described_class.parse_architecture_full(nil)).to be_nil
    end
  end

  describe ".parse_system_context" do
    it "parses a JSON array response" do
      response = '[{"name": "Database", "interaction": "Reads and writes data"}]'
      result = described_class.parse_system_context(response)
      expect(result).to be_an(Array)
      expect(result.first[:name]).to eq("Database")
      expect(result.first[:interaction]).to eq("Reads and writes data")
    end

    it "parses markdown bullet format" do
      response = <<~TEXT
        - Database: Reads and writes data
        - API: Serves endpoints
      TEXT
      result = described_class.parse_system_context(response)
      expect(result).to eq([
        { name: "Database", interaction: "Reads and writes data" },
        { name: "API", interaction: "Serves endpoints" }
      ])
    end

    it "parses asterisk bullet format" do
      response = "* Database: Reads and writes data"
      result = described_class.parse_system_context(response)
      expect(result).to eq([{ name: "Database", interaction: "Reads and writes data" }])
    end

    it "returns nil for unparseable response" do
      expect(described_class.parse_system_context("garbage text")).to be_nil
    end

    it "returns nil for nil response" do
      expect(described_class.parse_system_context(nil)).to be_nil
    end
  end

  describe ".parse_containers" do
    it "returns a hash with module root names as keys" do
      response = "## Module Root: app\nHandles the main application logic."
      result = described_class.parse_containers(response)
      expect(result).to be_a(Hash)
      expect(result).to have_key("app")
    end

    it "extracts description content for each module root" do
      response = <<~TEXT
        ## Module Root: app
        Handles the main application logic.

        ## Module Root: lib
        Core library utilities.
      TEXT
      result = described_class.parse_containers(response)
      expect(result["app"]).to eq("Handles the main application logic.")
      expect(result["lib"]).to eq("Core library utilities.")
    end

    it "returns nil for plain text without section headings" do
      response = "Just some plain text."
      expect(described_class.parse_containers(response)).to be_nil
    end

    it "returns nil for nil response" do
      expect(described_class.parse_containers(nil)).to be_nil
    end
  end

  describe ".parse_llm_modules" do
    it "parses **Name** - Description format" do
      result = described_class.parse_llm_modules("- **IngestService** - Handles data ingestion")
      expect(result).to eq([{ name: "IngestService", responsibility: "Handles data ingestion" }])
    end

    it "parses Name: Description format" do
      result = described_class.parse_llm_modules("- IngestService: Handles data ingestion")
      expect(result).to eq([{ name: "IngestService", responsibility: "Handles data ingestion" }])
    end

    it "returns empty array for nil input" do
      expect(described_class.parse_llm_modules(nil)).to eq([])
    end

    it "returns empty array for empty string" do
      expect(described_class.parse_llm_modules("")).to eq([])
    end
  end

  describe ".parse_llm_data_flows" do
    it "parses From -> To: Description format" do
      result = described_class.parse_llm_data_flows("- IngestService -> ProcessPipeline: Raw data flows")
      expect(result).to eq([{ from: "IngestService", to: "ProcessPipeline", description: "Raw data flows" }])
    end

    it "parses From → To: Description format (unicode arrow)" do
      result = described_class.parse_llm_data_flows("- IngestService → ProcessPipeline: Raw data flows")
      expect(result).to eq([{ from: "IngestService", to: "ProcessPipeline", description: "Raw data flows" }])
    end

    it "returns empty array for nil input" do
      expect(described_class.parse_llm_data_flows(nil)).to eq([])
    end

    it "returns empty array for empty string" do
      expect(described_class.parse_llm_data_flows("")).to eq([])
    end
  end

  describe ".parse_symbol_summaries" do
    let(:symbol_types) { { "Foo" => "class", "Bar" => "module", "Foo::Bar" => "class" } }

    it "parses symbol name: summary format" do
      response = "Foo: does X\nBar: does Y"
      result = described_class.parse_symbol_summaries(response, symbol_types)
      expect(result).to eq({ "class_Foo" => "does X", "module_Bar" => "does Y" })
    end

    it "parses numbered-list format" do
      response = "1. Foo: does X\n2. Bar: does Y"
      result = described_class.parse_symbol_summaries(response, symbol_types)
      expect(result).to eq({ "class_Foo" => "does X", "module_Bar" => "does Y" })
    end

    it "parses numbered-list format with leading whitespace" do
      response = "  1. Foo: does X\n  2. Bar: does Y"
      result = described_class.parse_symbol_summaries(response, symbol_types)
      expect(result).to eq({ "class_Foo" => "does X", "module_Bar" => "does Y" })
    end

    it "returns empty hash for empty string" do
      expect(described_class.parse_symbol_summaries("", symbol_types)).to eq({})
    end

    it "returns empty hash for nil" do
      expect(described_class.parse_symbol_summaries(nil, symbol_types)).to eq({})
    end

    it "parses :: symbol names" do
      response = "Foo::Bar: does the thing"
      result = described_class.parse_symbol_summaries(response, symbol_types)
      expect(result).to eq({ "class_Foo_Bar" => "does the thing" })
    end

    it "parses numbered :: symbol names" do
      response = "1. Foo::Bar: does the thing"
      result = described_class.parse_symbol_summaries(response, symbol_types)
      expect(result).to eq({ "class_Foo_Bar" => "does the thing" })
    end

    it "handles single-character symbol names" do
      single_char_types = { "X" => "class" }
      response = "X: a single class"
      result = described_class.parse_symbol_summaries(response, single_char_types)
      expect(result).to eq({ "class_X" => "a single class" })
    end

    it "handles single-character numbered symbol names" do
      single_char_types = { "X" => "class" }
      response = "1. X: a single class"
      result = described_class.parse_symbol_summaries(response, single_char_types)
      expect(result).to eq({ "class_X" => "a single class" })
    end

    it "handles symbol names with colons and dashes" do
      complex_types = { "Foo-Bar" => "class", "Foo::Bar" => "module" }
      response = "1. Foo-Bar: first\n2. Foo::Bar: second"
      result = described_class.parse_symbol_summaries(response, complex_types)
      expect(result).to eq({ "class_Foo-Bar" => "first", "module_Foo_Bar" => "second" })
    end
  end
end
