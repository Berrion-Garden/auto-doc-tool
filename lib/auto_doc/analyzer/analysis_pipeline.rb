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
      # Analyzes a list of files and returns structured analysis data.
      # Uses SourceParser for Ruby files and falls back to GenericScanner
      # for non-Ruby files.
      #
      # @param file_list [Array<String>] Absolute file paths to analyze
      # @return [Hash<String, Hash>] Analysis data: { file_path => { definitions:, docs:, scanner:, language: } }
      def self.run(file_list)
        analyses = {}

        file_list.each do |file_path|
          next unless File.exist?(file_path)

          # Detect language early so it can be reused downstream.
          # Read only the first 1024 bytes for shebang detection (avoids I/O on large files).
          first_lines = File.read(file_path, 1024, encoding: "UTF-8") rescue nil
          language = AutoDoc::Analyzer::GenericScanner.detect_language(file_path, first_lines)

          definitions = AutoDoc::Analyzer::SourceParser.parse_file(file_path)
          scanner = :ripper

          if definitions.empty?
            definitions = AutoDoc::Analyzer::GenericScanner.parse_file(file_path)
            scanner = :generic unless definitions.empty?
          end

          docs = AutoDoc::Analyzer::YardReader.extract(file_path)

          # Build lookup index: key = :"class_Foo" / :"module_Bar" / :"method_baz"
          # Only merge docs when there are actual doc records
          unless docs.empty?
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
          end

          analyses[file_path] = {
            definitions: definitions,
            docs: docs,
            scanner: scanner,
            language: language
          }
        end

        analyses
      end
    end
  end
end
