# frozen_string_literal: true

module AutoDoc
  class Orchestrator
    class BaseStep
      def run(context)
        raise NotImplementedError, "#{self.class} must implement #run"
      end

      protected

      def say(context, msg, color = nil)
        context[:say]&.call(msg, color)
      end

      # Collects pre-enriched symbol summaries from analyses[:docs].
      # By the time this runs, the Enricher has already called
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
