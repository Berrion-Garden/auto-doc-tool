# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"

RSpec.describe "E2E: auto-doc self-test" do
  let(:project_dir) { File.expand_path("../../fixtures/sample_ruby_project", __dir__) }
  let(:docs_dir) { File.join(project_dir, ".docs") }
  let(:gem_lib) { File.expand_path("../../lib", __dir__) }
  let(:exe) { File.expand_path("../../exe/auto-doc", __dir__) }

  after(:each) do
    FileUtils.rm_rf(docs_dir) if File.directory?(docs_dir)
  end

  it "version prints version string" do
    output = `ruby -I#{gem_lib} #{exe} version 2>&1`
    expect(output).to match(/auto-doc \d+\.\d+\.\d+/)
  end

  context "generate command" do
    before(:each) do
      @generate_output = `ruby -I#{gem_lib} #{exe} generate #{project_dir} 2>&1`
    end

    it "creates .docs directory" do
      expect(File.directory?(docs_dir)).to be(true), "generate output: #{@generate_output}"
    end

    it "creates README.md" do
      expect(File.exist?(File.join(docs_dir, "README.md"))).to be(true)
    end

    it "creates diagrams/deps.mmd" do
      expect(File.exist?(File.join(docs_dir, "diagrams", "deps.mmd"))).to be(true)
    end

    it "creates AGENTS.md for module roots" do
      agents_files = Dir.glob(File.join(docs_dir, "*", "AGENTS.md"))
      expect(agents_files).not_to be_empty
    end
  end

  context "audit command" do
    before(:each) do
      `ruby -I#{gem_lib} #{exe} generate #{project_dir} 2>&1`
      @audit_output = `ruby -I#{gem_lib} #{exe} audit --threshold 0 #{project_dir} 2>&1`
    end

    it "completes without crash" do
      expect($?.success?).to be(true), "audit failed: #{@audit_output.lines.first(3).join(" ")}"
    end

    it "creates report.json" do
      expect(File.exist?(File.join(docs_dir, "report.json"))).to be(true)
    end

    it "report.json contains expected keys" do
      report = JSON.parse(File.read(File.join(docs_dir, "report.json")))
      expect(report).to have_key("overall_coverage")
      expect(report).to have_key("total_symbols")
      expect(report).to have_key("passed")
    end
  end

  context "orphans command" do
    before(:each) do
      @orphans_output = `ruby -I#{gem_lib} #{exe} orphans #{project_dir} 2>&1`
    end

    it "runs without crash" do
      expect($?.success?).to be(true)
    end
  end
end
