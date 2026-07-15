# frozen_string_literal: true

require "json"
require_relative "utils/markdown_helper"

module AutoDoc
  # Multi-strategy ranked search engine for .docs/ documentation artifacts.
  # Searches across INDEX.md, vectors.json, SUMMARY.md, AGENTS.md, and source .rb files.
  #
  # Usage:
  #   results = AutoDoc::SearchService.search("/path/to/project", "AutoDoc")
  #   results = AutoDoc::SearchService.search("/path/to/project", "processor", options: { source: true, limit: 10 })
  class SearchService
    # Performs a multi-strategy ranked search across .docs/ documentation artifacts.
    #
    # @param project_dir [String] Path to the project root directory
    # @param term [String] The search term
    # @param options [Hash] Options hash
    # @option options [Boolean] :source Whether to search source .rb files
    # @option options [Integer] :limit Maximum number of results (default: 20)
    # @return [Hash] Search results with query, results array, and total
    def self.search(project_dir, term, options: {})
      docs_dir = File.join(project_dir, ".docs")

      limit = options.fetch(:limit, 20)
      results = []

      # Walk .docs/ directory using DocumentationIndex (only if it exists)
      if Dir.exist?(docs_dir)
        doc_index = DocumentationIndex.new(docs_dir)
        results.concat(search_index_md(doc_index, term))
        results.concat(search_vectors_json(doc_index, term))
        results.concat(search_summary_md(doc_index, term))
        results.concat(search_agents_md(doc_index, term))
      end

      # Source grep (only when source: true)
      if options[:source]
        results.concat(search_source_files(project_dir, term))
      end

      # Sort by descending score
      results.sort_by! { |r| -r[:score] }

      # Apply limit (use 999999 to effectively disable)
      limit = results.size if limit == 999_999
      results = results.first(limit)

      { query: term, results: results, total: results.size }
    end

    # ── private helpers ──────────────────────────────────────────────

    # Searches INDEX.md symbols/dependencies via DocumentationIndex.
    # @param doc_index [DocumentationIndex] The unified data-access layer
    # @param term [String] Search term
    # @return [Array<Hash>] Result entries
    def self.search_index_md(doc_index, term)
      results = []
      term_down = term.downcase

      # Symbol exact matches
      doc_index.symbols.each do |sym|
        if sym[:symbol].downcase == term_down
          results << {
            file: File.join(".docs", sym[:source_file]),
            score: 100,
            match_type: "symbol_exact",
            line: 0,
            context: sym[:symbol]
          }
        end
      end

      # Dependency partial matches (From or To column)
      doc_index.dependencies.each do |dep|
        if dep[:from].downcase.include?(term_down) || dep[:to].downcase.include?(term_down)
          results << {
            file: File.join(".docs", dep[:source_file]),
            score: 80,
            match_type: "dependency_match",
            line: 0,
            context: "#{dep[:from]} -> #{dep[:to]}"
          }
        end
      end

      results
    end

    # Searches vectors.json via DocumentationIndex for keyword overlap matches.
    # @param doc_index [DocumentationIndex] The unified data-access layer
    # @param term [String] Search term
    # @return [Array<Hash>] Result entries
    def self.search_vectors_json(doc_index, term)
      results = []
      data = doc_index.vectors
      symbols = data["symbols"]
      return results unless symbols.is_a?(Array)

      search_words = term.split(/\s+|_|(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])/).reject(&:empty?).map(&:downcase)

      symbols.each do |entry|
        keywords = entry["keywords"]
        next unless keywords.is_a?(Array)

        keyword_words = keywords.map(&:downcase)
        overlap = search_words.count { |w| keyword_words.include?(w) }

        next if overlap < 1

        score = overlap >= 3 ? 60 : 40
        match_type = overlap >= 3 ? "vector_keyword_high" : "vector_keyword_low"

        results << {
          file: ".docs/vectors.json",
          score: score,
          match_type: match_type,
          line: 0,
          context: entry["symbol"].to_s
        }
      end

      results
    end

    # Searches SUMMARY.md files via DocumentationIndex for full-text matches.
    # @param doc_index [DocumentationIndex] The unified data-access layer
    # @param term [String] Search term
    # @return [Array<Hash>] Result entries
    def self.search_summary_md(doc_index, term)
      results = []
      term_down = term.downcase

      doc_index.all_md_files_content.each do |rel_path, content|
        next unless rel_path.end_with?("SUMMARY.md")

        content.split("\n").each_with_index do |line, idx|
          next if line.strip.empty?
          next unless line.downcase.include?(term_down)

          results << {
            file: File.join(".docs", rel_path),
            score: 20,
            match_type: "summary_text",
            line: idx + 1,
            context: line.strip
          }
        end
      end

      results
    end

    # Searches AGENTS.md files via DocumentationIndex for full-text matches.
    # @param doc_index [DocumentationIndex] The unified data-access layer
    # @param term [String] Search term
    # @return [Array<Hash>] Result entries
    def self.search_agents_md(doc_index, term)
      results = []
      term_down = term.downcase

      doc_index.all_md_files_content.each do |rel_path, content|
        next unless rel_path.end_with?("AGENTS.md")

        content.split("\n").each_with_index do |line, idx|
          next if line.strip.empty?
          next unless line.downcase.include?(term_down)

          results << {
            file: File.join(".docs", rel_path),
            score: 20,
            match_type: "summary_text",
            line: idx + 1,
            context: line.strip
          }
        end
      end

      results
    end

    # Greps a markdown file for term matches.
    # @param file_path [String] Absolute path to file
    # @param term [String] Search term
    # @param rel_path [String] Path relative to .docs/
    # @param match_type [String] Type identifier for results
    # @param score [Integer] Score for matches
    # @return [Array<Hash>] Result entries
    def self.grep_md_file(file_path, term, rel_path, match_type, score)
      results = []
      content = File.read(file_path, encoding: "UTF-8")
      term_down = term.downcase

      content.split("\n").each_with_index do |line, idx|
        next if line.strip.empty?

        if line.downcase.include?(term_down)
          results << {
            file: File.join(".docs", rel_path),
            score: score,
            match_type: match_type,
            line: idx + 1,
            context: line.strip
          }
        end
      end

      results
    end

    # Greps source .rb files (excluding .docs/ directory).
    # @param project_dir [String] Path to the project root directory
    # @param term [String] Search term
    # @return [Array<Hash>] Result entries
    def self.search_source_files(project_dir, term)
      results = []
      term_down = term.downcase

      Dir.glob(File.join(project_dir, "**", "*.rb")).each do |file_path|
        # Skip files inside .docs/
        next if file_path.include?("/.docs/")

        rel_path = file_path.sub("#{project_dir}/", "")

        content = File.read(file_path, encoding: "UTF-8") rescue next
        content.split("\n").each_with_index do |line, idx|
          next if line.strip.empty?

          if line.downcase.include?(term_down)
            results << {
              file: rel_path,
              score: 10,
              match_type: "source_grep",
              line: idx + 1,
              context: line.strip
            }
          end
        end
      end

      results
    end

    private_class_method :search_index_md, :search_vectors_json,
                         :search_summary_md, :search_agents_md,
                         :grep_md_file, :search_source_files
  end
end
