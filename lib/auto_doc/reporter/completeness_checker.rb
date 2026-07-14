# frozen_string_literal: true

module AutoDoc
  module Reporter
    # Checks documentation coverage of public symbols versus documented ones.
    # Used as a helper by AuditReporter to calculate coverage percentages.
    class CompletenessChecker
      # Checks doc coverage for a set of analysis results.
      # @param analyses [Hash<String, Hash>] Analysis data keyed by file path.
      #   Each value contains: { symbols: [{name:, type:, has_doc?:}, ...] }
      # @param threshold [Integer] Minimum acceptable coverage percentage (default 80)
      # @return [Hash] Coverage report with keys:
      #   :total - total public symbol count
      #   :documented - number of documented symbols
      #   :undocumented - array of undocumented symbol hashes {name:, type:, file:, line:}
      #   :coverage_pct - percentage rounded to one decimal place
      def self.check(analyses, threshold = 80)
        new(analyses).check(threshold)
      end

      def initialize(analyses)
        @analyses = analyses || {}
      end

      # @param threshold [Integer] Minimum acceptable coverage percentage
      # @return [Hash] Coverage report hash
      def check(threshold = 80)
        total        = 0
        documented   = 0
        undocumented = []

        @analyses.each do |file_path, analysis|
          symbols = extract_symbols(analysis)
          symbols.each do |sym|
            total += 1
            if symbol_documented?(sym)
              documented += 1
            else
              undocumented << {
                name: sym_name(sym),
                type: sym_type(sym),
                file: file_path,
                line: sym_line(sym)
              }
            end
          end
        end

        coverage_pct = total.zero? ? 100.0 : (documented.to_f / total * 100).round(1)

        {
          total:        total,
          documented:   documented,
          undocumented: undocumented,
          coverage_pct: coverage_pct
        }
      end

      private

      def extract_symbols(analysis)
        # Support both array-of-symbols and nested analysis formats
        if analysis.is_a?(Array)
          analysis
        elsif analysis.respond_to?(:keys) && analysis[:symbols]
          analysis[:symbols]
        elsif analysis.respond_to?(:keys) && analysis[:definitions]
          analysis[:definitions].map { |d| d.is_a?(Hash) ? d : d.to_h }
        else
          []
        end
      end

      def symbol_documented?(sym)
        sym = sym.to_h if sym.respond_to?(:to_h) && !sym.is_a?(Hash)
        sym[:has_doc?] || false
      rescue TypeError, ArgumentError
        false
      end

      def sym_name(sym)
        return sym[:name] if sym.is_a?(Hash)
        return sym.name if sym.respond_to?(:name)
        "unknown"
      end

      def sym_type(sym)
        return sym[:type] if sym.is_a?(Hash)
        return sym.type.to_s if sym.respond_to?(:type)
        "unknown"
      end

      def sym_line(sym)
        return sym[:line] || sym[:line_number] if sym.is_a?(Hash)
        return (sym.line || sym.line_number).to_i if sym.respond_to?(:line) || sym.respond_to?(:line_number)
        0
      end
    end
  end
end
