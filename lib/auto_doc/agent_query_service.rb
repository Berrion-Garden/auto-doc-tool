# frozen_string_literal: true

require "json"
require "pathname"

module AutoDoc
  # Intent-based query router for natural language documentation queries.
  # Detects intent from prompt patterns and delegates to the appropriate data source.
  # No LLM required — purely regex + file reads.
  #
  # Usage:
  #   result = AutoDoc::AgentQueryService.query("/path/to/project", "what depends on User")
  #   # => { intent: :reverse_dependency, query: "User", result: [...] }
  class AgentQueryService
    INTENT_PATTERNS = [
      { pattern: /(?:what|who)\s+(?:depends on|uses|imports|references?)\s+(\S+)/i, intent: :reverse_dependency },
      { pattern: /(\S+)\s+(?:dependents|consumers|usages?)/i, intent: :reverse_dependency },
      { pattern: /(?:show me|list|get)\s+(\S+)(?:'s)?\s+(?:dependencies|deps|imports)/i, intent: :forward_dependency },
      { pattern: /(\S+)\s+(?:depends on|uses|imports|references?)\s+/i, intent: :forward_dependency },
      { pattern: /(?:list|show|get|find)\s+(?:all\s+)?(?:classes?|modules?|symbols?)\s+(?:in\s+)?(\S+)/i, intent: :list_symbols },
      { pattern: /(?:what does|describe|explain|tell me about)\s+(\S+)/i, intent: :describe_symbol },
      { pattern: /(?:architecture|arch|structure)\s+(?:of\s+)?(\S+)/i, intent: :architecture },
      { pattern: /(?:show|get|view)\s+(?:the\s+)?(?:diagram|graph)\s+(?:for\s+)?(\S+)/i, intent: :diagram_lookup },
      { pattern: /(?:schema|table|model)\s+(?:for\s+)?(?:the\s+)?(\S+)/i, intent: :schema_lookup },
    ].freeze

    # Queries the documentation knowledge base using intent detection.
    # @param project_dir [String] Path to the project root directory
    # @param prompt [String] Natural language query
    # @return [Hash] Result with intent, query, and result data
    def self.query(project_dir, prompt)
      docs_dir = File.join(project_dir, ".docs")
      return { intent: :error, query: prompt, result: "No .docs/ directory found. Run `auto-doc generate` first." } unless Dir.exist?(docs_dir)

      detected_intent = nil
      captured_query = nil

      INTENT_PATTERNS.each do |entry|
        if (m = prompt.match(entry[:pattern]))
          detected_intent = entry[:intent]
          captured_query = m[1]
          break
        end
      end

      detected_intent ||= :fallback
      captured_query ||= prompt

      result_data = resolve_intent(docs_dir, detected_intent, captured_query)

      {
        intent: detected_intent,
        query: captured_query,
        result: result_data
      }
    end

    private

    # Resolves the detected intent against documentation files.
    def self.resolve_intent(docs_dir, intent, query)
      query_lower = query.downcase

      case intent
      when :reverse_dependency
        find_reverse_deps(docs_dir, query_lower)
      when :forward_dependency
        find_forward_deps(docs_dir, query_lower)
      when :list_symbols
        find_symbols(docs_dir, query_lower)
      when :describe_symbol
        describe_symbol(docs_dir, query_lower)
      when :architecture
        get_architecture(docs_dir)
      when :diagram_lookup
        find_diagram(docs_dir, query_lower)
      when :schema_lookup
        find_schema(docs_dir, query_lower)
      else
        fallback_search(docs_dir, query)
      end
    end

    # Reads all INDEX.md files to find reverse dependencies (who depends on X)
    def self.find_reverse_deps(docs_dir, target)
      results = []
      Dir.glob(File.join(docs_dir, "**", "INDEX.md")).each do |index_path|
        content = File.read(index_path)
        in_deps = false
        content.each_line do |line|
          in_deps = true if line =~ /^##\s*Dependencies/i
          in_deps = false if line =~ /^##\s*(?!Dependencies)/ && line.start_with?("##")
          next unless in_deps && line.start_with?("|")
          next if line.strip =~ /\A\|[-| ]+\|\z/ || line =~ /\A\|\s*(From|#)\s*\|/
          cols = line.split("|").map(&:strip).reject(&:empty?)
          next if cols.size < 3
          if cols[2].downcase.include?(target)
            results << { from: cols[0], type: cols[1], to: cols[2], file: relative_path(docs_dir, index_path) }
          end
        end
      end
      results.empty? ? "No reverse dependencies found for '#{target}'." : results
    end

    # Reads all INDEX.md files to find forward dependencies (what does X depend on)
    def self.find_forward_deps(docs_dir, target)
      results = []
      Dir.glob(File.join(docs_dir, "**", "INDEX.md")).each do |index_path|
        content = File.read(index_path)
        in_deps = false
        content.each_line do |line|
          in_deps = true if line =~ /^##\s*Dependencies/i
          in_deps = false if line =~ /^##\s*(?!Dependencies)/ && line.start_with?("##")
          next unless in_deps && line.start_with?("|")
          next if line.strip =~ /\A\|[-| ]+\|\z/ || line =~ /\A\|\s*(From|#)\s*\|/
          cols = line.split("|").map(&:strip).reject(&:empty?)
          next if cols.size < 3
          if cols[0].downcase.include?(target)
            results << { from: cols[0], type: cols[1], to: cols[2], file: relative_path(docs_dir, index_path) }
          end
        end
      end
      results.empty? ? "No dependencies found for '#{target}'." : results
    end

    # Reads INDEX.md Symbols tables to list symbols
    def self.find_symbols(docs_dir, target)
      results = []
      Dir.glob(File.join(docs_dir, "**", "INDEX.md")).each do |index_path|
        rel = relative_path(docs_dir, index_path)
        next unless target == "all" || rel.downcase.include?(target) || File.basename(File.dirname(index_path)).downcase.include?(target)
        content = File.read(index_path)
        in_symbols = false
        content.each_line do |line|
          in_symbols = true if line =~ /^##\s*Symbols/i
          in_symbols = false if line =~ /^##\s*(?!Symbols)/ && line.start_with?("##")
          next unless in_symbols && line.start_with?("|")
          next if line.strip =~ /\A\|[-| ]+\|\z/ || line =~ /\A\|\s*(Name|#|Symbol)\s*\|/
          cols = line.split("|").map(&:strip).reject(&:empty?)
          next if cols.size < 3
          results << { symbol: cols[0], type: cols[1], file: rel }
        end
      end
      results.empty? ? "No symbols found for '#{target}'." : results
    end

    # Looks up a symbol in VECTORS.json
    def self.describe_symbol(docs_dir, target)
      pattern = /#{Regexp.escape(target)}/i
      Dir.glob(File.join(docs_dir, "**", "vectors.json")).each do |vec_path|
        content = JSON.parse(File.read(vec_path))
        symbols = content["symbols"] || []
        match = symbols.find { |s| s["symbol"] =~ pattern || s["keywords"]&.any? { |k| k =~ pattern } }
        return match if match
      end
      Dir.glob(File.join(docs_dir, "**", "VECTORS.json")).each do |vec_path|
        content = JSON.parse(File.read(vec_path))
        symbols = content["symbols"] || []
        match = symbols.find { |s| s["symbol"] =~ pattern || s["keywords"]&.any? { |k| k =~ pattern } }
        return match if match
      end
      "No description found for '#{target}'."
    end

    # Returns architecture.md content
    def self.get_architecture(docs_dir)
      arch_path = File.join(docs_dir, "architecture.md")
      if File.exist?(arch_path)
        content = File.read(arch_path)
        { architecture: content, diagrams: Dir.glob(File.join(docs_dir, "diagrams", "*.mmd")).map { |f| File.basename(f) } }
      else
        "No architecture.md found. Run `auto-doc generate` with Rails detection."
      end
    end

    # Finds a diagram by name
    def self.find_diagram(docs_dir, target)
      pattern = /#{Regexp.escape(target)}/i
      diagrams = Dir.glob(File.join(docs_dir, "diagrams", "*.mmd"))
      match = diagrams.find { |f| File.basename(f, ".mmd") =~ pattern }
      if match
        { name: File.basename(match), path: relative_path(docs_dir, match), content: File.read(match) }
      else
        available = diagrams.map { |f| File.basename(f, ".mmd") }
        "Diagram '#{target}' not found. Available diagrams: #{available.join(', ')}"
      end
    end

    # Looks up a table in schema.json
    def self.find_schema(docs_dir, target)
      schema_path = File.join(docs_dir, "schema", "schema.json")
      if File.exist?(schema_path)
        tables = JSON.parse(File.read(schema_path))
        pattern = /#{Regexp.escape(target)}/i
        match = tables.find { |t| t["table_name"] =~ pattern }
        return match if match
        "Table '#{target}' not found. Available tables: #{tables.map { |t| t['table_name'] }.join(', ')}"
      else
        "No schema.json found. Run `auto-doc generate` on a Rails project."
      end
    end

    # Falls back to SearchService
    def self.fallback_search(docs_dir, query)
      # docs_dir is project_dir/.docs, so project_dir is the parent of docs_dir
      project_dir = File.dirname(docs_dir)
      AutoDoc::SearchService.search(project_dir, query)
    end

    def self.relative_path(base, path)
      Pathname.new(path).relative_path_from(Pathname.new(base)).to_s
    end

    private_class_method :resolve_intent, :find_reverse_deps, :find_forward_deps,
                         :find_symbols, :describe_symbol, :get_architecture,
                         :find_diagram, :find_schema, :fallback_search, :relative_path
  end
end
