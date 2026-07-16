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

  it "loads the DocumentationIndex class" do
    expect(defined?(AutoDoc::DocumentationIndex)).to eq("constant")
    expect(AutoDoc::DocumentationIndex).to be_a(Class)
  end

  it "loads the Server class" do
    expect(defined?(AutoDoc::Server)).to eq("constant")
    expect(AutoDoc::Server).to be_a(Class)
  end

  it "loads search and agent query services" do
    expect(defined?(AutoDoc::SearchService)).to eq("constant")
    expect(defined?(AutoDoc::AgentQueryService)).to eq("constant")
  end

  it "loads all utility modules" do
    expect(defined?(AutoDoc::Utils::FileTreeBuilder)).to eq("constant")
    expect(defined?(AutoDoc::Utils::YamlConfigLoader)).to eq("constant")
    expect(defined?(AutoDoc::Utils::TimestampTracker)).to eq("constant")
    expect(defined?(AutoDoc::Utils::OutputFormatter)).to eq("constant")
    expect(defined?(AutoDoc::Utils::MarkdownHelper)).to eq("constant")
  end

  it "loads all analyzer modules" do
    expect(defined?(AutoDoc::Analyzer::SourceParser)).to eq("constant")
    expect(defined?(AutoDoc::Analyzer::SchemaParser)).to eq("constant")
    expect(defined?(AutoDoc::Analyzer::ModelAssociationParser)).to eq("constant")
    expect(defined?(AutoDoc::Analyzer::ImportExtractor)).to eq("constant")
    expect(defined?(AutoDoc::Analyzer::YardReader)).to eq("constant")
    expect(defined?(AutoDoc::Analyzer::AnalysisCache)).to eq("constant")
    expect(defined?(AutoDoc::Analyzer::AnalysisPipeline)).to eq("constant")
    expect(defined?(AutoDoc::Analyzer::DiffService)).to eq("constant")
    expect(defined?(AutoDoc::Analyzer::OrphansService)).to eq("constant")
  end

  it "loads the LLM module" do
    expect(defined?(AutoDoc::LLM)).to eq("constant")
    expect(defined?(AutoDoc::LLM::Client)).to eq("constant")
    expect(defined?(AutoDoc::LLM::Summarizer)).to eq("constant")
  end

  it "loads all generator modules" do
    expect(defined?(AutoDoc::Generator::AgentsMdGenerator)).to eq("constant")
    expect(defined?(AutoDoc::Generator::ReadmeGenerator)).to eq("constant")
    expect(defined?(AutoDoc::Generator::DiagramGenerator)).to eq("constant")
    expect(defined?(AutoDoc::Generator::IndexGenerator)).to eq("constant")
    expect(defined?(AutoDoc::Generator::SummaryGenerator)).to eq("constant")
    expect(defined?(AutoDoc::Generator::VectorGenerator)).to eq("constant")
    expect(defined?(AutoDoc::Generator::C4DiagramGenerator)).to eq("constant")
    expect(defined?(AutoDoc::Generator::ClassDiagramGenerator)).to eq("constant")
    expect(defined?(AutoDoc::Generator::ERDGenerator)).to eq("constant")
    expect(defined?(AutoDoc::Generator::ArchitectureGenerator)).to eq("constant")
    expect(defined?(AutoDoc::Generator::MapGenerator)).to eq("constant")
    expect(defined?(AutoDoc::Generator::TemplateHelper)).to eq("constant")
  end

  it "loads all reporter modules" do
    expect(defined?(AutoDoc::Reporter::AuditReporter)).to eq("constant")
    expect(defined?(AutoDoc::Reporter::CompletenessChecker)).to eq("constant")
  end

  it "loads all transformer modules" do
    expect(defined?(AutoDoc::Transformer)).to eq("constant")
    expect(defined?(AutoDoc::Transformer::GraphDataBuilder)).to eq("constant")
    expect(defined?(AutoDoc::Transformer::ClassHierarchyBuilder)).to eq("constant")
    expect(defined?(AutoDoc::Transformer::ContainerDataFlowBuilder)).to eq("constant")
    expect(defined?(AutoDoc::Transformer::ERDRelationshipBuilder)).to eq("constant")
    expect(defined?(AutoDoc::Transformer::FilesDataBuilder)).to eq("constant")
  end

  it "loads all orchestrator modules" do
    expect(defined?(AutoDoc::Orchestrator)).to eq("constant")
    expect(defined?(AutoDoc::Orchestrator::Pipeline)).to eq("constant")
    expect(defined?(AutoDoc::Orchestrator::BaseStep)).to eq("constant")
    expect(defined?(AutoDoc::Orchestrator::AgentsMdStep)).to eq("constant")
    expect(defined?(AutoDoc::Orchestrator::ReadmeStep)).to eq("constant")
    expect(defined?(AutoDoc::Orchestrator::IndexSummaryVectorsStep)).to eq("constant")
    expect(defined?(AutoDoc::Orchestrator::DiagramStep)).to eq("constant")
    expect(defined?(AutoDoc::Orchestrator::ArchitectureStep)).to eq("constant")
    expect(defined?(AutoDoc::Orchestrator::ManifestStep)).to eq("constant")
    expect(defined?(AutoDoc::Orchestrator::MetricsHelper)).to eq("constant")
  end

  it "loads the e2e_runner" do
    expect(defined?(AutoDoc::Tester::E2ERunner)).to eq("constant")
    expect(AutoDoc::Tester::E2ERunner).to be_a(Class)
  end
end
