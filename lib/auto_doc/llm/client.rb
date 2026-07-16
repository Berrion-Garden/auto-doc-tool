# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module AutoDoc
  module LLM
    # Client for communicating with OpenAI-compatible LLM chat completion endpoints.
    # Uses Net::HTTP from the Ruby stdlib — no external HTTP gem required.
    #
    # Usage:
    #   client = AutoDoc::LLM::Client.new(
    #     endpoint: "https://api.openai.com/v1",
    #     api_key:  ENV["OPENAI_API_KEY"],
    #     model:    "gpt-4o"
    #   )
    #   client.chat([{ role: "user", content: "Hello!" }])
    #   # => "Hi there!"
    class Client
      # @param config_hash [Hash] Configuration with keys :endpoint, :api_key, :model, :timeout
      # @option config_hash [String]  :endpoint API base URL (e.g. "https://api.openai.com/v1")
      # @option config_hash [String]  :api_key  API authentication key
      # @option config_hash [String]  :model    Model identifier (e.g. "gpt-4o")
      # @option config_hash [Integer] :timeout  Request timeout in seconds (default: 30)
      def initialize(config_hash)
        @config = config_hash
      end

      # Sends a chat completion request and returns the response content.
      #
      # @param messages [Array<Hash>] Array of message objects with :role and :content keys
      # @param options  [Hash]        Optional overrides merged into the request body
      # @return [String, nil] Response content on success, nil on any failure
      def chat(messages, options = {})
        return nil unless configured?

        uri = URI.parse("#{@config[:endpoint]}/chat/completions")
        http = Net::HTTP.new(uri.host, uri.port)
        timeout = @config.fetch(:timeout, 30)
        http.open_timeout = timeout
        http.read_timeout = timeout
        http.use_ssl = uri.scheme == "https"

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{@config[:api_key]}"

        body = {
          model: @config[:model],
          messages: messages
        }.merge(options)

        request.body = JSON.generate(body)

        response = http.request(request)
        response.value # raises Net::HTTPError on 4xx/5xx

        parsed = JSON.parse(response.body)
        parsed.dig("choices", 0, "message", "content")
      rescue Net::OpenTimeout, Net::ReadTimeout, Net::HTTPError, Net::HTTPClientException, JSON::ParserError, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET
        nil
      end

      # Returns true when both endpoint and api_key are present and non-empty.
      #
      # @return [Boolean]
      def configured?
        endpoint = @config[:endpoint]
        api_key  = @config[:api_key]
        !endpoint.nil? && !endpoint.empty? && !api_key.nil? && !api_key.empty?
      end

      # Builds a Client instance from a configuration object that responds to +llm_config+.
      #
      # @param config [#llm_config] An object that returns a config hash via +llm_config+
      # @return [Client]
      def self.from_config(config)
        new(config.llm_config)
      end
    end
  end
end
