# frozen_string_literal: true

require "spec_helper"
require "net/http"
require "json"

RSpec.describe AutoDoc::LLM::Client do
  subject(:client) { described_class.new(config_hash) }

  let(:config_hash) do
    {
      endpoint: "https://api.example.com/v1",
      api_key:  "sk-test-key-123",
      model:    "gpt-4o",
      timeout:  30
    }
  end

  let(:http) { double("Net::HTTP") }
  let(:response) { double("Net::HTTPResponse") }

  before do
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:use_ssl=)
  end

  describe "#configured?" do
    it "returns true when both endpoint and api_key are present" do
      expect(client.configured?).to be true
    end

    it "returns false when endpoint is nil" do
      client = described_class.new(config_hash.merge(endpoint: nil))
      expect(client.configured?).to be false
    end

    it "returns false when endpoint is empty" do
      client = described_class.new(config_hash.merge(endpoint: ""))
      expect(client.configured?).to be false
    end

    it "returns false when api_key is nil" do
      client = described_class.new(config_hash.merge(api_key: nil))
      expect(client.configured?).to be false
    end

    it "returns false when api_key is empty" do
      client = described_class.new(config_hash.merge(api_key: ""))
      expect(client.configured?).to be false
    end

    it "returns false when both endpoint and api_key are missing" do
      client = described_class.new({})
      expect(client.configured?).to be false
    end
  end

  describe "#chat" do
    let(:messages) { [{ role: "user", content: "Summarize the project" }] }

    context "on successful 200 response" do
      before do
        allow(http).to receive(:request).and_return(response)
        allow(response).to receive(:value).and_return(nil)
        allow(response).to receive(:body).and_return(
          '{"choices":[{"message":{"content":"This is a summary of the project."}}]}'
        )
      end

      it "returns the response content string" do
        result = client.chat(messages)
        expect(result).to eq("This is a summary of the project.")
      end
    end

    context "on HTTP error" do
      before do
        allow(http).to receive(:request).and_return(response)
        allow(response).to receive(:value).and_raise(
          Net::HTTPClientException.new("401 Unauthorized", response)
        )
      end

      it "returns nil" do
        result = client.chat(messages)
        expect(result).to be_nil
      end
    end

    context "on server error" do
      before do
        allow(http).to receive(:request).and_return(response)
        allow(response).to receive(:value).and_raise(
          Net::HTTPFatalError.new("500 Internal Server Error", response)
        )
      end

      it "returns nil" do
        result = client.chat(messages)
        expect(result).to be_nil
      end
    end

    context "on timeout" do
      before do
        allow(http).to receive(:request).and_raise(Net::OpenTimeout)
      end

      it "returns nil" do
        result = client.chat(messages)
        expect(result).to be_nil
      end
    end

    context "on read timeout" do
      before do
        allow(http).to receive(:request).and_raise(Net::ReadTimeout)
      end

      it "returns nil" do
        result = client.chat(messages)
        expect(result).to be_nil
      end
    end

    context "on JSON parse error" do
      before do
        allow(http).to receive(:request).and_return(response)
        allow(response).to receive(:value).and_return(nil)
        allow(response).to receive(:body).and_return("not valid json")
      end

      it "returns nil" do
        result = client.chat(messages)
        expect(result).to be_nil
      end
    end

    context "on socket error" do
      before do
        allow(http).to receive(:request).and_raise(SocketError)
      end

      it "returns nil" do
        result = client.chat(messages)
        expect(result).to be_nil
      end
    end

    context "on connection refused" do
      before do
        allow(http).to receive(:request).and_raise(Errno::ECONNREFUSED)
      end

      it "returns nil" do
        result = client.chat(messages)
        expect(result).to be_nil
      end
    end
  end

  describe "request body construction" do
    let(:messages) { [{ role: "user", content: "Hello" }] }

    it "includes model and messages in the request body" do
      allow(response).to receive(:value).and_return(nil)
      allow(response).to receive(:body).and_return(
        '{"choices":[{"message":{"content":"Hi"}}]}'
      )

      expect(http).to receive(:request) do |req|
        body = JSON.parse(req.body)
        expect(body).to include("model" => "gpt-4o")
        expect(body["messages"]).to eq([{ "role" => "user", "content" => "Hello" }])
      end.and_return(response)

      client.chat(messages)
    end

    it "merges additional options into the request body" do
      allow(response).to receive(:value).and_return(nil)
      allow(response).to receive(:body).and_return(
        '{"choices":[{"message":{"content":"Hi"}}]}'
      )

      expect(http).to receive(:request) do |req|
        body = JSON.parse(req.body)
        expect(body).to include("temperature" => 0.7, "max_tokens" => 500)
      end.and_return(response)

      client.chat(messages, { temperature: 0.7, max_tokens: 500 })
    end

    it "sets Content-Type and Authorization headers" do
      allow(response).to receive(:value).and_return(nil)
      allow(response).to receive(:body).and_return(
        '{"choices":[{"message":{"content":"Hi"}}]}'
      )

      expect(http).to receive(:request) do |req|
        expect(req["Content-Type"]).to eq("application/json")
        expect(req["Authorization"]).to eq("Bearer sk-test-key-123")
      end.and_return(response)

      client.chat(messages)
    end
  end

  describe ".from_config" do
    it "builds a Client from an object that responds to llm_config" do
      config = double("config", llm_config: config_hash)
      built_client = described_class.from_config(config)
      expect(built_client).to be_a(described_class)
      expect(built_client.configured?).to be true
    end
  end

  describe "timeout configuration" do
    it "uses the default timeout of 30 seconds" do
      client = described_class.new(endpoint: "https://example.com", api_key: "key")
      expect(http).to receive(:open_timeout=).with(30)
      expect(http).to receive(:read_timeout=).with(30)

      allow(http).to receive(:request).and_raise(Net::OpenTimeout)

      client.chat([{ role: "user", content: "test" }])
    end

    it "uses the configured timeout value" do
      client = described_class.new(endpoint: "https://example.com", api_key: "key", timeout: 60)
      expect(http).to receive(:open_timeout=).with(60)
      expect(http).to receive(:read_timeout=).with(60)

      allow(http).to receive(:request).and_raise(Net::OpenTimeout)

      client.chat([{ role: "user", content: "test" }])
    end
  end
end
