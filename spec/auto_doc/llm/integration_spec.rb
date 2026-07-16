# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "net/http"
require "json"

RSpec.describe "LLM Integration: Client → Summarizer → Generator Output" do
  # This spec verifies the full LLM chain end-to-end with mocked HTTP:
  #   Config → Client#chat → Summarizer → Generator (SummaryGenerator / AgentsMdGenerator)
  #
  # It ensures the consumer generators (SummaryGenerator, AgentsMdGenerator)
  # correctly wire through the LLM layer when AUTO_DOC_DISABLE_LLM is unset
  # and a configured LLM client is available.

  # Per-example env var management — each test starts with env var unset
  # so LLM code paths are exercised. Tests that set the var are responsible
  # for restoring it in their own after blocks.
  before do
    @saved_disable_llm = ENV.delete("AUTO_DOC_DISABLE_LLM")
  end

  after do
    if @saved_disable_llm
      ENV["AUTO_DOC_DISABLE_LLM"] = @saved_disable_llm
    else
      ENV.delete("AUTO_DOC_DISABLE_LLM")
    end
  end

  let(:project_dir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(project_dir) }

  # Config with LLM settings — makes Client.configured? return true
  let(:config) do
    File.write(File.join(project_dir, ".autodoc.yml"), <<~YAML)
      llm:
        provider: openai
        endpoint: https://llm.test/v1
        api_key: test-key
        model: test-model
    YAML
    AutoDoc::Config.load(project_dir)
  end

  # Config without LLM settings — makes Client.configured? return false
  let(:no_llm_config) { AutoDoc::Config.load(Dir.mktmpdir) }

  let(:http) { double("Net::HTTP") }
  let(:response) { double("Net::HTTPResponse") }

  before do
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:use_ssl=)
  end

  # ---------------------------------------------------------------------------
  # Client → chat integration
  # ---------------------------------------------------------------------------
  describe "AutoDoc::LLM::Client via Config" do
    it "builds a client from Config#llm_config and returns chat responses" do
      allow(http).to receive(:request).and_return(response)
      allow(response).to receive(:value).and_return(nil)
      allow(response).to receive(:body).and_return(
        '{"choices":[{"message":{"content":"Hello from LLM!"}}]}'
      )

      client = AutoDoc::LLM::Client.from_config(config)
      expect(client.configured?).to be true
      result = client.chat([{ role: "user", content: "Hi" }])
      expect(result).to eq("Hello from LLM!")
    end

    it "returns nil when config has no LLM settings" do
      client = AutoDoc::LLM::Client.from_config(no_llm_config)
      expect(client.configured?).to be false
      result = client.chat([{ role: "user", content: "Hi" }])
      expect(result).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Summarizer → Client integration
  # ---------------------------------------------------------------------------
  describe "AutoDoc::LLM::Summarizer via Client" do
    let(:analyses) do
      {
        "/project/app/controllers/users_controller.rb" => {
          definitions: [
            { name: "UsersController", type: "class", has_doc?: true },
            { name: "index", type: "method", has_doc?: true },
            { name: "create", type: "method", has_doc?: false }
          ],
          docs: []
        },
        "/project/app/models/user.rb" => {
          definitions: [
            { name: "User", type: "class", has_doc?: true }
          ],
          docs: []
        }
      }
    end

    let(:client) { AutoDoc::LLM::Client.from_config(config) }

    before do
      allow(http).to receive(:request).and_return(response)
      allow(response).to receive(:value).and_return(nil)
      allow(response).to receive(:body).and_return(
        '{"choices":[{"message":{"content":"LLM module summary output."}}]}'
      )
    end

    it "summarize_module returns client response text" do
      result = AutoDoc::LLM::Summarizer.summarize_module("app", analyses, client)
      expect(result).to eq("LLM module summary output.")
    end

    it "summarize_architecture returns client response text" do
      result = AutoDoc::LLM::Summarizer.summarize_architecture("MyApp", analyses, client)
      expect(result).to eq("LLM module summary output.")
    end

    it "summarize_components returns client response text" do
      result = AutoDoc::LLM::Summarizer.summarize_components(analyses, client)
      expect(result).to eq("LLM module summary output.")
    end

    it "returns nil when client is not configured" do
      unconfigured_client = AutoDoc::LLM::Client.from_config(no_llm_config)
      result = AutoDoc::LLM::Summarizer.summarize_module("app", analyses, unconfigured_client)
      expect(result).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # SummaryGenerator → Summarizer → Client integration
  # ---------------------------------------------------------------------------
  describe "SummaryGenerator with LLM" do
    let(:dir_name) { "lib" }
    let(:analyses) do
      {
        "/project/lib/foo.rb" => {
          definitions: [{ name: "Foo", type: :class, line: 1, has_doc?: true }],
          imports: [{ path: "json", type: :require }],
          docs: []
        }
      }
    end

    it "uses LLM content in purpose, architecture, and components when configured" do
      # SummaryGenerator calls chat 3 times: purpose, architecture, components
      allow(http).to receive(:request).and_return(response).exactly(3).times
      allow(response).to receive(:value).and_return(nil).exactly(3).times
      allow(response).to receive(:body).and_return(
        '{"choices":[{"message":{"content":"LLM-powered purpose for lib"}}]}',
        '{"choices":[{"message":{"content":"LLM-powered architecture"}}]}',
        '{"choices":[{"message":{"content":"- Foo (class): Main component"}}]}'
      )

      result = AutoDoc::Generator::SummaryGenerator.generate(dir_name, analyses, config)
      expect(result).to include("LLM-powered purpose for lib")
      expect(result).to include("LLM-powered architecture")
    end

    it "falls back to static inference when no LLM config" do
      result = AutoDoc::Generator::SummaryGenerator.generate(dir_name, analyses, no_llm_config)
      expect(result).to include("Core library code")
      expect(result).to include("Modular library")
    end

    it "falls back to static inference when LLM call fails" do
      allow(http).to receive(:request).and_raise(SocketError, "network unreachable")

      result = AutoDoc::Generator::SummaryGenerator.generate(dir_name, analyses, config)
      expect(result).to include("Core library code")
      expect(result).to include("Modular library")
    end

    it "respects AUTO_DOC_DISABLE_LLM env var" do
      ENV["AUTO_DOC_DISABLE_LLM"] = "true"
      expect(Net::HTTP).not_to receive(:new)

      result = AutoDoc::Generator::SummaryGenerator.generate(dir_name, analyses, config)
      expect(result).to include("Core library code")
      expect(result).to include("Modular library")
    end
  end

  # ---------------------------------------------------------------------------
  # AgentsMdGenerator → Summarizer → Client integration
  # ---------------------------------------------------------------------------
  describe "AgentsMdGenerator with LLM" do
    let(:module_name) { "lib" }
    let(:tree_text) { "lib/\n  foo.rb\n" }
    let(:files) do
      [
        { name: "foo.rb", path: "/project/lib/foo.rb",
          classes: [{ name: "Foo", type: "class", has_doc?: true, line: 1 }],
          imports: [] }
      ]
    end

    it "uses LLM for purpose summary when configured" do
      allow(http).to receive(:request).and_return(response)
      allow(response).to receive(:value).and_return(nil)
      allow(response).to receive(:body).and_return(
        '{"choices":[{"message":{"content":"The lib module contains core classes."}}]}'
      )

      result = AutoDoc::Generator::AgentsMdGenerator.generate(
        module_name, tree_text, files, config: config
      )
      expect(result).to include("The lib module contains core classes.")
    end

    it "falls back gracefully when LLM returns nil" do
      allow(http).to receive(:request).and_return(response)
      allow(response).to receive(:value).and_return(nil)
      allow(response).to receive(:body).and_return('{"choices":[{"message":{"content":null}}]}')

      result = AutoDoc::Generator::AgentsMdGenerator.generate(
        module_name, tree_text, files, config: config
      )
      expect(result).to include("developer to fill in")
    end

    it "falls back gracefully when LLM call raises" do
      allow(http).to receive(:request).and_raise(Errno::ECONNREFUSED)

      result = AutoDoc::Generator::AgentsMdGenerator.generate(
        module_name, tree_text, files, config: config
      )
      expect(result).to include("developer to fill in")
    end

    it "respects AUTO_DOC_DISABLE_LLM env var" do
      ENV["AUTO_DOC_DISABLE_LLM"] = "true"
      expect(Net::HTTP).not_to receive(:new)

      result = AutoDoc::Generator::AgentsMdGenerator.generate(
        module_name, tree_text, files, config: config
      )
      expect(result).to include("developer to fill in")
    end

    it "works without any config (backward compat)" do
      result = AutoDoc::Generator::AgentsMdGenerator.generate(
        module_name, tree_text, files
      )
      expect(result).to include("# lib")
      expect(result).to include("developer to fill in")
    end
  end
end
