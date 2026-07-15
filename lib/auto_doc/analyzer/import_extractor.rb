# frozen_string_literal: true

module AutoDoc
  module Analyzer
    # Extracts import and dependency statements from Ruby source files.
    # Supports require, require_relative, include, prepend, and extend keywords.
    class ImportExtractor
      IMPORT_PATTERNS = {
        require:          /^(?:\s*)require\s+(['"])(.*?)\1/,
        require_relative: /^(?:\s*)require_relative\s+(['"])(.*?)\1/,
        include:          /^(?:\s*)include\s+([^\n]+)$/,
        prepend:          /^(?:\s*)prepend\s+([^\n]+)$/,
        extend:           /^(?:\s*)extend\s+([^\n]+)$/
      }.freeze

      # Extracts import statements from a Ruby source file.
      # @param path [String] Path to the Ruby file
      # @return [Array<Hash>] Array of import records
      #   Each record: { path:, type: } where type is one of
      #   :require, :require_relative, :include, :prepend, :extend
      def self.extract(path)
        return [] unless File.exist?(path)
        new(path).extract_imports
      end

      def initialize(file_path)
        @file_path = file_path
        @content   = File.read(file_path, encoding: "UTF-8")
      end

      # @return [Array<Hash>] Extracted imports
      def extract_imports
        results = []

        IMPORT_PATTERNS.each do |type, pattern|
          @content.scan(pattern) do |matches|
            value = matches.flatten.compact.last.to_s.strip
            next if value.empty?

            case type
            when :require, :require_relative
              results << { path: value, type: type }
            else
              # For include/prepend/extend, split comma-separated constants
              values = value.split(",").map(&:strip).reject(&:empty?)
              values.each do |v|
                results << { path: v, type: type }
              end
            end
          end
        end

        results
      end
    end
  end
end
