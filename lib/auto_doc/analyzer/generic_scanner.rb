# frozen_string_literal: true

module AutoDoc
  module Analyzer
    # Scans non-Ruby source files using regex patterns to extract
    # function, class, and method definitions. Supports multiple
    # languages via extension and shebang detection.
    #
    # Returns structured definition data in the same format as SourceParser
    # so it can be used as a fallback in the analysis pipeline.
    class GenericScanner
      # Mapping of file extensions to language symbols
      SUPPORTED_EXTENSIONS = {
        ".rb"   => :ruby,
        ".py"   => :python,
        ".js"   => :javascript,
        ".ts"   => :typescript,
        ".go"   => :go,
        ".rs"   => :rust,
        ".java" => :java,
        ".sh"   => :bash,
        ".jsx"  => :react,
        ".tsx"  => :react_typescript,
        ".swift" => :swift,
        ".kt"   => :kotlin,
        ".php"  => :php
      }.freeze

      # Regex patterns for extracting definitions, keyed by language symbol.
      # Each entry may contain :function, :class, and :method patterns.
      REGEX_PATTERNS = {
        python: {
          function: /def\s+(\w+)/,
          class: /class\s+(\w+)/
        },
        javascript: {
          function: /function\s+(\w+)/,
          class: /class\s+(\w+)/,
          method: /(\w+)\s*=\s*function/
        },
        typescript: {
          function: /function\s+(\w+)/,
          class: /class\s+(\w+)/,
          method: /(\w+)\s*=\s*function/
        },
        go: {
          function: /func\s+(\w+)/,
          class: /type\s+(\w+)\s+(struct|interface)/
        },
        rust: {
          function: /fn\s+(\w+)/,
          class: /(?:struct|enum|trait)\s+(\w+)/
        },
        java: {
          method: /(?:public|private|protected)\s+(?:\w+\s+)*(\w+)\s*\(/,
          class: /(?:public\s+)?(?:abstract\s+)?(?:class|interface)\s+(\w+)/
        },
        bash: {
          function: /^(\w+)\s*\(\)/
        },
        react: {
          function: /function\s+(\w+)/,
          class: /class\s+(\w+)/,
          method: /(\w+)\s*=\s*function/
        },
        react_typescript: {
          function: /function\s+(\w+)/,
          class: /class\s+(\w+)/,
          method: /(\w+)\s*=\s*function/
        },
        swift: {
          function: /func\s+(\w+)/,
          class: /(?:class|struct|enum)\s+(\w+)/
        },
        kotlin: {
          function: /fun\s+(\w+)/,
          class: /(?:class|object|interface)\s+(\w+)/
        },
        php: {
          function: /function\s+(\w+)/,
          class: /class\s+(\w+)/
        }
      }.freeze

      SHEBANG_LANGUAGE_MAP = {
        "python"  => :python,
        "python3" => :python,
        "node"    => :javascript,
        "bash"    => :bash,
        "sh"      => :bash,
        "ruby"    => :ruby,
        "deno"    => :typescript,
        "go"      => :go,
        "java"    => :java
      }.freeze

      # Detects the programming language of a file based on its extension
      # and optionally its shebang line.
      #
      # @param file_path [String] Path to the file
      # @param first_lines [String, nil] First few lines of the file (for shebang detection)
      # @return [Symbol] Language symbol or :unknown
      def self.detect_language(file_path, first_lines = nil)
        ext = File.extname(file_path)
        return SUPPORTED_EXTENSIONS[ext] if SUPPORTED_EXTENSIONS.key?(ext)

        if first_lines
          shebang = first_lines.lines.first
          if shebang&.start_with?("#!")
            SHEBANG_LANGUAGE_MAP.each do |interpreter, lang|
              return lang if shebang.include?(interpreter)
            end
          end
        end

        :unknown
      end

      # Parses a source file and returns structured definitions.
      #
      # @param path [String] Absolute path to the file
      # @return [Array<Hash>] Array of { name:, type:, line: } hashes
      def self.parse_file(path)
        return [] unless File.exist?(path)

        content = File.read(path, encoding: "UTF-8")
        language = detect_language(path, content)

        return [] if language == :unknown

        patterns = REGEX_PATTERNS[language]
        return [] unless patterns

        result = []
        lines = content.lines

        patterns.each do |type, regex|
          lines.each_with_index do |line, idx|
            line.match(regex) do |m|
              result << { name: m[1], type: type, line: idx + 1 }
            end
          end
        end

        result
      rescue StandardError
        []
      end

      # Analyzes source content using an LLM client for enrichment.
      #
      # @param content [String] The file's source content
      # @param language [Symbol] Language symbol (e.g. :python, :javascript)
      # @param client [AutoDoc::LLM::Client] LLM client instance
      # @return [String, nil] LLM response text or nil on failure
      def self.enrich_with_llm(content, language, client)
        prompt = "Analyze this #{language} source file. " \
                 "What classes, functions, methods, and imports does it define? " \
                 "What is its purpose?"
        messages = [{ role: "user", content: prompt }]
        client.chat(messages)
      rescue StandardError
        nil
      end
    end
  end
end
