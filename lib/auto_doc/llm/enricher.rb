# frozen_string_literal: true

module AutoDoc
  module LLM
    # Enriches analysis data with LLM-generated symbol summaries.
    # Groups analyses by module root, calls the LLM per module,
    # and appends generated summaries to each file's docs array.
    class Enricher
      class << self
        # Enriches analyses with LLM-generated symbol summaries.
        #
        # @param analyses [Hash] Analysis data: { file_path => { definitions:, docs: } }
        # @param config   [Config] Configuration object responding to llm_primary? and module_roots
        # @return [Hash] The (potentially modified) analyses hash
        def enrich_analyses(analyses, config)
          # Guard: only run when LLM is primary and configured
          return analyses unless config.llm_primary?

          client = Client.build_if_configured(config)
          return analyses unless client

          # Build a lookup of symbol_name => type from all analyses
          symbol_types = {}
          analyses.each_value do |analysis|
            (analysis[:definitions] || []).each do |defn|
              next unless defn.is_a?(Hash)
              symbol_types[defn[:name].to_s] = defn[:type].to_s.downcase
            end
          end

          # Group files by module root and call LLM per module
          config.module_roots.each do |root|
            root_analyses = analyses.select { |fp, _| fp.include?("/#{root}/") }
            next if root_analyses.empty?

            response = Summarizer.summarize_symbols(root, root_analyses, client)

            if response.nil?
              $stderr.puts "[AutoDoc] Enricher: LLM returned nil for module '#{root}'"
              next
            end

            parsed = ResponseParser.parse_symbol_summaries(response, symbol_types)
            next if parsed.empty?

            # Append summaries to each file's docs array
            root_analyses.each do |_file_path, analysis|
              (analysis[:definitions] || []).each do |defn|
                next unless defn.is_a?(Hash)
                entry_id = "#{defn[:type].to_s.downcase}_#{defn[:name].to_s.gsub('::', '_')}"
                summary_text = parsed[entry_id]
                next unless summary_text

                analysis[:docs] << {
                  target_name: defn[:name].to_s,
                  target_type: defn[:type].to_s.downcase,
                  summary: summary_text
                }
              end
            end
          end

          analyses
        end
      end
    end
  end
end
