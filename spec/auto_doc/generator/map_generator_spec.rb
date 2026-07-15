# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

RSpec.describe AutoDoc::Generator::MapGenerator do
  subject(:generator) { described_class }

  let(:project_dir) { Dir.mktmpdir }
  let(:output_dir) { ".docs" }
  let(:project_name) { "TestProject" }
  let(:output_abs) { File.join(project_dir, output_dir) }

  after do
    FileUtils.remove_entry(project_dir) if File.directory?(project_dir)
  end

  # Helper to create a file inside the mock docs directory
  def create_doc_file(relative_path)
    abs_path = File.join(output_abs, relative_path)
    FileUtils.mkdir_p(File.dirname(abs_path))
    File.write(abs_path, "content")
  end

  # Helper to create a VECTORS.json with a given symbol count
  def create_vectors(symbol_count)
    symbols = symbol_count.times.map do |i|
      { id: "sym_#{i}", symbol: "Symbol#{i}", type: "class", file: "/project/lib/foo.rb", line: i + 1 }
    end
    create_doc_file("vectors.json")
    File.write(File.join(output_abs, "vectors.json"), JSON.pretty_generate({ symbols: symbols }))
  end

  describe ".generate" do
    context "with a full mock docs directory" do
      before do
        # Create a full set of documentation artifacts
        create_doc_file("INDEX.md")
        create_doc_file("SUMMARY.md")
        create_doc_file("README.md")
        create_doc_file("vectors.json")
        create_doc_file("architecture.md")
        create_doc_file("report.json")
        create_doc_file("diagrams/deps.mmd")
        create_doc_file("diagrams/class_diagram.mmd")
        create_doc_file("schema/schema.json")
        create_doc_file("schema/models.json")
        create_doc_file("lib/AGENTS.md")
        create_doc_file("lib/INDEX.md")
        create_doc_file("lib/SUMMARY.md")
        create_doc_file("lib/vectors.json")
        create_vectors(5)
      end

      it "categorizes indexes correctly" do
        result = generator.generate(project_dir, output_dir, project_name, coverage_pct: 80, total_symbols: 10)
        expect(result[:artifacts][:indexes]).to contain_exactly("INDEX.md", "lib/INDEX.md")
      end

      it "categorizes summaries correctly" do
        result = generator.generate(project_dir, output_dir, project_name, coverage_pct: 80, total_symbols: 10)
        expect(result[:artifacts][:summaries]).to contain_exactly("SUMMARY.md", "lib/SUMMARY.md")
      end

      it "categorizes readme correctly" do
        result = generator.generate(project_dir, output_dir, project_name, coverage_pct: 80, total_symbols: 10)
        expect(result[:artifacts][:readme]).to contain_exactly("README.md")
      end

      it "categorizes vectors correctly" do
        result = generator.generate(project_dir, output_dir, project_name, coverage_pct: 80, total_symbols: 10)
        expect(result[:artifacts][:vectors]).to include("vectors.json", "lib/vectors.json")
        expect(result[:artifacts][:vectors].size).to eq(2)
      end

      it "categorizes diagrams correctly" do
        result = generator.generate(project_dir, output_dir, project_name, coverage_pct: 80, total_symbols: 10)
        expect(result[:artifacts][:diagrams]).to contain_exactly("diagrams/deps.mmd", "diagrams/class_diagram.mmd")
      end

      it "categorizes agents_docs correctly" do
        result = generator.generate(project_dir, output_dir, project_name, coverage_pct: 80, total_symbols: 10)
        expect(result[:artifacts][:agents_docs]).to contain_exactly("lib/AGENTS.md")
      end

      it "categorizes architecture correctly" do
        result = generator.generate(project_dir, output_dir, project_name, coverage_pct: 80, total_symbols: 10)
        expect(result[:artifacts][:architecture]).to contain_exactly("architecture.md")
      end

      it "categorizes schema correctly" do
        result = generator.generate(project_dir, output_dir, project_name, coverage_pct: 80, total_symbols: 10)
        expect(result[:artifacts][:schema]).to contain_exactly("schema/schema.json", "schema/models.json")
      end

      it "categorizes audit correctly" do
        result = generator.generate(project_dir, output_dir, project_name, coverage_pct: 80, total_symbols: 10)
        expect(result[:artifacts][:audit]).to contain_exactly("report.json")
      end

      it "discovers module roots from AGENTS.md files" do
        result = generator.generate(project_dir, output_dir, project_name, coverage_pct: 80, total_symbols: 10)
        expect(result[:module_roots]).to contain_exactly("lib")
      end

      it "includes schema_version" do
        result = generator.generate(project_dir, output_dir, project_name, coverage_pct: 80, total_symbols: 10)
        expect(result[:schema_version]).to eq(1)
      end

      it "includes generated_at timestamp" do
        result = generator.generate(project_dir, output_dir, project_name, coverage_pct: 80, total_symbols: 10)
        expect(result[:generated_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      it "includes project name" do
        result = generator.generate(project_dir, output_dir, project_name, coverage_pct: 80, total_symbols: 10)
        expect(result[:project]).to eq("TestProject")
      end

      it "includes coverage_pct" do
        result = generator.generate(project_dir, output_dir, project_name, coverage_pct: 80, total_symbols: 10)
        expect(result[:coverage_pct]).to eq(80)
      end

      it "includes total_symbols" do
        result = generator.generate(project_dir, output_dir, project_name, coverage_pct: 80, total_symbols: 10)
        expect(result[:total_symbols]).to eq(10)
      end

      it "writes .map.json to the output directory" do
        generator.generate(project_dir, output_dir, project_name, coverage_pct: 80, total_symbols: 10)
        map_path = File.join(output_abs, ".map.json")
        expect(File.exist?(map_path)).to be true
        parsed = JSON.parse(File.read(map_path))
        expect(parsed["project"]).to eq("TestProject")
      end
    end

    context "with custom output_path" do
      let(:custom_path) { File.join(project_dir, "custom_map.json") }

      after { FileUtils.rm_f(custom_path) }

      it "writes to the specified path" do
        create_doc_file("INDEX.md")
        generator.generate(project_dir, output_dir, project_name, coverage_pct: 80, total_symbols: 5, output_path: custom_path)
        expect(File.exist?(custom_path)).to be true
        parsed = JSON.parse(File.read(custom_path))
        expect(parsed["project"]).to eq("TestProject")
      end
    end

    context "with empty output directory" do
      it "returns empty artifact arrays" do
        result = generator.generate(project_dir, output_dir, project_name)
        %i[indexes summaries readme vectors diagrams agents_docs architecture schema audit].each do |cat|
          expect(result[:artifacts][cat]).to be_empty
        end
      end

      it "returns empty module roots" do
        result = generator.generate(project_dir, output_dir, project_name)
        expect(result[:module_roots]).to be_empty
      end

      it "defaults total_symbols to 0" do
        result = generator.generate(project_dir, output_dir, project_name)
        expect(result[:total_symbols]).to eq(0)
      end
    end

    context "with missing optional artifacts" do
      before do
        # Only create some artifacts (no schema/, no architecture.md)
        create_doc_file("INDEX.md")
        create_doc_file("SUMMARY.md")
        create_doc_file("vectors.json")
        create_doc_file("diagrams/deps.mmd")
      end

      it "omits those categories gracefully as empty arrays" do
        result = generator.generate(project_dir, output_dir, project_name)
        expect(result[:artifacts][:architecture]).to be_empty
        expect(result[:artifacts][:schema]).to be_empty
        expect(result[:artifacts][:audit]).to be_empty
        expect(result[:artifacts][:agents_docs]).to be_empty
      end

      it "still populates present categories" do
        result = generator.generate(project_dir, output_dir, project_name)
        expect(result[:artifacts][:indexes]).not_to be_empty
        expect(result[:artifacts][:summaries]).not_to be_empty
        expect(result[:artifacts][:vectors]).not_to be_empty
        expect(result[:artifacts][:diagrams]).not_to be_empty
      end
    end

    context "when vectors.json exists" do
      before { create_vectors(7) }

      it "counts symbols from vectors.json when not explicitly provided" do
        result = generator.generate(project_dir, output_dir, project_name)
        expect(result[:total_symbols]).to eq(7)
      end
    end

    context "when output directory does not exist" do
      it "does not crash" do
        result = generator.generate(project_dir, "nonexistent", project_name)
        expect(result[:artifacts][:indexes]).to be_empty
        expect(result[:artifacts][:diagrams]).to be_empty
      end
    end
  end

  describe "#generate" do
    it "works with instance as well" do
      create_doc_file("INDEX.md")
      instance = described_class.new(project_dir, output_dir, project_name)
      result = instance.generate
      expect(result[:project]).to eq("TestProject")
      expect(result[:artifacts][:indexes]).to include("INDEX.md")
    end
  end
end
