# frozen_string_literal: true

module AutoDoc
  class Orchestrator
    class AgentsMdStep < BaseStep
      def run(context)
        target_dir    = context[:target_dir]
        output_dir    = context[:output_dir]
        config        = context[:config]
        module_roots  = context[:module_roots]
        analyses      = context[:analyses]

        # Collect LLM symbol summaries from analyses[:docs] (populated by Enricher)
        llm_summaries = collect_symbol_summaries(analyses)

        module_roots.each do |root|
          dir_name   = File.basename(root)
          tree_text  = AutoDoc::Utils::FileTreeBuilder.build(root, config.exclude_patterns || [])

          file_analyses = analyses.select { |fp, _| fp.start_with?("#{root}/") }
          files_data    = AutoDoc::Transformer::FilesDataBuilder.build(file_analyses, llm_summaries)

          output_path = File.join(target_dir, output_dir, dir_name, "AGENTS.md")
          AutoDoc::Generator::AgentsMdGenerator.generate(dir_name, tree_text, files_data, config: config, output_path: output_path, llm_summaries: llm_summaries)

          say(context, "  Created #{output_path}", :green)
        end

        context
      end

      private

      # Collects pre-enriched symbol summaries from analyses[:docs].
      # By the time this step runs, the Enricher has already called
      # Summarizer.summarize_symbols and stored results in each analysis[:docs].
      #
      # @param analyses [Hash] Analysis data with docs arrays populated by Enricher
      # @return [Hash, nil] Map of entry_id => summary_text, or nil if empty
      def collect_symbol_summaries(analyses)
        llm_summaries = {}

        analyses.each_value do |analysis|
          (analysis[:docs] || []).each do |doc|
            next unless doc.is_a?(Hash)
            entry_id = "#{doc[:target_type]}_#{doc[:target_name].to_s.gsub('::', '_')}"
            llm_summaries[entry_id] = doc[:summary]
          end
        end

        llm_summaries.empty? ? nil : llm_summaries
      end
    end
  end
end
