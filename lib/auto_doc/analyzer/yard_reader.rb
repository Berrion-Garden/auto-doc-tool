# frozen_string_literal: true

begin
  require "yard"
rescue LoadError
  # YARD is an optional dependency; parsing falls back to regex-only.
end

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
      YARD_AVAILABLE = defined?(YARD)

      # @!attribute [r] has_summary?
      #   Whether the comment block contains non-whitespace content
      # @!attribute [r] params
      #   Array of parameter hashes with name, types, and description
      # @!attribute [r] return_type
      #   The documented return type as a string, or nil
      # @!attribute [r] yield_type
      #   The documented yield type as a string, or nil
      # @!attribute [r] tags
      #   Array of unrecognized tag hashes with tag_name and text
      Comment = Struct.new(:target_type, :target_name, :text, :line, :has_summary?,
                           :params, :return_type, :yield_type, :tags) do
        def to_h
          {
            target_type:  target_type,
            target_name:  target_name,
            text:         text,
            line:         line,
            has_summary?: has_summary?,
            params:       params,
            return_type:  return_type,
            yield_type:   yield_type,
            tags:         tags
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
              comment = Comment.new(target_type, target_name, body, start_idx + 1, has_summary,
                                     [], nil, nil, [])

              # Enrich with YARD structured data if the gem is available.
              if YARD_AVAILABLE && !body.strip.empty?
                parser = YARD::Docstring.parser
                parser.parse(body)
                docstring = parser.to_docstring
                comment.params = docstring.tags(:param).map do |t|
                  { name: t.name, types: t.types || [], description: t.text }
                end
                if (rt = docstring.tag(:return))
                  comment.return_type = rt.types&.first
                end
                # Check yieldreturn first, then yield/yieldparam for yield type
                if (yt = docstring.tag(:yieldreturn))
                  comment.yield_type = yt.types&.first
                elsif (yt = docstring.tag(:yield))
                  comment.yield_type = yt.types&.first
                elsif (yp = docstring.tag(:yieldparam))
                  comment.yield_type = yp.types&.first
                end
                known_tags = %i[param return yield yieldreturn yieldparam]
                comment.tags = docstring.tags.reject { |t| known_tags.include?(t.tag_name.to_sym) }
                                            .map { |t| { tag_name: t.tag_name, text: t.text } }
              end

              comments << comment
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
