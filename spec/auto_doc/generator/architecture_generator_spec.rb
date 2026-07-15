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
  end

  describe "#generate" do
    it "works with instance as well" do
      instance = described_class.new(project_name, [], [], [], {})
      result = instance.generate
      expect(result).to include("## System Overview")
    end
  end
end
