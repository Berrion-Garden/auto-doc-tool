# frozen_string_literal: true

module AutoDoc
  module Analyzer
    # Extracts doc comments from Ruby source files.
    # Matches consecutive comment lines (# ...) immediately preceding class/module/method definitions,
    # and returns structured records for each documented symbol found in the file.
    class YardReader
      # @!attribute [r] target_type
      #   :class, :module, or :method
      # @!attribute [r] target_name
      #   Name of the documented symbol
      # @!attribute [r] text
      #   The full comment block text (without leading # markers)
      # @!attribute [r] line
      #   Line number where the comment block starts
      # @!attribute [r] has_summary?
      #   Whether the comment block contains non-whitespace content
      Comment = Struct.new(:target_type, :target_name, :text, :line, :has_summary?) do
        def to_h
          {
            target_type:  target_type,
            target_name:  target_name,
            text:         text,
            line:         line,
            has_summary?: has_summary?
          }
        end
      end

      # Extracts doc comments from a Ruby source file.
      # @param path [String] Path to the Ruby file
      # @return [Array<Hash>] Array of comment records as hashes
      def self.extract(path)
        return [] unless File.exist?(path)
        new(path).extract_doc_comments
      end

      def initialize(file_path)
        @file_path = file_path
        @content   = File.read(file_path, encoding: "UTF-8")
        @lines     = @content.lines
      end

      # Scans the source for consecutive comment blocks that sit immediately
      # before a `class`, `module`, or `def` line and returns each as a record.
      #
      # @return [Array<Hash>] Comment records (one per documented symbol)
      def extract_doc_comments
        comments = []
        i = 0

        while i < @lines.length
          comment_lines, start_idx = collect_comment_block(i)

          next_line_index = start_idx + comment_lines.length

          # If the very next non-blank line is a class/module/def keyword,
          # attach this comment block to that symbol.
          if next_line_index < @lines.length
            target_name, target_type = identify_target(@lines[next_line_index])
            if target_name
              body       = comment_lines.map { |l| l.sub(/\A\s*#\s?/, "") }.join("\n")
              has_summary = !body.strip.empty?
              comments << Comment.new(target_type, target_name, body, start_idx + 1, has_summary)
            end
          end

          # Advance past the comment block (if any) AND the line we just inspected
          # so we never re-process the same target line.
          i = next_line_index + 1
        end

        comments.map(&:to_h)
      end

      private

      # Collects consecutive lines that are pure comment lines (leading whitespace + `#`).
      # Stops at the first non-comment line or end of file.
      #
      # @return [Array<String>, Integer] Tuple of collected comment strings and zero-based start index
      def collect_comment_block(start)
        return [[], start] unless start < @lines.length

        lines = []
        idx   = start

        while idx < @lines.length && @lines[idx].match?(/^\s*#/)
          lines << @lines[idx]
          idx += 1
        end

        [lines, start]
      end

      # Inspects a single source line and returns the symbol name + type
      # if it is a `class`, `module`, or `def` definition.
      #
      # @return [Array<String, Symbol>] Name and type, or [nil, nil] for non-definition lines
      def identify_target(line)
        return [nil, nil] unless line.is_a?(String)

        if (m = line.match(/\A\s*class\s+([A-Z]\w*(?:::\w+)*)/))
          return [m[1], :class]
        end

        if (m = line.match(/\A\s*module\s+([A-Z]\w*(?:::\w+)*)/))
          return [m[1], :module]
        end

        if (m = line.match(/\A\s*def\s+(?:self\.)?(\w+(?:[?!])?)/))
          return [m[1], :method]
        end

        [nil, nil]
      end
    end
  end
end
