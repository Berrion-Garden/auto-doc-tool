# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe AutoDoc::Orchestrator::AgentsMdStep do
  subject(:step) { described_class.new }

  let(:project_dir) { Dir.mktmpdir }
  let(:target_dir) { project_dir }
  let(:output_dir) { ".docs" }
  let(:config) { AutoDoc::Config.load(project_dir) }

  let(:context) do
    {
      target_dir: target_dir,
      output_dir: output_dir,
      config: config,
      module_roots: ["#{project_dir}/lib"],
      analyses: {
        "#{project_dir}/lib/foo.rb" => {
          definitions: [{ name: "Foo", type: :class, line: 1, has_doc?: true }],
          imports: [],
          docs: []
        }
      },
      say: ->(_msg, _color) { nil }
    }
  end

  before do
    FileUtils.mkdir_p("#{project_dir}/lib")
    File.write("#{project_dir}/lib/foo.rb", "class Foo; end")
  end

  after { FileUtils.remove_entry(project_dir) }

  describe "#run" do
    it "passes config to AgentsMdGenerator.generate" do
      expected_config = config

      expect(AutoDoc::Generator::AgentsMdGenerator).to receive(:generate) do |dir_name, tree_text, files_data, config:, output_path: nil, llm_summaries: nil|
        expect(dir_name).to eq("lib")
        expect(config).to eq(expected_config)
      end.and_return("rendered content")

      step.run(context)
    end

    it "passes the correct output_path to AgentsMdGenerator.generate" do
      expected_output_path = File.join(target_dir, output_dir, "lib", "AGENTS.md")

      expect(AutoDoc::Generator::AgentsMdGenerator).to receive(:generate) do |dir_name, tree_text, files_data, config: nil, output_path:, llm_summaries: nil|
        expect(output_path).to eq(expected_output_path)
      end.and_return("rendered content")

      step.run(context)
    end

    it "returns the context hash" do
      allow(AutoDoc::Generator::AgentsMdGenerator).to receive(:generate).and_return("rendered content")

      result = step.run(context)
      expect(result).to eq(context)
    end
  end
end
