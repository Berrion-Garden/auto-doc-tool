# frozen_string_literal: true

module AutoDoc
  module Transformer
    # Converts raw file analyses into the structure expected by AgentsMdGenerator.
    # Builds a sorted array of file records with name, path, classes, and imports.
    class FilesDataBuilder
      # @param analyses [Hash<String, Hash>] Analysis data: { file_path => { definitions:, imports: } }
      # @param llm_summaries [Hash, nil] Optional LLM summaries: { entry_id => summary_text }
      # @return [Array<Hash>] Sorted array of file records
      def self.build(analyses, llm_summaries = nil)
        files = []
        analyses.each do |file_path, analysis|
          definitions = (analysis[:definitions] || []).map do |defn|
            defn = defn.dup
            entry_id = "#{defn[:type]}_#{defn[:name].to_s.gsub('::', '_')}"
            defn[:llm_summary] = llm_summaries&.[](entry_id) if llm_summaries
            defn
          end
          files << {
            name:    File.basename(file_path),
            path:    file_path,
            classes: definitions,
            imports: analysis[:imports] || []
          }
        end
        files.sort_by! { |f| f[:name].downcase }
        files
      end
    end
  end
end
