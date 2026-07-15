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
end
