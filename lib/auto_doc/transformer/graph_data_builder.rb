# frozen_string_literal: true

module AutoDoc
  module Transformer
    # Extracts graph nodes and edges from import analyses for diagram generation.
    # Nodes are unique class/module names; edges are import/require dependencies.
    class GraphDataBuilder
      # @param analyses [Hash<String, Hash>] Full analysis data
      # @return [Array] Array of [nodes, edges] where nodes is a sorted array of unique class/module names
      #   and edges is an array of { from:, to:, type: } hashes
      def self.build(analyses)
        nodes = []
        edges = []

        analyses.each do |file_path, analysis|
          rel_file = file_path.sub(%r{^.*/}, "")
          defs = (analysis[:definitions] || []).select { |d| d.is_a?(Hash) && (d[:type] == :class || d[:type] == :module) }
          defs.each { |d| nodes << d[:name] if d[:name] }

          imports = analysis[:imports] || []
          imports.each do |imp|
            edges << { from: rel_file, to: imp[:path], type: imp[:type].to_s }
          end
        end

        [nodes.uniq.sort, edges]
      end
    end
  end
end
