# frozen_string_literal: true

require "spec_helper"

RSpec.describe "AutoDoc module" do
  it "has a VERSION constant" do
    expect(AutoDoc::VERSION).to eq("1.0.0")
    expect(AutoDoc::VERSION).to be_frozen
  end

  it "loads the CLI class" do
    expect(defined?(AutoDoc::CLI)).to eq("constant")
    expect(AutoDoc::CLI).to be_a(Class)
  end

  it "loads the Config class" do
    expect(defined?(AutoDoc::Config)).to eq("constant")
    expect(AutoDoc::Config).to be_a(Class)
  end

  it "loads all analyzer modules" do
    expect(defined?(AutoDoc::Analyzer::SourceParser)).to eq("constant")
    expect(defined?(AutoDoc::Analyzer::SchemaParser)).to eq("constant")
    expect(defined?(AutoDoc::Analyzer::ModelAssociationParser)).to eq("constant")
    expect(defined?(AutoDoc::Analyzer::ImportExtractor)).to eq("constant")
    expect(defined?(AutoDoc::Analyzer::YardReader)).to eq("constant")
  end

  it "loads all generator modules" do
    expect(defined?(AutoDoc::Generator::AgentsMdGenerator)).to eq("constant")
    expect(defined?(AutoDoc::Generator::ReadmeGenerator)).to eq("constant")
    expect(defined?(AutoDoc::Generator::DiagramGenerator)).to eq("constant")
    expect(defined?(AutoDoc::Generator::C4DiagramGenerator)).to eq("constant")
    expect(defined?(AutoDoc::Generator::ClassDiagramGenerator)).to eq("constant")
    expect(defined?(AutoDoc::Generator::ERDGenerator)).to eq("constant")
    expect(defined?(AutoDoc::Generator::ArchitectureGenerator)).to eq("constant")
  end

  it "loads all reporter modules" do
    expect(defined?(AutoDoc::Reporter::AuditReporter)).to eq("constant")
    expect(defined?(AutoDoc::Reporter::CompletenessChecker)).to eq("constant")
  end

  it "loads all utility modules" do
    expect(defined?(AutoDoc::Utils::FileTreeBuilder)).to eq("constant")
    expect(defined?(AutoDoc::Utils::YamlConfigLoader)).to eq("constant")
  end
end
