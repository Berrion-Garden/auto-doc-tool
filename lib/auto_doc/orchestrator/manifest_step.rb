# frozen_string_literal: true

module AutoDoc
  class Orchestrator
    class ManifestStep < BaseStep
      include MetricsHelper

      def run(context)
        target_dir = context[:target_dir]
        output_dir = context[:output_dir]
        config     = context[:config]
        analyses   = context[:analyses]

        # Save manifest for incremental tracking
        ruby_files_list = Dir.glob(File.join(target_dir, "**", "*.rb")).reject do |f|
          relative = f.sub("#{target_dir}/", "")
          (config.exclude_patterns || []).any? { |pat| File.fnmatch?(pat, relative, File::FNM_PATHNAME) }
        end.map { |f| f.sub("#{target_dir}/", "") }
        AutoDoc::Utils::TimestampTracker.save_manifest(target_dir, ruby_files_list, output_dir)

        # Generate .map.json master manifest
        map_extra = {
          coverage_pct:  calculate_coverage(analyses),
          total_symbols: count_all_symbols(analyses)
        }
        AutoDoc::Generator::MapGenerator.generate(target_dir, output_dir, config, analyses, map_extra)
        say(context, "  Created #{File.join(target_dir, output_dir, '.map.json')}", :green)

        context
      end

      private

      def count_all_symbols(analyses)
        analyses.sum { |_, a| (a[:definitions] || []).size }
      end
    end
  end
end
