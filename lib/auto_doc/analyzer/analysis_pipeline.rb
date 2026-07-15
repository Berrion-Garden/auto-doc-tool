# frozen_string_literal: true

module AutoDoc
  module Analyzer
    # Shared pipeline for analyzing Ruby files. Handles the common pattern of
    # file iteration -> SourceParser.parse_file + YardReader.extract -> doc
    # presence merge that is duplicated across Orchestrator and DiffService.
    #
    # Import extraction is NOT included here — it is orchestrator-only and
    # handled separately by the caller.
    class AnalysisPipeline
      # Analyzes a list of Ruby files and returns structured analysis data.
      #
      # @param file_list [Array<String>] Absolute file paths to analyze
      # @return [Hash<String, Hash>] Analysis data: { file_path => { definitions:, docs: } }
      def self.run(file_list)
        analyses = {}

        file_list.each do |file_path|
          next unless File.exist?(file_path)

          definitions = AutoDoc::Analyzer::SourceParser.parse_file(file_path)
          docs        = AutoDoc::Analyzer::YardReader.extract(file_path)

          # Build lookup index: key = :"class_Foo" / :"module_Bar" / :"method_baz"
          doc_index = docs.each_with_object({}) do |d, h|
            key_name = d[:target_name].to_s.gsub("::", "_")
            h[:"#{d[:target_type]}_#{key_name}"] = d
          end

          # Merge documentation presence into each definition.
          definitions.each do |defn|
            def_name = defn[:name].to_s.gsub("::", "_")
            key      = :"#{defn[:type]}_#{def_name}"
            doc_rec  = doc_index[key]
            defn[:has_doc?] = doc_rec && doc_rec[:has_summary?] == true
          end

          analyses[file_path] = { definitions: definitions, docs: docs }
        end

        analyses
      end
    end
  end
end
