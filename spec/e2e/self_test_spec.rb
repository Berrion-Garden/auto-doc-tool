# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"

RSpec.describe "E2E: auto-doc self-test" do
  before(:all) do
    @project_dir = File.expand_path("../../fixtures/sample_ruby_project", __dir__)
    @docs_dir = File.join(@project_dir, ".docs")
    @gem_lib = File.expand_path("../../lib", __dir__)
    @exe = File.expand_path("../../exe/auto-doc", __dir__)
    # Generate docs once for all tests
    `ruby -I#{@gem_lib} #{@exe} generate #{@project_dir} 2>&1`
  end

  after(:all) do
    FileUtils.rm_rf(@docs_dir) if File.directory?(@docs_dir)
  end

  it "generate creates .docs directory" do
    expect(File.directory?(@docs_dir)).to be(true)
  end

  it "generate creates README.md" do
    expect(File.exist?(File.join(@docs_dir, "README.md"))).to be(true)
  end

  it "generate creates diagrams/deps.mmd" do
    expect(File.exist?(File.join(@docs_dir, "diagrams", "deps.mmd"))).to be(true)
  end

  it "generate creates AGENTS.md for module roots" do
    agents_files = Dir.glob(File.join(@docs_dir, "*", "AGENTS.md"))
    expect(agents_files).not_to be_empty
  end

  it "audit --threshold 0 completes without crash" do
    output = `ruby -I#{@gem_lib} #{@exe} audit --threshold 0 #{@project_dir} 2>&1`
    expect($?.success?).to be(true), "audit failed: #{output.lines.first(3).join(" ")}"
  end

  it "audit creates report.json" do
    expect(File.exist?(File.join(@docs_dir, "report.json"))).to be(true)
  end

  it "report.json contains expected keys" do
    report = JSON.parse(File.read(File.join(@docs_dir, "report.json")))
    expect(report).to have_key("overall_coverage")
    expect(report).to have_key("total_symbols")
    expect(report).to have_key("passed")
  end

  it "orphans runs without crash" do
    output = `ruby -I#{@gem_lib} #{@exe} orphans #{@project_dir} 2>&1`
    expect($?.success?).to be(true)
  end

  it "version prints version string" do
    output = `ruby -I#{@gem_lib} #{@exe} version 2>&1`
    expect(output).to match(/auto-doc \d+\.\d+\.\d+/)
  end
end
