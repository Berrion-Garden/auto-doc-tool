# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"

RSpec.describe AutoDoc::Orchestrator::DiagramStep do
  subject(:step) { described_class.new }

  let(:target_dir) { Dir.mktmpdir }
  let(:output_dir) { ".docs" }
  let(:diagrams_dir) { File.join(target_dir, output_dir, "diagrams") }

  let(:module_roots) { ["#{target_dir}/lib", "#{target_dir}/app"] }
  let(:analyses) do
    {
      "#{target_dir}/lib/foo.rb" => {
        definitions: [{ name: "Foo", type: :class, has_doc?: true, methods: [{ name: "bar" }] }],
        imports: []
      },
      "#{target_dir}/app/bar.rb" => {
        definitions: [{ name: "Bar", type: :class, has_doc?: true, methods: [{ name: "baz" }] }],
        imports: []
      }
    }
  end

  # Default context: LLM disabled (as spec_helper sets AUTO_DOC_DISABLE_LLM=true)
  let(:config) do
    instance_double(AutoDoc::Config,
      llm_config: { endpoint: "https://test", api_key: "test-key", model: "test-model" },
      generate_dag?: false)
  end

  let(:say_spy) { double("say") }

  let(:context) do
    {
      target_dir: target_dir,
      output_dir: output_dir,
      config: config,
      module_roots: module_roots,
      analyses: analyses,
      say: say_spy
    }
  end

  before do
    allow(say_spy).to receive(:call)
    # Non-Rails project by default (no db/schema.rb)
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(File.join(target_dir, "db/schema.rb")).and_return(false)

    # Create the source files
    FileUtils.mkdir_p("#{target_dir}/lib")
    FileUtils.mkdir_p("#{target_dir}/app")
    File.write("#{target_dir}/lib/foo.rb", "class Foo; end")
    File.write("#{target_dir}/app/bar.rb", "class Bar; end")
  end

  after do
    FileUtils.remove_entry(target_dir)
  end

  describe "#run" do
    it "returns the context hash" do
      result = step.run(context)
      expect(result).to eq(context)
    end

    it "generates C4 context diagram with hardcoded external systems when LLM disabled" do
      step.run(context)

      c4_content = File.read(File.join(diagrams_dir, "c4_context.mmd"))
      expect(c4_content).to include("Developer")
      expect(c4_content).to include("File System")
      expect(c4_content).to include("Git")
      expect(c4_content).to include("Writes code and runs documentation commands")
      expect(c4_content).to include("Reads/writes documentation files")
    end

    it "generates C4 container diagram with hardcoded module descriptions when LLM disabled" do
      step.run(context)

      c4_content = File.read(File.join(diagrams_dir, "c4_container.mmd"))
      expect(c4_content).to include("lib module")
      expect(c4_content).to include("app module")
    end

    it "generates class diagram" do
      step.run(context)

      expect(File).to exist(File.join(diagrams_dir, "class_diagram.mmd"))
    end

    it "generates both C4 diagrams" do
      step.run(context)

      expect(File).to exist(File.join(diagrams_dir, "c4_context.mmd"))
      expect(File).to exist(File.join(diagrams_dir, "c4_container.mmd"))
    end

    it "stores container_data_flows in context" do
      result = step.run(context)

      expect(result[:container_data_flows]).to be_an(Array)
    end

    context "when config has no llm_config (client not configured)" do
      let(:config) do
        instance_double(AutoDoc::Config,
          llm_config: nil,
          generate_dag?: false)
      end

      it "falls back to hardcoded external systems" do
        step.run(context)

        c4_content = File.read(File.join(diagrams_dir, "c4_context.mmd"))
        expect(c4_content).to include("Developer")
        expect(c4_content).to include("File System")
        expect(c4_content).to include("Git")
      end

      it "falls back to hardcoded module descriptions" do
        step.run(context)

        c4_content = File.read(File.join(diagrams_dir, "c4_container.mmd"))
        expect(c4_content).to include("lib module")
        expect(c4_content).to include("app module")
      end
    end

    context "with AUTO_DOC_DISABLE_LLM set" do
      it "skips LLM and uses hardcoded values" do
        ENV["AUTO_DOC_DISABLE_LLM"] = "true"

        step.run(context)

        c4_content = File.read(File.join(diagrams_dir, "c4_context.mmd"))
        expect(c4_content).to include("Developer")
        expect(c4_content).to include("File System")
        expect(c4_content).to include("Git")
      end
    end

    context "when LLM is configured and returns valid data" do
      let(:http) { double("Net::HTTP") }
      let(:response) { double("Net::HTTPResponse") }

      before do
        # Enable LLM for this context group
        @original_disable = ENV.delete("AUTO_DOC_DISABLE_LLM")

        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:use_ssl=)
      end

      after do
        if @original_disable
          ENV["AUTO_DOC_DISABLE_LLM"] = @original_disable
        else
          ENV.delete("AUTO_DOC_DISABLE_LLM")
        end
      end

      it "uses LLM-generated external systems for context diagram" do
        # First call: system_context
        # Second call: containers
        allow(http).to receive(:request).and_return(response)
        allow(response).to receive(:value).and_return(nil)
        allow(response).to receive(:body).and_return(
          # OpenAI API response wrapper containing the system context content
          '{"choices":[{"message":{"content":"[{\\"name\\": \\"Database\\", \\"interaction\\": \\"Stores documentation data\\"}, {\\"name\\": \\"CI Pipeline\\", \\"interaction\\": \\"Triggers doc generation on push\\"}]"}}]}',
          # OpenAI API response wrapper containing the containers content
          '{"choices":[{"message":{"content":"## Module Root: lib\\n\\nThe lib module contains Foo class.\\n\\n## Module Root: app\\n\\nThe app module contains Bar class."}}]}'
        )

        step.run(context)

        c4_content = File.read(File.join(diagrams_dir, "c4_context.mmd"))
        expect(c4_content).to include("Database")
        expect(c4_content).to include("CI Pipeline")
        expect(c4_content).not_to include("Developer")
        expect(c4_content).not_to include("File System")
        expect(c4_content).not_to include("Git")
      end

      it "uses LLM-generated module descriptions for container diagram" do
        allow(http).to receive(:request).and_return(response)
        allow(response).to receive(:value).and_return(nil)
        allow(response).to receive(:body).and_return(
          # First call: system_context
          '{"choices":[{"message":{"content":"[{\\"name\\": \\"Database\\", \\"interaction\\": \\"Stores data\\"}]"}}]}',
          # Second call: containers
          '{"choices":[{"message":{"content":"## Module Root: lib\\n\\nThe lib module contains Foo class.\\n\\n## Module Root: app\\n\\nThe app module contains Bar class."}}]}'
        )

        step.run(context)

        c4_content = File.read(File.join(diagrams_dir, "c4_container.mmd"))
        expect(c4_content).to include("The lib module contains Foo class")
        expect(c4_content).to include("The app module contains Bar class")
        # The fallback description "lib module" (standalone) should not be the full description
        # LLM content includes "The lib module contains..." which contains the words
        # but the fallback pattern "<br/>lib module]" (end anchor) should not appear
        expect(c4_content).not_to include("lib module]")
      end
    end

    context "when LLM returns nil (API failure)" do
      let(:http) { double("Net::HTTP") }

      before do
        @original_disable = ENV.delete("AUTO_DOC_DISABLE_LLM")

        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:use_ssl=)
      end

      after do
        if @original_disable
          ENV["AUTO_DOC_DISABLE_LLM"] = @original_disable
        else
          ENV.delete("AUTO_DOC_DISABLE_LLM")
        end
      end

      it "falls back to hardcoded external systems when LLM call fails" do
        allow(http).to receive(:request).and_raise(SocketError, "connection refused")

        step.run(context)

        c4_content = File.read(File.join(diagrams_dir, "c4_context.mmd"))
        expect(c4_content).to include("Developer")
        expect(c4_content).to include("File System")
        expect(c4_content).to include("Git")
      end

      it "falls back to hardcoded module descriptions when LLM call fails" do
        allow(http).to receive(:request).and_raise(SocketError, "connection refused")

        step.run(context)

        c4_content = File.read(File.join(diagrams_dir, "c4_container.mmd"))
        expect(c4_content).to include("lib module")
        expect(c4_content).to include("app module")
      end
    end

    context "with Rails project (db/schema.rb exists)" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(File.join(target_dir, "db/schema.rb")).and_return(true)
      end

      it "generates C4 diagrams even with schema tables available" do
        # Return empty tables so ERD generation is skipped (no ERD to fail on)
        allow(AutoDoc::Analyzer::SchemaParser).to receive(:parse).and_return([])
        allow(AutoDoc::Analyzer::ModelAssociationParser).to receive(:parse).and_return({})

        step.run(context)

        expect(File).to exist(File.join(diagrams_dir, "c4_context.mmd"))
        expect(File).to exist(File.join(diagrams_dir, "c4_container.mmd"))
      end
    end
  end
end
