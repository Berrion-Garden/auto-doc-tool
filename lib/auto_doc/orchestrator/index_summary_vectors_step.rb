# frozen_string_literal: true

require "pathname"

module AutoDoc
  class Orchestrator
    class IndexSummaryVectorsStep < BaseStep
      def run(context)
        target_dir   = context[:target_dir]
        output_dir   = context[:output_dir]
        config       = context[:config]
        module_roots = context[:module_roots]
        analyses     = context[:analyses]

        # Collect LLM symbol summaries if LLM is available
        llm_summaries = collect_symbol_summaries(analyses, module_roots, config)

        # Per-directory INDEX.md, SUMMARY.md, vectors.json
        module_roots.each do |root|
          walk_subdirectories(context, root, analyses, target_dir, output_dir, config, llm_summaries: llm_summaries)
        end

        # Project-level INDEX.md, SUMMARY.md, VECTORS.json
        project_name = File.basename(target_dir)

        project_index_path = File.join(target_dir, output_dir, "INDEX.md")
        AutoDoc::Generator::IndexGenerator.generate(project_name, analyses, config, output_path: project_index_path)
        say(context, "  Created #{project_index_path}", :green)

        project_summary_path = File.join(target_dir, output_dir, "SUMMARY.md")
        AutoDoc::Generator::SummaryGenerator.generate(project_name, analyses, config, output_path: project_summary_path)
        say(context, "  Created #{project_summary_path}", :green)

        project_vectors_path = File.join(target_dir, output_dir, "VECTORS.json")
        vectors_data = AutoDoc::Generator::VectorGenerator.generate_project(analyses, config, llm_summaries: llm_summaries)
        AutoDoc::Generator::VectorGenerator.write(project_vectors_path, vectors_data)
        say(context, "  Created #{project_vectors_path}", :green)

        context
      end

      private

      def collect_symbol_summaries(analyses, module_roots, config)
        return nil unless config.respond_to?(:llm_primary?) && config.llm_primary?

        client = AutoDoc::LLM::Client.build_if_configured(config)
        return nil unless client

        llm_summaries = {}

        # Build a lookup of symbol_name => type from analyses
        symbol_types = {}
        analyses.each_value do |analysis|
          (analysis[:definitions] || []).each do |defn|
            next unless defn.is_a?(Hash)
            symbol_types[defn[:name].to_s] = defn[:type].to_s.downcase
          end
        end

        module_roots.each do |root|
          base_name = File.basename(root)
          root_analyses = analyses.select { |fp, _| fp.start_with?("#{root}/") }
          next if root_analyses.empty?

          response = AutoDoc::LLM::Summarizer.summarize_symbols(base_name, root_analyses, client)
          next unless response.is_a?(String) && !response.empty?

          llm_summaries.merge!(AutoDoc::LLM::ResponseParser.parse_symbol_summaries(response, symbol_types))
        end

        llm_summaries.empty? ? nil : llm_summaries
      end

      def walk_subdirectories(context, root, analyses, target_dir, output_dir, config, llm_summaries: nil)
        dirs_to_process = [root]
        dirs_to_process.reject! { |d| d == context[:target_dir] }

        Dir.glob(File.join(root, "**", "*")).select { |e| File.directory?(e) }.each do |subdir|
          dirs_to_process << subdir
        end

        dirs_to_process.each do |dir|
          ruby_files = Dir.glob(File.join(dir, "*.rb"))
          next if ruby_files.empty?

          display_name = File.basename(dir)
          output_rel   = Pathname.new(dir).relative_path_from(Pathname.new(root)).to_s

          if output_rel == "."
            display_name = File.basename(root)
            output_rel   = display_name
          end

          dir_analyses = analyses.select { |fp, _| fp.start_with?("#{dir}/") }
          next if dir_analyses.empty?

          # INDEX.md
          index_path = File.join(target_dir, output_dir, output_rel, "INDEX.md")
          AutoDoc::Generator::IndexGenerator.generate(display_name, dir_analyses, config, output_path: index_path)
          say(context, "  Created #{index_path}", :green)

          # SUMMARY.md
          summary_path = File.join(target_dir, output_dir, output_rel, "SUMMARY.md")
          AutoDoc::Generator::SummaryGenerator.generate(display_name, dir_analyses, config, output_path: summary_path)
          say(context, "  Created #{summary_path}", :green)

          # vectors.json — skip root to avoid duplicating project-level VECTORS.json
          next if dir == root

          vectors_data = AutoDoc::Generator::VectorGenerator.generate_directory(display_name, dir_analyses, config, llm_summaries: llm_summaries)
          vectors_path = File.join(target_dir, output_dir, output_rel, "vectors.json")
          AutoDoc::Generator::VectorGenerator.write(vectors_path, vectors_data)
          say(context, "  Created #{vectors_path}", :green)
        end
      end
    end
  end
end
