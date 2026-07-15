# frozen_string_literal: true

require "json"
require_relative "utils/markdown_helper"

module AutoDoc
  # Unified data-access layer for .docs/ documentation artifacts.
  # Lazy-parses all INDEX.md, vectors.json/VECTORS.json, SUMMARY.md,
  # and AGENTS.md files on first access and caches results.
  #
  # Usage:
  #   idx = DocumentationIndex.new("/path/to/project/.docs")
  #   idx.symbols       # => [{symbol:, type:, file:, line:, documented:, source_file:}, ...]
  #   idx.dependencies  # => [{from:, type:, to:, source_file:}, ...]
  #   idx.vectors       # => {"symbols" => [...]} (merged)
  #   idx.all_md_files_content  # => {"SUMMARY.md" => "...", "module/SUMMARY.md" => "...", ...}
  class DocumentationIndex
    def initialize(docs_dir)
      @docs_dir = docs_dir
      @parsed = false
    end

    # Returns all symbols from all INDEX.md Symbols tables.
    # Each entry: {symbol:, type:, file:, line:, documented:, source_file:}
    # source_file is relative to .docs/ (e.g. "module/INDEX.md")
    def symbols
      parse!
      @_symbols
    end

    # Returns all dependencies from all INDEX.md Dependencies tables.
    # Each entry: {from:, type:, to:, source_file:}
    # source_file is relative to .docs/ (e.g. "module/INDEX.md")
    def dependencies
      parse!
      @_dependencies
    end

    # Returns merged vectors hash from all vectors.json/VECTORS.json files.
    # Merges the "symbols" arrays from all files found.
    # Structure: {"symbols" => [{...}, ...]}
    def vectors
      parse!
      @_vectors
    end

    # Returns a hash of {relative_path => content_string} for all
    # SUMMARY.md and AGENTS.md files found in the .docs/ tree.
    def all_md_files_content
      parse!
      @_md_files
    end

    private

    # One-time parse of all .docs/ artifacts.
    def parse!
      return if @parsed
      @parsed = true
      @_symbols = []
      @_dependencies = []
      @_vectors = {}
      @_md_files = {}

      return unless Dir.exist?(@docs_dir)

      # Walk all files in .docs/ recursively
      Dir.glob(File.join(@docs_dir, "**", "*")).each do |file_path|
        next unless File.file?(file_path)
        rel_path = file_path.sub("#{@docs_dir}/", "")

        case File.basename(file_path)
        when "INDEX.md"
          parse_index_md(file_path, rel_path)
        when "vectors.json", "VECTORS.json"
          parse_vectors_json(file_path)
        when "SUMMARY.md", "AGENTS.md"
          @_md_files[rel_path] = File.read(file_path, encoding: "UTF-8")
        end
      end
    end

    # Parses a single INDEX.md file, extracting Symbols and Dependencies tables.
    def parse_index_md(file_path, rel_path)
      content = File.read(file_path, encoding: "UTF-8")
      lines = content.split("\n")
      current_section = nil

      lines.each_with_index do |line, _idx|
        # Track current section header
        if line =~ /^##\s+(.+)/
          current_section = Regexp.last_match(1).strip.downcase
          next
        end

        # Only process pipe-delimited data rows under a known section
        next unless line.start_with?("|")

        # Skip separator rows (|---|)
        next if line.strip =~ /\A\|[-| ]+\|\z/

        # Skip table header rows
        next if line =~ /\A\|\s*(#|Name|Symbol|From)\s*\|/

        cols = AutoDoc::Utils::MarkdownHelper.parse_pipe_row(line)
        next if cols.size < 3

        case current_section
        when "symbols"
          @_symbols << {
            symbol: cols[0].to_s.strip,
            type: cols[1].to_s.strip,
            file: cols[2].to_s.strip,
            line: cols.size > 3 ? cols[3].to_s.strip : "",
            documented: cols.size > 4 ? cols[4].to_s.strip : "",
            source_file: rel_path
          }
        when "dependencies"
          from_val = cols[0].to_s.strip
          # Skip "No dependencies detected" rows
          next if from_val.empty? || from_val == "\u2014" || from_val.match?(/\A_?No\b/i)

          @_dependencies << {
            from: from_val,
            type: cols[1].to_s.strip,
            to: cols[2].to_s.strip,
            source_file: rel_path
          }
        end
      end
    end

    # Parses a single vectors.json or VECTORS.json file and merges its symbols.
    def parse_vectors_json(file_path)
      data = JSON.parse(File.read(file_path, encoding: "UTF-8"))
      symbols = data["symbols"]
      return unless symbols.is_a?(Array)

      @_vectors["symbols"] ||= []
      @_vectors["symbols"].concat(symbols)
    rescue JSON::ParserError
      nil
    end
  end
end
