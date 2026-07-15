# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

RSpec.describe AutoDoc::Generator::MapGenerator do
  subject(:generator) { described_class }

  let(:project_dir) { Dir.mktmpdir }
  let(:output_dir) { ".docs" }
  let(:output_abs) { File.join(project_dir, output_dir) }
  let(:config) { instance_double(AutoDoc::Config, module_roots: %w[app lib]) }
  let(:analyses) do
    {
      "/project/lib/foo.rb" => {
        definitions: [{ name: "Foo", type: :class, line: 1, has_doc?: true, methods: [] }],
        imports: [],
        docs: []
      },
      "/project/lib/bar.rb" => {
        definitions: [
          { name: "Bar", type: :module, line: 1, has_doc?: false, methods: [] },
          { name: "Bar#baz", type: :method, line: 5, has_doc?: true }
        ],
        imports: [],
        docs: []
      },
      "/project/app/controller.rb" => {
        definitions: [
          { name: "Controller", type: :class, line: 1, has_doc?: true, methods: [{ name: "index", line: 3 }] }
        ],
        imports: [],
        docs: []
      }
    }
  end
  let(:extra) { { coverage_pct: 75, total_symbols: 4 } }

  after do
    FileUtils.remove_entry(project_dir) if File.directory?(project_dir)
  end

  # Helper to create a file inside the mock docs directory
  def create_doc_file(relative_path)
    abs_path = File.join(output_abs, relative_path)
    FileUtils.mkdir_p(File.dirname(abs_path))
    File.write(abs_path, "content")
  end

  describe ".generate" do
    context "with a full set of documentation artifacts" do
      before do
        create_doc_file("INDEX.md")
        create_doc_file("SUMMARY.md")
        create_doc_file("VECTORS.json")
        create_doc_file("architecture.md")
        create_doc_file("diagrams/deps.mmd")
        create_doc_file("diagrams/class_diagram.mmd")
        create_doc_file("schema/schema.json")
        create_doc_file("schema/models.json")
        create_doc_file("lib/AGENTS.md")
        create_doc_file("lib/INDEX.md")
        create_doc_file("lib/SUMMARY.md")
        create_doc_file("lib/vectors.json")
      end

      it "includes schema_version" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:schema_version]).to eq("1.0")
      end

      it "includes generated_at timestamp" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:generated_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      it "includes project name" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:project]).to eq(File.basename(project_dir))
      end

      it "includes module_roots from config" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:module_roots]).to contain_exactly("app", "lib")
      end

      it "includes coverage_pct from extra" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:coverage_pct]).to eq(75.0)
      end

      it "includes total_symbols from extra" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:total_symbols]).to eq(4)
      end

      it "includes total_files based on analyses count" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:total_files]).to eq(3)
      end

      it "categorizes indexes correctly" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:artifacts][:indexes]).to contain_exactly("INDEX.md", "lib/INDEX.md")
      end

      it "categorizes summaries correctly" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:artifacts][:summaries]).to contain_exactly("SUMMARY.md", "lib/SUMMARY.md")
      end

      it "categorizes vectors correctly" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:artifacts][:vectors]).to include("VECTORS.json", "lib/vectors.json")
        expect(result[:artifacts][:vectors].size).to eq(2)
      end

      it "categorizes diagrams correctly" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:artifacts][:diagrams]).to contain_exactly("diagrams/deps.mmd", "diagrams/class_diagram.mmd")
      end

      it "categorizes agents_docs correctly" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:artifacts][:agents_docs]).to contain_exactly("lib/AGENTS.md")
      end

      it "categorizes architecture correctly" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:artifacts][:architecture]).to contain_exactly("architecture.md")
      end

      it "categorizes schema correctly" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:artifacts][:schema]).to contain_exactly("schema/schema.json", "schema/models.json")
      end

      it "writes .map.json to the output directory" do
        generator.generate(project_dir, output_dir, config, analyses, extra)
        map_path = File.join(output_abs, ".map.json")
        expect(File.exist?(map_path)).to be true
        parsed = JSON.parse(File.read(map_path))
        expect(parsed["project"]).to eq(File.basename(project_dir))
        expect(parsed["schema_version"]).to eq("1.0")
      end

      it "produces valid JSON that can be parsed" do
        generator.generate(project_dir, output_dir, config, analyses, extra)
        map_path = File.join(output_abs, ".map.json")
        parsed = JSON.parse(File.read(map_path))
        expect(parsed).to have_key("artifacts")
        expect(parsed["artifacts"]).to have_key("indexes")
        expect(parsed["artifacts"]).to have_key("summaries")
        expect(parsed["artifacts"]).to have_key("vectors")
        expect(parsed["artifacts"]).to have_key("diagrams")
        expect(parsed["artifacts"]).to have_key("agents_docs")
        expect(parsed["artifacts"]).to have_key("architecture")
        expect(parsed["artifacts"]).to have_key("schema")
      end

      it "returns the manifest hash" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result).to be_a(Hash)
        expect(result[:project]).to eq(File.basename(project_dir))
      end
    end

    context "with empty output directory" do
      it "returns empty artifact arrays" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        %i[indexes summaries vectors diagrams agents_docs architecture schema].each do |cat|
          expect(result[:artifacts][cat]).to be_empty
        end
      end

      it "still includes metadata keys" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:schema_version]).to eq("1.0")
        expect(result[:project]).to eq(File.basename(project_dir))
        expect(result[:total_files]).to eq(3)
      end
    end

    context "with missing optional artifacts" do
      before do
        create_doc_file("INDEX.md")
        create_doc_file("SUMMARY.md")
        create_doc_file("VECTORS.json")
        create_doc_file("diagrams/deps.mmd")
      end

      it "returns empty arrays for missing categories" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:artifacts][:architecture]).to be_empty
        expect(result[:artifacts][:schema]).to be_empty
        expect(result[:artifacts][:agents_docs]).to be_empty
      end

      it "populates present categories" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:artifacts][:indexes]).not_to be_empty
        expect(result[:artifacts][:summaries]).not_to be_empty
        expect(result[:artifacts][:vectors]).not_to be_empty
        expect(result[:artifacts][:diagrams]).not_to be_empty
      end
    end

    context "with default extra values" do
      let(:extra) { {} }

      it "defaults coverage_pct to 0.0" do
        result = generator.generate(project_dir, output_dir, config, analyses, {})
        expect(result[:coverage_pct]).to eq(0.0)
      end

      it "defaults total_symbols to 0" do
        result = generator.generate(project_dir, output_dir, config, analyses, {})
        expect(result[:total_symbols]).to eq(0)
      end
    end

    context "when output directory does not exist" do
      let(:output_dir) { "nonexistent" }

      it "does not crash" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:artifacts][:indexes]).to be_empty
        expect(result[:artifacts][:diagrams]).to be_empty
        expect(result[:schema_version]).to eq("1.0")
      end
    end

    context "with relative vector files (lowercase)" do
      before do
        create_doc_file("vectors.json")
        create_doc_file("subdir/vectors.json")
      end

      it "categorizes lowercase vectors.json" do
        result = generator.generate(project_dir, output_dir, config, analyses, extra)
        expect(result[:artifacts][:vectors]).to include("vectors.json", "subdir/vectors.json")
      end
    end
  end
end
