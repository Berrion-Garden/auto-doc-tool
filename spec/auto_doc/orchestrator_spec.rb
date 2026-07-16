# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::Orchestrator do
  subject(:orchestrator) { described_class.new(options) }

  let(:options) { {} }
  let(:target_dir) { "/tmp/test_project_#{Process.pid}" }
  let(:pipeline_result) do
    {
      project: "test_project",
      output_dir: target_dir,
      module_roots: [File.join(target_dir, "app"), File.join(target_dir, "lib")],
      analyses_count: 0,
      classes_count: 0,
      methods_count: 0,
      coverage_pct: 0,
      generated_at: Time.now,
      schema_tables: [],
      models: []
    }
  end

  before do
    FileUtils.mkdir_p(target_dir)
    FileUtils.mkdir_p(File.join(target_dir, "app"))
    FileUtils.mkdir_p(File.join(target_dir, "lib"))

    config = instance_double(AutoDoc::Config,
      exclude_patterns: [],
      module_roots: %w[app lib],
      llm_primary?: true,
      output_dir: ".docs"
    )
    allow(AutoDoc::Config).to receive(:load).and_return(config)

    # Stub analysis cache
    allow(AutoDoc::Analyzer::AnalysisCache).to receive(:fetch).and_return({})

    # Stub pipeline
    pipeline = instance_double(AutoDoc::Orchestrator::Pipeline)
    allow(pipeline).to receive(:run).and_return(pipeline_result)
    allow(AutoDoc::Orchestrator::Pipeline).to receive(:new).and_return(pipeline)
  end

  after do
    FileUtils.remove_entry(target_dir) if Dir.exist?(target_dir)
  end

  describe "#generate" do
    context "when LLM is primary" do
      it "calls Enricher.enrich_analyses with base_dir" do
        expect(AutoDoc::LLM::Enricher).to receive(:enrich_analyses).with(
          kind_of(Hash),
          anything,
          hash_including(base_dir: target_dir)
        ).and_return({})

        orchestrator.generate(target_dir)
      end
    end

    context "when LLM is not primary" do
      before do
        config = instance_double(AutoDoc::Config,
          exclude_patterns: [],
          module_roots: %w[app lib],
          llm_primary?: false,
          output_dir: ".docs"
        )
        allow(AutoDoc::Config).to receive(:load).and_return(config)
      end

      it "still calls Enricher.enrich_analyses (orchestrator always delegates)" do
        expect(AutoDoc::LLM::Enricher).to receive(:enrich_analyses).and_return({})

        orchestrator.generate(target_dir)
      end
    end
  end
end
