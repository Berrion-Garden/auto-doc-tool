# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe AutoDoc::Generator::ArchitectureGenerator do
  subject(:generator) { described_class }

  let(:project_name) { "MyApp" }
  let(:schema_tables) { [] }
  let(:models) { [] }
  let(:class_hierarchy) { [] }
  let(:config) { {} }

  describe ".generate" do
    context "with full data" do
      let(:models) do
        [
          {
            model: "User",
            table: "users",
            associations: [
              { type: "has_many", target: "Post", options: {} }
            ]
          },
          {
            model: "Post",
            table: "posts",
            associations: [
              { type: "belongs_to", target: "User", options: {} }
            ]
          }
        ]
      end

      let(:config) do
        {
          overview: "MyApp is a documentation tool.",
          design_decisions: [
            { title: "Use Rails", body: "Selected for rapid development." }
          ],
          diagram_links: [
            { title: "Class Diagram", path: "diagrams/class.mmd" }
          ]
        }
      end

      it "contains System Overview section" do
        result = generator.generate(project_name, schema_tables, models, class_hierarchy, config)
        expect(result).to include("## System Overview")
        expect(result).to include("MyApp is a documentation tool.")
      end

      it "contains Architecture Style section" do
        result = generator.generate(project_name, schema_tables, models, class_hierarchy, config)
        expect(result).to include("## Architecture Style")
      end

      it "contains Module Map section" do
        result = generator.generate(project_name, schema_tables, models, class_hierarchy, config)
        expect(result).to include("## Module Map")
      end

      it "contains Data Flow section" do
        result = generator.generate(project_name, schema_tables, models, class_hierarchy, config)
        expect(result).to include("## Data Flow")
      end

      it "contains Design Decisions section" do
        result = generator.generate(project_name, schema_tables, models, class_hierarchy, config)
        expect(result).to include("## Design Decisions")
      end

      it "contains Diagrams section" do
        result = generator.generate(project_name, schema_tables, models, class_hierarchy, config)
        expect(result).to include("## Diagrams")
      end

      it "renders Module Map table rows" do
        result = generator.generate(project_name, schema_tables, models, class_hierarchy, config)
        expect(result).to include("| User |")
        expect(result).to include("| Post |")
      end

      it "renders Data Flow table rows" do
        result = generator.generate(project_name, schema_tables, models, class_hierarchy, config)
        expect(result).to include("| User | Post |")
        expect(result).to include("| Post | User |")
      end

      it "renders Design Decisions" do
        result = generator.generate(project_name, schema_tables, models, class_hierarchy, config)
        expect(result).to include("### Use Rails")
        expect(result).to include("Selected for rapid development.")
      end

      it "renders Diagram Links" do
        result = generator.generate(project_name, schema_tables, models, class_hierarchy, config)
        expect(result).to include("[Class Diagram](diagrams/class.mmd)")
      end
    end

    context "architecture style detection" do
      it "detects Monolithic for single module" do
        models_with_one = [
          { model: "User", table: "users", associations: [] }
        ]
        result = generator.generate(project_name, schema_tables, models_with_one, class_hierarchy, config)
        expect(result).to include("Monolithic")
      end

      it "detects Modular Monolith for 2-3 modules" do
        models_with_two = [
          { model: "User", table: "users", associations: [] },
          { model: "Post", table: "posts", associations: [] }
        ]
        result = generator.generate(project_name, schema_tables, models_with_two, class_hierarchy, config)
        expect(result).to include("Modular Monolith")
      end

      it "detects Microservices for 4+ modules" do
        models_with_four = [
          { model: "User", table: "users", associations: [] },
          { model: "Post", table: "posts", associations: [] },
          { model: "Comment", table: "comments", associations: [] },
          { model: "Category", table: "categories", associations: [] }
        ]
        result = generator.generate(project_name, schema_tables, models_with_four, class_hierarchy, config)
        expect(result).to include("Microservices")
      end
    end

    context "with empty data" do
      it "returns all sections present with fallback text" do
        result = generator.generate(project_name, schema_tables, models, class_hierarchy, config)
        expect(result).to include("## System Overview")
        expect(result).to include("## Architecture Style")
        expect(result).to include("## Module Map")
        expect(result).to include("## Data Flow")
        expect(result).to include("## Design Decisions")
        expect(result).to include("## Diagrams")
        expect(result).to include("No overview provided.")
        expect(result).to include("No data flows defined.")
        expect(result).to include("No design decisions recorded.")
        expect(result).to include("No diagrams generated.")
      end
    end

    context "with output_path provided" do
      let(:output_dir) { Dir.mktmpdir }
      let(:output_path) { File.join(output_dir, "architecture.md") }

      after { FileUtils.remove_entry(output_dir) }

      it "writes the rendered content to file" do
        generator.generate(project_name, schema_tables, models, class_hierarchy, config, output_path: output_path)
        expect(File.exist?(output_path)).to be true
        content = File.read(output_path)
        expect(content).to include("## System Overview")
      end
    end

    it "includes the generated timestamp" do
      result = generator.generate(project_name, schema_tables, models, class_hierarchy, config)
      expect(result).to match(/Generated by auto-doc/)
    end

    context "with LLM integration" do
      let(:analyses_hash) { { "lib/foo.rb" => { definitions: [] } } }

      context "when LLM returns structured data" do
        let(:mock_client) { instance_double(AutoDoc::LLM::Client) }
        let(:auto_doc_config_obj) do
          instance_double(AutoDoc::Config, llm_config: { endpoint: "https://test", api_key: "test", model: "test-model" })
        end
        let(:llm_summary) do
          {
            purpose: "LLM-powered doc tool",
            style: "Event-Driven Architecture",
            modules: "- **IngestService** - Handles data ingestion\n- **ProcessPipeline** - Transforms raw data",
            data_flow: "- IngestService -> ProcessPipeline: Raw data flows for transformation\n- ProcessPipeline -> Storage: Transformed data persisted"
          }
        end

        before do
          allow(AutoDoc::LLM::Client).to receive(:build_if_configured).and_return(mock_client)
          allow(AutoDoc::LLM::Summarizer).to receive(:summarize_architecture_full).and_return(llm_summary)
        end

        it "uses LLM-provided overview text" do
          result = generator.generate(project_name, schema_tables, models, class_hierarchy, config,
            analyses: analyses_hash, auto_doc_config: auto_doc_config_obj)
          expect(result).to include("LLM-powered doc tool")
        end

        it "uses LLM-provided architecture style" do
          result = generator.generate(project_name, schema_tables, models, class_hierarchy, config,
            analyses: analyses_hash, auto_doc_config: auto_doc_config_obj)
          expect(result).to include("Event-Driven Architecture")
        end

        it "uses LLM-provided modules in Module Map" do
          result = generator.generate(project_name, schema_tables, models, class_hierarchy, config,
            analyses: analyses_hash, auto_doc_config: auto_doc_config_obj)
          expect(result).to include("| IngestService |")
          expect(result).to include("| ProcessPipeline |")
        end

        it "uses LLM-provided data flows" do
          result = generator.generate(project_name, schema_tables, models, class_hierarchy, config,
            analyses: analyses_hash, auto_doc_config: auto_doc_config_obj)
          expect(result).to include("| IngestService | ProcessPipeline |")
          expect(result).to include("| ProcessPipeline | Storage |")
        end
      end

      context "when LLM available but summary returns nil" do
        let(:mock_client) { instance_double(AutoDoc::LLM::Client) }
        let(:auto_doc_config_obj) do
          instance_double(AutoDoc::Config, llm_config: { endpoint: "https://test", api_key: "test", model: "test-model" })
        end

        before do
          allow(AutoDoc::LLM::Client).to receive(:build_if_configured).and_return(mock_client)
          allow(AutoDoc::LLM::Summarizer).to receive(:summarize_architecture_full).and_return(nil)
        end

        it "falls back to default overview text" do
          result = generator.generate(project_name, schema_tables, models, class_hierarchy, config,
            analyses: analyses_hash, auto_doc_config: auto_doc_config_obj)
          expect(result).to include("No overview provided.")
        end

        it "falls back to detected architecture style" do
          result = generator.generate(project_name, schema_tables, models, class_hierarchy, config,
            analyses: analyses_hash, auto_doc_config: auto_doc_config_obj)
          expect(result).to include("Monolithic")
        end
      end

      context "when auto_doc_config is nil" do
        it "falls through to static logic without calling LLM" do
          result = generator.generate(project_name, schema_tables, models, class_hierarchy, config,
            analyses: analyses_hash, auto_doc_config: nil)
          expect(result).to include("No overview provided.")
          expect(result).to include("Monolithic")
        end
      end
    end
  end

  describe "#parse_llm_modules" do
    subject(:instance) { described_class.new("test", [], [], [], {}) }

    it "parses **Name** - Description format" do
      result = instance.send(:parse_llm_modules, "- **IngestService** - Handles data ingestion")
      expect(result).to eq([{ name: "IngestService", responsibility: "Handles data ingestion" }])
    end

    it "parses Name: Description format" do
      result = instance.send(:parse_llm_modules, "- IngestService: Handles data ingestion")
      expect(result).to eq([{ name: "IngestService", responsibility: "Handles data ingestion" }])
    end

    it "returns empty array for nil input" do
      expect(instance.send(:parse_llm_modules, nil)).to eq([])
    end

    it "returns empty array for empty string" do
      expect(instance.send(:parse_llm_modules, "")).to eq([])
    end
  end

  describe "#parse_llm_data_flows" do
    subject(:instance) { described_class.new("test", [], [], [], {}) }

    it "parses From -> To: Description format" do
      result = instance.send(:parse_llm_data_flows, "- IngestService -> ProcessPipeline: Raw data flows")
      expect(result).to eq([{ from: "IngestService", to: "ProcessPipeline", description: "Raw data flows" }])
    end

    it "parses From → To: Description format (unicode arrow)" do
      result = instance.send(:parse_llm_data_flows, "- IngestService → ProcessPipeline: Raw data flows")
      expect(result).to eq([{ from: "IngestService", to: "ProcessPipeline", description: "Raw data flows" }])
    end

    it "returns empty array for nil input" do
      expect(instance.send(:parse_llm_data_flows, nil)).to eq([])
    end

    it "returns empty array for empty string" do
      expect(instance.send(:parse_llm_data_flows, "")).to eq([])
    end
  end

  describe "#generate" do
    it "works with instance as well" do
      instance = described_class.new(project_name, [], [], [], {})
      result = instance.generate
      expect(result).to include("## System Overview")
    end
  end
end
