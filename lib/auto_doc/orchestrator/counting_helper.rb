# frozen_string_literal: true

module AutoDoc
  class Orchestrator
    module CountingHelper
      def count_classes_and_methods(analyses)
        cls_count    = 0
        method_count = 0

        analyses.each_value do |analysis|
          defs = analysis[:definitions] || []
          cls_count += defs.count { |d| d.is_a?(Hash) && (d[:type] == :class || d[:type] == :module) }
          defs.each do |defn|
            methods_list = defn.is_a?(Hash) ? (defn[:methods] || []) : []
            method_count += methods_list.size
          end
        end

        [cls_count, method_count]
      end

      def calculate_coverage(analyses)
        report = AutoDoc::Reporter::CompletenessChecker.check(analyses.map { |fp, a|
          [fp, { symbols: (a[:definitions] || []).map(&:to_h) }]
        }.to_h)
        report[:coverage_pct].to_s
      end
    end
  end
end
