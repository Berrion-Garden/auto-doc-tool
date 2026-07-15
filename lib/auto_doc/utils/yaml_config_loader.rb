# frozen_string_literal: true

begin
  require "yaml"
  YAML_AVAILABLE = true
rescue LoadError
  YAML_AVAILABLE = false
end

module AutoDoc
  module Utils
    # Simple YAML file reader with validation.
    # Returns an empty hash if the file does not exist or is invalid YAML.
    class YamlConfigLoader
      EXPECTED_KEYS = %i[
        module_roots
        exclude_patterns
        output
        audit
        diagrams
      ].freeze

      # Loads and parses a YAML config file at the given path.
      # Returns empty hash if file does not exist, is empty, or contains invalid YAML.
      def self.load(file_path)
        return {} unless File.exist?(file_path)
        return {} if File.zero?(file_path)

        content = File.read(file_path)
        return {} unless YAML_AVAILABLE

        parsed = YAML.safe_load(content, permitted_classes: [Symbol], aliases: true)
        return {} unless parsed.is_a?(Hash)

        # Convert string keys to symbols for consistency
        symbolize_keys(parsed)
      end

      def self.symbolize_keys(hash)
        hash.each_with_object({}) do |(key, value), result|
          new_key = key.is_a?(String) ? key.to_sym : key
          result[new_key] = value.is_a?(Hash) ? symbolize_keys(value) : value
        end
      end

      private_class_method :symbolize_keys
    end
  end
end
