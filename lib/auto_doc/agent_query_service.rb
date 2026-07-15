# frozen_string_literal: true

require "json"
require "pathname"
require_relative "utils/markdown_helper"

module AutoDoc
  # Intent-based query router for natural language documentation queries.
  # Detects intent from prompt patterns and delegates to the appropriate data source.
  # No LLM required — purely regex + file reads.
  #
  # Usage:
  #   result = AutoDoc::AgentQueryService.query("/path/to/project", "what depends on User")
  #   # => { intent: :reverse_dependency, query: "User", result: [...] }
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

    # Queries the documentation knowledge base using intent detection.
    # @param project_dir [String] Path to the project root directory
    # @param prompt [String] Natural language query
    # @return [Hash] Result with intent, query, and result data
    def self.query(project_dir, prompt)
      docs_dir = File.join(project_dir, ".docs")
      return { intent: :error, query: prompt, result: { error: "No .docs/ directory found. Run `auto-doc generate` first." } } unless Dir.exist?(docs_dir)

      prompt_stripped = prompt.strip

      PATTERNS.each do |regex, intent, term_group|
        match = prompt_stripped.match(regex)
        next unless match

        term = term_group ? match[term_group].strip : nil
        result_data = resolve_intent(docs_dir, intent, term)
        return { intent: intent, query: prompt_stripped, result: result_data }
      end

      # Fallback: delegate to SearchService
      search_result = fallback_search(docs_dir, prompt_stripped)
      { intent: :search, result: search_result, query: prompt_stripped }
    end

    private

    # Resolves the detected intent against documentation files.
    def self.resolve_intent(docs_dir, intent, term)
      case intent
      when :reverse_dependency
        find_reverse_deps(docs_dir, term)
      when :forward_dependency
        find_forward_deps(docs_dir, term)
      when :list_symbols
        list_all_symbols(docs_dir)
      when :describe_symbol
        describe_symbol_by_name(docs_dir, term)
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

    # Finds rows in INDEX.md Dependencies table where "To" matches term.
    def self.find_reverse_deps(docs_dir, term)
      term_down = term.downcase
      doc_index = DocumentationIndex.new(docs_dir)
      doc_index.dependencies.select { |r| r[:to].downcase.include?(term_down) }
    end

    # Finds rows in INDEX.md Dependencies table where "From" matches term.
    def self.find_forward_deps(docs_dir, term)
      term_down = term.downcase
      doc_index = DocumentationIndex.new(docs_dir)
      doc_index.dependencies.select { |r| r[:from].downcase.include?(term_down) }
    end

    # Returns all rows from INDEX.md Symbols table.
    def self.list_all_symbols(docs_dir)
      doc_index = DocumentationIndex.new(docs_dir)
      doc_index.symbols
    end

    # Looks up a symbol in VECTORS.json by exact name (case-insensitive).
    def self.describe_symbol_by_name(docs_dir, term)
      doc_index = DocumentationIndex.new(docs_dir)
      vectors = doc_index.vectors
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
                            .map { |f| relative_path(docs_dir, f) }
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
        path: relative_path(docs_dir, file_path)
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

    # Falls back to SearchService
    def self.fallback_search(docs_dir, query)
      project_dir = File.dirname(docs_dir)
      AutoDoc::SearchService.search(project_dir, query)
    end

    def self.relative_path(base, path)
      Pathname.new(path).relative_path_from(Pathname.new(base)).to_s
    end

    private_class_method :resolve_intent, :find_reverse_deps, :find_forward_deps,
                         :list_all_symbols, :describe_symbol_by_name, :read_architecture,
                         :lookup_diagram, :lookup_schema,
                         :fallback_search, :relative_path
  end
end
