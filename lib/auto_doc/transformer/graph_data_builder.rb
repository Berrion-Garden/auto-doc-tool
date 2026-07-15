# frozen_string_literal: true

# NOTE: If a 36-file Rails app produces zero nodes, the root cause is likely
# in SourceParser — Ripper.sexp may return nil for certain Ruby constructs or
# the file encoding may not be UTF-8. GraphDataBuilder is now defensive against
# nil analyses, string keys, and non-Hash entries.

module AutoDoc
  module Transformer
    # Extracts graph nodes and edges from import analyses for diagram generation.
    # Nodes are unique class/module names; edges are import/require dependencies.
    class GraphDataBuilder
      # @param analyses [Hash<String, Hash>] Full analysis data
      # @return [Array] Array of [nodes, edges] where nodes is a sorted array of unique class/module names
      #   and edges is an array of { from:, to:, type: } hashes
      def self.build(analyses)
        return [[], []] unless analyses.is_a?(Hash)

        nodes = []
        edges = []

        analyses.each do |file_path, analysis|
          next unless analysis.is_a?(Hash)

          rel_file = file_path.sub(%r{^.*/}, "")

          defs = (analysis[:definitions] || analysis["definitions"] || []).select do |d|
            d.is_a?(Hash) && (
              d[:type] == :class || d[:type] == :module ||
              d["type"] == "class" || d["type"] == "module"
            )
          end

          defs.each { |d| nodes << (d[:name] || d["name"]) if d[:name] || d["name"] }

          imports = analysis[:imports] || analysis["imports"] || []
          imports.each do |imp|
            next unless imp.is_a?(Hash)
            imp_path = imp[:path] || imp["path"]
            imp_type = imp[:type] || imp["type"]
            edges << { from: rel_file, to: imp_path, type: imp_type.to_s } if imp_path
          end
        end

        [nodes.uniq.sort, edges]
      end
    end
  end
end
