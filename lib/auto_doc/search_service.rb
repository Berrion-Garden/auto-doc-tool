# frozen_string_literal: true

require "json"

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

      # Walk .docs/ directory recursively (only if it exists)
      if Dir.exist?(docs_dir)
        Dir.glob(File.join(docs_dir, "**", "*")).each do |file_path|
          next unless File.file?(file_path)
          rel_path = file_path.sub("#{docs_dir}/", "")

          case File.basename(file_path)
          when "INDEX.md"
            results.concat(search_index_md(file_path, term, rel_path))
          when "vectors.json"
            results.concat(search_vectors_json(file_path, term, rel_path))
          when "SUMMARY.md"
            results.concat(search_summary_md(file_path, term, rel_path))
          when "AGENTS.md"
            results.concat(search_agents_md(file_path, term, rel_path))
          end
        end
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

    # Searches INDEX.md for symbol exact matches and dependency matches.
    # @param file_path [String] Absolute path to INDEX.md
    # @param term [String] Search term
    # @param rel_path [String] Path relative to .docs/
    # @return [Array<Hash>] Result entries
    def self.search_index_md(file_path, term, rel_path)
      results = []
      content = File.read(file_path, encoding: "UTF-8")
      lines = content.split("\n")

      current_section = nil
      term_down = term.downcase

      lines.each_with_index do |line, idx|
        # Track current section header
        if line =~ /^##\s+(.+)/
          current_section = Regexp.last_match(1).strip.downcase
        end

        # Only process pipe-delimited data rows under a known section
        next unless line.start_with?("|")

        # Skip separator rows (|---|)
        next if line.strip =~ /\A\|[-| ]+\|\z/

        # Skip table header rows
        next if line =~ /\A\|\s*(#|Name|Symbol|From)\s*\|/

        stripped = line.strip

        case current_section
        when "symbols"
          cols = parse_pipe_row(line)
          next if cols.size < 3

          symbol_name = cols[0].to_s.strip

          # Case-insensitive exact match
          if symbol_name.downcase == term_down
            results << {
              file: File.join(".docs", rel_path),
              score: 100,
              match_type: "symbol_exact",
              line: idx + 1,
              context: stripped
            }
          end

        when "dependencies"
          cols = parse_pipe_row(line)
          next if cols.size < 3

          from_val = cols[0].to_s.strip
          to_val   = cols[2].to_s.strip

          # Case-insensitive partial match on From or To
          if from_val.downcase.include?(term_down) || to_val.downcase.include?(term_down)
            results << {
              file: File.join(".docs", rel_path),
              score: 80,
              match_type: "dependency_match",
              line: idx + 1,
              context: stripped
            }
          end
        end
      end

      results
    end

    # Searches vectors.json for keyword overlap matches.
    # @param file_path [String] Absolute path to vectors.json
    # @param term [String] Search term
    # @param rel_path [String] Path relative to .docs/
    # @return [Array<Hash>] Result entries
    def self.search_vectors_json(file_path, term, rel_path)
      results = []
      content = File.read(file_path, encoding: "UTF-8")
      data = JSON.parse(content)

      symbols = data["symbols"]
      return results unless symbols.is_a?(Array)

      search_words = term.split(/\s+|_|(?<=[a-z])(?=[A-Z])/).reject(&:empty?).map(&:downcase)

      symbols.each do |entry|
        keywords = entry["keywords"]
        next unless keywords.is_a?(Array)

        keyword_words = keywords.map(&:downcase)
        overlap = search_words.count { |w| keyword_words.include?(w) }

        next if overlap < 1

        score = overlap >= 3 ? 60 : 40
        match_type = overlap >= 3 ? "vector_keyword_high" : "vector_keyword_low"

        results << {
          file: File.join(".docs", rel_path),
          score: score,
          match_type: match_type,
          line: 0,
          context: entry["symbol"].to_s
        }
      end

      results
    end

    # Searches SUMMARY.md for full-text matches.
    # @param file_path [String] Absolute path to SUMMARY.md
    # @param term [String] Search term
    # @param rel_path [String] Path relative to .docs/
    # @return [Array<Hash>] Result entries
    def self.search_summary_md(file_path, term, rel_path)
      grep_md_file(file_path, term, rel_path, "summary_text", 20)
    end

    # Searches AGENTS.md for full-text matches.
    # @param file_path [String] Absolute path to AGENTS.md
    # @param term [String] Search term
    # @param rel_path [String] Path relative to .docs/
    # @return [Array<Hash>] Result entries
    def self.search_agents_md(file_path, term, rel_path)
      grep_md_file(file_path, term, rel_path, "summary_text", 20)
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

    # Parses a pipe-delimited markdown row into column values.
    # @param line [String] A line containing a pipe-delimited row
    # @return [Array<String>] Trimmed column values
    def self.parse_pipe_row(line)
      line.strip
          .gsub(/\A\||\|\z/, "") # Remove leading/trailing pipes
          .split("|")
          .map(&:strip)
    end

    private_class_method :search_index_md, :search_vectors_json,
                         :search_summary_md, :search_agents_md,
                         :grep_md_file, :search_source_files,
                         :parse_pipe_row
  end
end
