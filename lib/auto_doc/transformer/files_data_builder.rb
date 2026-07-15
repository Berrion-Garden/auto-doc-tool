# frozen_string_literal: true

module AutoDoc
  module Transformer
    # Converts raw file analyses into the structure expected by AgentsMdGenerator.
    # Builds a sorted array of file records with name, path, classes, and imports.
    class FilesDataBuilder
      # @param analyses [Hash<String, Hash>] Analysis data: { file_path => { definitions:, imports: } }
      # @return [Array<Hash>] Sorted array of file records
      def self.build(analyses)
        files = []
        analyses.each do |file_path, analysis|
          files << {
            name:    File.basename(file_path),
            path:    file_path,
            classes: analysis[:definitions] || [],
            imports: analysis[:imports] || []
          }
        end
        files.sort_by! { |f| f[:name].downcase }
        files
      end
    end
  end
end
