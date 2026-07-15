# frozen_string_literal: true

require "json"
require "fileutils"

module AutoDoc
  # Intent-based query router that maps natural-language prompts to
  # documentation retrieval strategies. Uses pattern matching via regex
  # (no LLM). Falls back to SearchService for unrecognized prompts.
  #
  # Usage:
  #   result = AutoDoc::AgentQueryService.query("/path/to/project", "what depends on Calculator")
  #   # => { intent: :reverse_dependency, result: [...], query: "what depends on Calculator" }
  class AgentQueryService
    # Pattern definitions: [regex, intent, term_capture_group_index]
    # Sorted by priority — first match wins.
    PATTERNS = [
      # 1. Reverse dependency: "what depends on X", "dependents of X", "who uses X"
      [/\A(?:what\s+)?depends\s+on\s+(.+)/i, :reverse_dependency, 1],
      [/\Adependents\s+of\s+(.+)/i, :reverse_dependency, 1],
      [/\Awho\s+uses\s+(.+)/i, :reverse_dependency, 1],

      # 2. Forward dependency: "X depends on", "deps of X", "dependencies of X"
      [/\A(.+?)\s+depends\s+on\b/i, :forward_dependency, 1],
      [/\Adeps\s+of\s+(.+)/i, :forward_dependency, 1],
      [/\Adependencies\s+of\s+(.+)/i, :forward_dependency, 1],

      # 3. List symbols: "list all", "symbols in"
      [/\Alist\s+all/i, :list_symbols, nil],
      [/\Asymbols\s+in/i, :list_symbols, nil],

      # 4. Describe symbol: "what does X do", "describe X", "what is X"
      [/\Awhat\s+does\s+(.+?)\s+do\b/i, :describe_symbol, 1],
      [/\Adescribe\s+(.+)/i, :describe_symbol, 1],
      [/\Awhat\s+is\s+(.+)/i, :describe_symbol, 1],

      # 5. Architecture: "architecture of", "arch of"
      [/\Aarchitecture\s+of/i, :architecture, nil],
      [/\Aarch\s+of/i, :architecture, nil],

      # 6. Diagram lookup: "diagram for X", "show diagram X"
      [/\Adiagram\s+for\s+(.+)/i, :diagram_lookup, 1],
      [/\Ashow\s+diagram\s+(.+)/i, :diagram_lookup, 1],

      # 7. Schema lookup: "schema for X", "table X"
      [/\Aschema\s+for\s+(.+)/i, :schema_lookup, 1],
      [/\Atable\s+(.+)/i, :schema_lookup, 1]
    ].freeze

    private_constant :PATTERNS

    # Queries documentation artifacts based on natural-language prompt.
    #
    # @param project_dir [String] Path to the project root directory
    # @param prompt [String] Natural-language query
    # @return [Hash] Result with keys :intent, :result, :query
    def self.query(project_dir, prompt)
      docs_dir = File.join(project_dir, ".docs")

      unless Dir.exist?(docs_dir)
        return { intent: :error, result: { error: "No .docs/ directory found at #{project_dir}" }, query: prompt }
      end

      prompt_stripped = prompt.strip

      # Try each pattern in priority order
      PATTERNS.each do |regex, intent, term_group|
        match = prompt_stripped.match(regex)
        next unless match

        term = term_group ? match[term_group].strip : nil
        result = dispatch(intent, project_dir, docs_dir, term, prompt_stripped)
        return { intent: intent, result: result, query: prompt_stripped }
      end

      # Fallback: delegate to SearchService
      search_result = AutoDoc::SearchService.search(project_dir, prompt_stripped)
      { intent: :search, result: search_result, query: prompt_stripped }
    end

    # ── private dispatch ─────────────────────────────────────────────────

    def self.dispatch(intent, project_dir, docs_dir, term, prompt)
      case intent
      when :reverse_dependency
        lookup_reverse_dependency(docs_dir, term)
      when :forward_dependency
        lookup_forward_dependency(docs_dir, term)
      when :list_symbols
        list_all_symbols(docs_dir)
      when :describe_symbol
        describe_symbol(docs_dir, term)
      when :architecture
        read_architecture(docs_dir)
      when :diagram_lookup
        lookup_diagram(docs_dir, term)
      when :schema_lookup
        lookup_schema(docs_dir, term)
      else
        { error: "Unknown intent: #{intent}" }
      end
    end

    private_class_method :dispatch

    # ── handler implementations ─────────────────────────────────────────

    # Finds rows in INDEX.md Dependencies table where "To" matches term.
    def self.lookup_reverse_dependency(docs_dir, term)
      rows = parse_dependencies_table(docs_dir)
      term_down = term.downcase
      rows.select { |r| r[:to].downcase.include?(term_down) }
    end

    # Finds rows in INDEX.md Dependencies table where "From" matches term.
    def self.lookup_forward_dependency(docs_dir, term)
      rows = parse_dependencies_table(docs_dir)
      term_down = term.downcase
      rows.select { |r| r[:from].downcase.include?(term_down) }
    end

    # Returns all rows from INDEX.md Symbols table.
    def self.list_all_symbols(docs_dir)
      parse_symbols_table(docs_dir)
    end

    # Looks up a symbol entry in VECTORS.json by name.
    def self.describe_symbol(docs_dir, term)
      vectors = load_vectors_json(docs_dir)
      return nil unless vectors

      term_down = term.downcase
      vectors["symbols"]&.find { |entry| entry["symbol"].to_s.downcase == term_down }
    end

    # Reads architecture.md content and lists available diagram files.
    def self.read_architecture(docs_dir)
      arch_path = File.join(docs_dir, "architecture.md")
      content = File.exist?(arch_path) ? File.read(arch_path, encoding: "UTF-8") : ""

      diagrams_dir = File.join(docs_dir, "diagrams")
      diagram_links = []
      if Dir.exist?(diagrams_dir)
        diagram_links = Dir.glob(File.join(diagrams_dir, "*.mmd"))
                            .map { |f| f.sub("#{docs_dir}/", "") }
                            .sort
      end

      { content: content, diagrams: diagram_links }
    end

    # Finds and reads a matching .mmd diagram file by name.
    def self.lookup_diagram(docs_dir, term)
      diagrams_dir = File.join(docs_dir, "diagrams")
      return nil unless Dir.exist?(diagrams_dir)

      pattern = term.downcase.gsub(/[^a-z0-9_-]/, "")
      matches = Dir.glob(File.join(diagrams_dir, "*.mmd"))
                   .select { |f| File.basename(f, ".mmd").downcase.include?(pattern) }

      return nil if matches.empty?

      file_path = matches.first
      {
        name: File.basename(file_path, ".mmd"),
        content: File.read(file_path, encoding: "UTF-8"),
        path: file_path.sub("#{docs_dir}/", "")
      }
    end

    # Looks up a table definition in schema.json.
    def self.lookup_schema(docs_dir, term)
      schema_path = File.join(docs_dir, "schema", "schema.json")
      return nil unless File.exist?(schema_path)

      schema = JSON.parse(File.read(schema_path, encoding: "UTF-8"))
      term_down = term.downcase

      # schema.json may be an array of table definitions or a hash with table names as keys
      if schema.is_a?(Array)
        schema.find { |t| t["table"]&.downcase == term_down || t["name"]&.downcase == term_down }
      elsif schema.is_a?(Hash)
        result = schema[term]
        result ||= schema[term_down]
        result ||= schema[term_down.sub(/s$/, "")] unless term_down.end_with?("s")
        result ||= schema["#{term_down}s"]
        result
      end
    end

    # ── data loading helpers ────────────────────────────────────────────

    # Parses a named section table from INDEX.md, yielding parsed columns for each data row.
    # Handles section tracking, pipe-row iteration, separator-row skipping, and header-row skipping.
    # The block receives parsed column values and returns a result hash (or nil to skip the row).
    def self.parse_markdown_section_table(docs_dir, section_name, header_pattern: nil, &row_builder)
      index_path = File.join(docs_dir, "INDEX.md")
      return [] unless File.exist?(index_path)

      lines = File.read(index_path, encoding: "UTF-8").split("\n")
      current_section = nil
      results = []

      lines.each do |line|
        # Track current section header
        if line =~ /^##\s+(.+)/
          current_section = Regexp.last_match(1).strip.downcase
          next
        end

        next unless current_section == section_name.downcase
        next unless line.start_with?("|")

        # Skip separator rows (|---|)
        next if line.strip =~ /\A\|[-| ]+\|\z/

        # Skip table header rows
        next if header_pattern && line =~ header_pattern

        cols = parse_pipe_row(line)
        next if cols.size < 3

        row = row_builder.call(cols)
        results << row if row
      end

      results
    end

    # Parses INDEX.md Dependencies table into array of {from:, type:, to:} hashes.
    def self.parse_dependencies_table(docs_dir)
      parse_markdown_section_table(docs_dir, "dependencies",
                                   header_pattern: /\A\|\s*From\s*\|/) do |cols|
        # Skip placeholder rows (no dependencies, blank from column, em-dash)
        next if cols[0].to_s.strip.empty? || cols[0].to_s.strip == "—" || cols[0].to_s.strip.match?(/\A_?No\b/)

        {
          from: cols[0].to_s.strip,
          type: cols[1].to_s.strip,
          to: cols[2].to_s.strip
        }
      end
    end

    # Parses INDEX.md Symbols table into array of {symbol:, type:, file:, line:, documented:} hashes.
    def self.parse_symbols_table(docs_dir)
      parse_markdown_section_table(docs_dir, "symbols",
                                   header_pattern: /\A\|\s*(#|Name|Symbol)\s*\|/) do |cols|
        {
          symbol: cols[0].to_s.strip,
          type: cols[1].to_s.strip,
          file: cols[2].to_s.strip,
          line: cols.size > 3 ? cols[3].to_s.strip : "",
          documented: cols.size > 4 ? cols[4].to_s.strip : ""
        }
      end
    end

    # Loads VECTORS.json (case-insensitive filename lookup).
    def self.load_vectors_json(docs_dir)
      # Try exact name first, then case-insensitive glob
      vectors_path = File.join(docs_dir, "VECTORS.json")
      unless File.exist?(vectors_path)
        matches = Dir.glob(File.join(docs_dir, "vectors.json"))
        return nil if matches.empty?

        vectors_path = matches.first
      end

      JSON.parse(File.read(vectors_path, encoding: "UTF-8"))
    rescue JSON::ParserError
      nil
    end

    # Parses a pipe-delimited markdown row into column values.
    def self.parse_pipe_row(line)
      line.strip
          .gsub(/\A\||\|\z/, "") # Remove leading/trailing pipes
          .split("|")
          .map(&:strip)
    end

    private_class_method :lookup_reverse_dependency, :lookup_forward_dependency,
                         :list_all_symbols, :describe_symbol, :read_architecture,
                         :lookup_diagram, :lookup_schema,
                         :parse_markdown_section_table, :parse_dependencies_table,
                         :parse_symbols_table,
                         :load_vectors_json, :parse_pipe_row
  end
end
