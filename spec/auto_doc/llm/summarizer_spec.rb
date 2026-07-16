# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::LLM::Summarizer do
  subject(:summarizer) { described_class }

  let(:client) { instance_double(AutoDoc::LLM::Client) }

  let(:sample_analyses) do
    {
      "/app/lib/controllers/users_controller.rb" => {
        definitions: [
          { name: "UsersController", type: "class", has_doc?: true },
          { name: "index", type: "method", has_doc?: true },
          { name: "create", type: "method", has_doc?: false }
        ],
        docs: []
      },
      "/app/lib/models/user.rb" => {
        definitions: [
          { name: "User", type: "class", has_doc?: true },
          { name: "validates", type: "method", has_doc?: false }
        ],
        docs: []
      },
      "/app/lib/services/user_service.rb" => {
        definitions: [
          { name: "UserService", type: "module", has_doc?: true },
          { name: "find_by_email", type: "method", has_doc?: true }
        ],
        docs: []
      }
    }
  end

  describe ".summarize_module" do
    context "when client succeeds" do
      before do
        allow(client).to receive(:chat).and_return("The User module handles user authentication and profile management.")
      end

      it "returns a summary string" do
        result = summarizer.summarize_module("models", sample_analyses, client)
        expect(result).to be_a(String)
        expect(result).to eq("The User module handles user authentication and profile management.")
      end

      it "builds a prompt containing file names and class names" do
        expected_prompt = nil
        allow(client).to receive(:chat) do |messages|
          expected_prompt = messages.first[:content]
          "summary"
        end

        summarizer.summarize_module("models", sample_analyses, client)

        expect(expected_prompt).to include("models")
        expect(expected_prompt).to include("user.rb")
      end

      it "builds a prompt that does NOT contain source code patterns" do
        allow(client).to receive(:chat) do |messages|
          expect(messages.first[:content]).not_to include("def ")
          expect(messages.first[:content]).not_to include("class ")
          "summary"
        end

        summarizer.summarize_module("models", sample_analyses, client)
      end

      it "builds a prompt that does NOT contain Ruby-specific language" do
        allow(client).to receive(:chat) do |messages|
          expect(messages.first[:content]).not_to include("Ruby")
          "summary"
        end

        summarizer.summarize_module("models", sample_analyses, client)
      end
    end

    context "when client returns nil" do
      before do
        allow(client).to receive(:chat).and_return(nil)
      end

      it "returns nil" do
        result = summarizer.summarize_module("models", sample_analyses, client)
        expect(result).to be_nil
      end
    end
  end

  describe ".summarize_architecture" do
    context "when client succeeds" do
      before do
        allow(client).to receive(:chat).and_return("The project follows MVC architecture.")
      end

      it "returns a summary string" do
        result = summarizer.summarize_architecture("MyApp", sample_analyses, client)
        expect(result).to be_a(String)
        expect(result).to eq("The project follows MVC architecture.")
      end

      it "builds a prompt containing the project name and metadata" do
        expected_prompt = nil
        allow(client).to receive(:chat) do |messages|
          expected_prompt = messages.first[:content]
          "summary"
        end

        summarizer.summarize_architecture("MyApp", sample_analyses, client)

        expect(expected_prompt).to include("MyApp")
        expect(expected_prompt).to include("UsersController")
        expect(expected_prompt).to include("UserService")
      end

      it "builds a prompt that does NOT contain source code patterns" do
        allow(client).to receive(:chat) do |messages|
          expect(messages.first[:content]).not_to include("def ")
          expect(messages.first[:content]).not_to include("class ")
          "summary"
        end

        summarizer.summarize_architecture("MyApp", sample_analyses, client)
      end

      it "builds a prompt that does NOT contain Ruby-specific language" do
        allow(client).to receive(:chat) do |messages|
          expect(messages.first[:content]).not_to include("Ruby")
          "summary"
        end

        summarizer.summarize_architecture("MyApp", sample_analyses, client)
      end
    end

    context "when client returns nil" do
      before do
        allow(client).to receive(:chat).and_return(nil)
      end

      it "returns nil" do
        result = summarizer.summarize_architecture("MyApp", sample_analyses, client)
        expect(result).to be_nil
      end
    end
  end

  describe ".summarize_components" do
    context "when client succeeds" do
      before do
        allow(client).to receive(:chat).and_return("Controllers depend on services.")
      end

      it "returns a summary string" do
        result = summarizer.summarize_components(sample_analyses, client)
        expect(result).to be_a(String)
        expect(result).to eq("Controllers depend on services.")
      end

      it "builds a prompt containing component metadata" do
        expected_prompt = nil
        allow(client).to receive(:chat) do |messages|
          expected_prompt = messages.first[:content]
          "summary"
        end

        summarizer.summarize_components(sample_analyses, client)

        expect(expected_prompt).to include("UsersController")
        expect(expected_prompt).to include("User")
        expect(expected_prompt).to include("UserService")
      end

      it "builds a prompt that does NOT contain source code patterns" do
        allow(client).to receive(:chat) do |messages|
          expect(messages.first[:content]).not_to include("def ")
          expect(messages.first[:content]).not_to include("class ")
          "summary"
        end

        summarizer.summarize_components(sample_analyses, client)
      end

      it "builds a prompt that does NOT contain Ruby-specific language" do
        allow(client).to receive(:chat) do |messages|
          expect(messages.first[:content]).not_to include("Ruby")
          "summary"
        end

        summarizer.summarize_components(sample_analyses, client)
      end
    end

    context "when client returns nil" do
      before do
        allow(client).to receive(:chat).and_return(nil)
      end

      it "returns nil" do
        result = summarizer.summarize_components(sample_analyses, client)
        expect(result).to be_nil
      end
    end
  end

  describe ".summarize_architecture_full" do
    context "when client succeeds with structured markdown" do
      let(:llm_response) do
        <<~MARKDOWN
          ## Purpose
          This project manages widgets and gadgets.

          ## Architectural Style
          The project follows a modular architecture with clear separation of concerns.

          ## Main Modules
          - Controllers: Handle HTTP requests
          - Models: Business logic and data persistence
          - Services: Orchestrate complex operations

          ## Data Flow
          HTTP request flows through controllers to services to models.
        MARKDOWN
      end

      before do
        allow(client).to receive(:chat).and_return(llm_response)
      end

      it "returns a hash with :purpose, :style, :modules, :data_flow keys" do
        result = summarizer.summarize_architecture_full("MyApp", sample_analyses, client)
        expect(result).to be_a(Hash)
        expect(result.keys).to contain_exactly(:purpose, :style, :modules, :data_flow)
      end

      it "extracts the purpose section content" do
        result = summarizer.summarize_architecture_full("MyApp", sample_analyses, client)
        expect(result[:purpose]).to include("widgets and gadgets")
      end

      it "extracts the style section content" do
        result = summarizer.summarize_architecture_full("MyApp", sample_analyses, client)
        expect(result[:style]).to include("modular architecture")
      end

      it "extracts the modules section content" do
        result = summarizer.summarize_architecture_full("MyApp", sample_analyses, client)
        expect(result[:modules]).to include("Controllers")
        expect(result[:modules]).to include("Services")
      end

      it "extracts the data flow section content" do
        result = summarizer.summarize_architecture_full("MyApp", sample_analyses, client)
        expect(result[:data_flow]).to include("HTTP request")
      end

      it "builds a prompt containing the project name and metadata" do
        expected_prompt = nil
        allow(client).to receive(:chat) do |messages|
          expected_prompt = messages.first[:content]
          llm_response
        end

        summarizer.summarize_architecture_full("MyApp", sample_analyses, client)

        expect(expected_prompt).to include("MyApp")
        expect(expected_prompt).to include("UsersController")
        expect(expected_prompt).to include("UserService")
      end

      it "builds a prompt that does NOT contain source code patterns" do
        allow(client).to receive(:chat) do |messages|
          expect(messages.first[:content]).not_to include("def ")
          expect(messages.first[:content]).not_to include("class ")
          llm_response
        end

        summarizer.summarize_architecture_full("MyApp", sample_analyses, client)
      end

      it "builds a prompt mentioning markdown sections" do
        allow(client).to receive(:chat) do |messages|
          expect(messages.first[:content]).to include("markdown")
          llm_response
        end

        summarizer.summarize_architecture_full("MyApp", sample_analyses, client)
      end
    end

    context "when response has no markdown headings" do
      it "puts the entire response into :purpose" do
        allow(client).to receive(:chat).and_return("A simple plain text description of the project architecture.")
        result = summarizer.summarize_architecture_full("MyApp", sample_analyses, client)
        expect(result).to be_a(Hash)
        expect(result[:purpose]).to eq("A simple plain text description of the project architecture.")
      end
    end

    context "when client returns nil" do
      before do
        allow(client).to receive(:chat).and_return(nil)
      end

      it "returns nil" do
        result = summarizer.summarize_architecture_full("MyApp", sample_analyses, client)
        expect(result).to be_nil
      end
    end
  end

  describe ".summarize_system_context" do
    context "when client returns JSON array" do
      let(:llm_response) do
        '[{"name": "PostgreSQL", "interaction": "Primary data store for user accounts and content"}, {"name": "Redis", "interaction": "Caching layer for session data and rate limiting"}]'
      end

      before do
        allow(client).to receive(:chat).and_return(llm_response)
      end

      it "returns an array of hashes with :name and :interaction keys" do
        result = summarizer.summarize_system_context("MyApp", sample_analyses, client)
        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
        expect(result.first).to have_key(:name)
        expect(result.first).to have_key(:interaction)
      end

      it "extracts the name field" do
        result = summarizer.summarize_system_context("MyApp", sample_analyses, client)
        expect(result.first[:name]).to eq("PostgreSQL")
      end

      it "extracts the interaction field" do
        result = summarizer.summarize_system_context("MyApp", sample_analyses, client)
        expect(result.first[:interaction]).to include("data store")
      end

      it "builds a prompt containing the project name" do
        expected_prompt = nil
        allow(client).to receive(:chat) do |messages|
          expected_prompt = messages.first[:content]
          llm_response
        end

        summarizer.summarize_system_context("MyApp", sample_analyses, client)

        expect(expected_prompt).to include("MyApp")
      end

      it "builds a prompt mentioning external systems" do
        allow(client).to receive(:chat) do |messages|
          expect(messages.first[:content]).to include("external systems")
          llm_response
        end

        summarizer.summarize_system_context("MyApp", sample_analyses, client)
      end

      it "builds a prompt mentioning JSON format" do
        allow(client).to receive(:chat) do |messages|
          expect(messages.first[:content]).to include("JSON")
          llm_response
        end

        summarizer.summarize_system_context("MyApp", sample_analyses, client)
      end
    end

    context "when client returns markdown bullet list" do
      it "parses markdown bullet format into name/interaction hashes" do
        md_response = <<~MARKDOWN
          - PostgreSQL: Primary data store for user accounts
          - Redis: Caching layer for session data
        MARKDOWN
        allow(client).to receive(:chat).and_return(md_response)
        result = summarizer.summarize_system_context("MyApp", sample_analyses, client)
        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
        expect(result.first[:name]).to eq("PostgreSQL")
        expect(result.last[:name]).to eq("Redis")
      end

      it "parses asterisk bullet format" do
        md_response = "* PostgreSQL: Primary data store"
        allow(client).to receive(:chat).and_return(md_response)
        result = summarizer.summarize_system_context("MyApp", sample_analyses, client)
        expect(result).to be_an(Array)
        expect(result.first[:name]).to eq("PostgreSQL")
      end
    end

    context "when response is unparseable" do
      it "returns nil for garbage response" do
        allow(client).to receive(:chat).and_return("Just some random text without structure")
        result = summarizer.summarize_system_context("MyApp", sample_analyses, client)
        expect(result).to be_nil
      end
    end

    context "when client returns nil" do
      before do
        allow(client).to receive(:chat).and_return(nil)
      end

      it "returns nil" do
        result = summarizer.summarize_system_context("MyApp", sample_analyses, client)
        expect(result).to be_nil
      end
    end
  end

  describe ".summarize_containers" do
    let(:module_roots) { ["lib"] }

    context "when client returns structured markdown" do
      let(:llm_response) do
        <<~MARKDOWN
          ## Module Root: lib
          The lib directory contains the core application logic. It is organized into controllers, models, and services.

          ## Module Root: config
          Configuration files for the application including database and routing setup.
        MARKDOWN
      end

      before do
        allow(client).to receive(:chat).and_return(llm_response)
      end

      it "returns a hash with module root names as keys" do
        result = summarizer.summarize_containers(sample_analyses, module_roots, client)
        expect(result).to be_a(Hash)
        expect(result.keys).to contain_exactly("lib", "config")
      end

      it "extracts description content for each module root" do
        result = summarizer.summarize_containers(sample_analyses, module_roots, client)
        expect(result["lib"]).to include("core application logic")
        expect(result["config"]).to include("Configuration files")
      end

      it "builds a prompt containing module root names" do
        expected_prompt = nil
        allow(client).to receive(:chat) do |messages|
          expected_prompt = messages.first[:content]
          llm_response
        end

        summarizer.summarize_containers(sample_analyses, module_roots, client)

        expect(expected_prompt).to include("lib")
      end

      it "filters analyses to only include files within module roots" do
        allow(client).to receive(:chat) do |messages|
          prompt = messages.first[:content]
          expect(prompt).to include("users_controller.rb")
          expect(prompt).to include("user.rb")
          expect(prompt).to include("user_service.rb")
          llm_response
        end

        summarizer.summarize_containers(sample_analyses, module_roots, client)
      end
    end

    context "when response is unparseable" do
      it "returns nil for plain text without section headings" do
        allow(client).to receive(:chat).and_return("The lib module contains the core application logic.")
        result = summarizer.summarize_containers(sample_analyses, module_roots, client)
        expect(result).to be_nil
      end

      it "returns nil for empty response" do
        allow(client).to receive(:chat).and_return("")
        result = summarizer.summarize_containers(sample_analyses, module_roots, client)
        expect(result).to be_nil
      end
    end

    context "when client returns nil" do
      before do
        allow(client).to receive(:chat).and_return(nil)
      end

      it "returns nil" do
        result = summarizer.summarize_containers(sample_analyses, module_roots, client)
        expect(result).to be_nil
      end
    end
  end
end
