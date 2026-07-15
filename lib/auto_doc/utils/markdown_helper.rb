# frozen_string_literal: true

module AutoDoc
  module Utils
    # Shared utilities for parsing markdown content.
    module MarkdownHelper
      # Parses a pipe-delimited markdown row into column values.
      # @param line [String] A line containing a pipe-delimited row
      # @return [Array<String>] Trimmed column values
      def self.parse_pipe_row(line)
        line.strip
            .gsub(/\A\||\|\z/, "") # Remove leading/trailing pipes
            .split("|")
            .map(&:strip)
      end
    end
  end
end
