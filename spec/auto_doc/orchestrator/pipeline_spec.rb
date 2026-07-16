# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::Orchestrator::Pipeline do
  subject(:pipeline) { described_class.new(config) }

  let(:config) { instance_double(AutoDoc::Config, exclude_patterns: []) }
  let(:say_spy) { double("say") }
  let(:analyses) do
    {
      "/project/app/models/user.rb" => {
        definitions: [
          { name: "User", type: :class, has_doc?: true, methods: [{ name: "find" }] }
        ],
        imports: []
      }
    }
  end

  before do
    allow(say_spy).to receive(:call)

    # Stub out all steps to avoid triggering actual generators
    allow_any_instance_of(AutoDoc::Orchestrator::AgentsMdStep).to receive(:run)
    allow_any_instance_of(AutoDoc::Orchestrator::ReadmeStep).to receive(:run)
    allow_any_instance_of(AutoDoc::Orchestrator::IndexSummaryVectorsStep).to receive(:run)
    allow_any_instance_of(AutoDoc::Orchestrator::DiagramStep).to receive(:run)
    allow_any_instance_of(AutoDoc::Orchestrator::ArchitectureStep).to receive(:run)
    allow_any_instance_of(AutoDoc::Orchestrator::ManifestStep).to receive(:run)
  end

  describe "#run" do
    it "executes all steps" do
      # expect_any_instance_of does not support .ordered in RSpec 3,
      # so we verify each step's run is called at all
      expect_any_instance_of(AutoDoc::Orchestrator::AgentsMdStep).to receive(:run).with(hash_including(:analyses))
      expect_any_instance_of(AutoDoc::Orchestrator::ReadmeStep).to receive(:run).with(hash_including(:analyses))
      expect_any_instance_of(AutoDoc::Orchestrator::IndexSummaryVectorsStep).to receive(:run).with(hash_including(:analyses))
      expect_any_instance_of(AutoDoc::Orchestrator::DiagramStep).to receive(:run).with(hash_including(:analyses))
      expect_any_instance_of(AutoDoc::Orchestrator::ArchitectureStep).to receive(:run).with(hash_including(:analyses))
      expect_any_instance_of(AutoDoc::Orchestrator::ManifestStep).to receive(:run).with(hash_including(:analyses))

      pipeline.run(analyses,
        target_dir: "/project",
        output_dir: "/project/.docs",
        module_roots: ["/project/app"],
        say: say_spy)
    end

    it "returns summary hash with expected keys" do
      result = pipeline.run(analyses,
        target_dir: "/project",
        output_dir: "/project/.docs",
        module_roots: ["/project/app"],
        say: say_spy)

      expected_keys = %i[project output_dir module_roots analyses_count classes_count methods_count coverage_pct generated_at schema_tables models]
      expected_keys.each do |key|
        expect(result).to have_key(key)
      end
    end

    it "returns project name in result" do
      result = pipeline.run(analyses,
        target_dir: "/project",
        output_dir: "/project/.docs",
        module_roots: ["/project/app"],
        say: say_spy)

      expect(result[:project]).to eq("project")
    end

    it "includes coverage percentage in result" do
      result = pipeline.run(analyses,
        target_dir: "/project",
        output_dir: "/project/.docs",
        module_roots: ["/project/app"],
        say: say_spy)

      expect(result[:coverage_pct]).to be_a(Numeric)
    end

    it "includes classes and methods count" do
      result = pipeline.run(analyses,
        target_dir: "/project",
        output_dir: "/project/.docs",
        module_roots: ["/project/app"],
        say: say_spy)

      expect(result[:classes_count]).to eq(1)
      expect(result[:methods_count]).to eq(1)
    end

    it "falls back to counting when context classes are 0" do
      # When all_classes is 0 in context, pipeline falls back to count_classes_and_methods
      result = pipeline.run(analyses,
        target_dir: "/project",
        output_dir: "/project/.docs",
        module_roots: ["/project/app"],
        say: say_spy)

      # Should still count correctly
      expect(result[:classes_count]).to be > 0
    end

    it "passes config to each step via context" do
      expect_any_instance_of(AutoDoc::Orchestrator::AgentsMdStep).to receive(:run) do |_step, ctx|
        expect(ctx[:config]).to eq(config)
      end

      pipeline.run(analyses,
        target_dir: "/project",
        output_dir: "/project/.docs",
        module_roots: ["/project/app"],
        say: say_spy)
    end

    context "with LLM config" do
      let(:tmpdir) { Dir.mktmpdir }
      let(:llm_config) do
        AutoDoc::Config.load(tmpdir, llm: { endpoint: "https://test", api_key: "test", model: "gpt-4o" })
      end
      let(:pipeline) { described_class.new(llm_config) }
      after { FileUtils.remove_entry(tmpdir) }

      it "passes llm_config to each step" do
        expect_any_instance_of(AutoDoc::Orchestrator::AgentsMdStep).to receive(:run) do |_step, ctx|
          cfg = ctx[:config]
          expect(cfg.llm_config[:endpoint]).to eq("https://test")
        end

        pipeline.run(analyses,
          target_dir: "/project",
          output_dir: "/project/.docs",
          module_roots: ["/project/app"],
          say: say_spy)
      end
    end
  end
end
