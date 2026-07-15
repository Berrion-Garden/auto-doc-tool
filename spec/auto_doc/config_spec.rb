# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "yaml"

RSpec.describe AutoDoc::Config do
  subject(:config) { described_class }

  let(:project_dir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(project_dir) }

  describe ".load" do
    it "returns defaults when no .autodoc.yml exists" do
      cfg = config.load(project_dir)
      expect(cfg.module_roots).to eq(%w[app lib bin])
      expect(cfg.exclude_patterns).to eq(%w[vendor/**/* node_modules/**/* spec/**/*])
      expect(cfg.output_dir).to eq(".docs")
      expect(cfg.min_doc_coverage).to eq(80)
    end

    it "deep-merges YAML file values over defaults" do
      File.write(File.join(project_dir, ".autodoc.yml"), <<~YAML)
        module_roots:
          - src
        audit:
          min_doc_coverage: 90
      YAML

      cfg = config.load(project_dir)
      expect(cfg.module_roots).to eq(["src"])
      expect(cfg.min_doc_coverage).to eq(90)
      # Unset defaults preserved
      expect(cfg.exclude_patterns).to eq(%w[vendor/**/* node_modules/**/* spec/**/*])
    end

    it "applies CLI overrides on top of file config" do
      File.write(File.join(project_dir, ".autodoc.yml"), <<~YAML)
        module_roots:
          - app
        audit:
          min_doc_coverage: 80
      YAML

      cfg = config.load(project_dir, { exclude_patterns: ["tmp/**/*"] })
      expect(cfg.exclude_patterns).to eq(["tmp/**/*"])
      expect(cfg.module_roots).to eq(["app"])
    end

    it "walks up directory tree looking for .autodoc.yml" do
      child_dir = File.join(project_dir, "sub", "nested")
      FileUtils.mkdir_p(child_dir)

      File.write(File.join(project_dir, ".autodoc.yml"), <<~YAML)
        module_roots:
          - custom
      YAML

      cfg = config.load(child_dir)
      expect(cfg.module_roots).to eq(["custom"])
    end

    it "returns defaults for empty YAML file" do
      File.write(File.join(project_dir, ".autodoc.yml"), "")
      cfg = config.load(project_dir)
      expect(cfg.module_roots).to eq(%w[app lib bin])
    end

    it "handles nested output config" do
      File.write(File.join(project_dir, ".autodoc.yml"), <<~YAML)
        output:
          directory: .docs
      YAML

      cfg = config.load(project_dir)
      expect(cfg.output_dir).to eq(".docs")
    end

    describe "backward-compatible output_dir" do
      it "returns .docs by default when neither .docs/ nor .autodoc/ exist" do
        cfg = config.load(project_dir)
        expect(cfg.output_dir).to eq(".docs")
      end

      it "falls back to .autodoc when .docs/ doesn't exist but .autodoc/ does" do
        FileUtils.mkdir_p(File.join(project_dir, ".autodoc"))
        cfg = config.load(project_dir)
        expect(cfg.output_dir).to eq(".autodoc")
      end

      it "uses .docs when .docs/ directory already exists" do
        FileUtils.mkdir_p(File.join(project_dir, ".docs"))
        cfg = config.load(project_dir)
        expect(cfg.output_dir).to eq(".docs")
      end

      it "uses configured directory from YAML when it exists on disk" do
        File.write(File.join(project_dir, ".autodoc.yml"), <<~YAML)
          output:
            directory: .custom_docs
        YAML
        FileUtils.mkdir_p(File.join(project_dir, ".custom_docs"))
        cfg = config.load(project_dir)
        expect(cfg.output_dir).to eq(".custom_docs")
      end
    end

    it "handles nested diagram config" do
      File.write(File.join(project_dir, ".autodoc.yml"), <<~YAML)
        diagrams:
          generate_dag: false
          diagram_directory: graphs
      YAML

      cfg = config.load(project_dir)
      expect(cfg.generate_dag?).to be false
      expect(cfg.diagram_directory).to eq("graphs")
    end
  end
end
