# frozen_string_literal: true

module AutoDoc
  module Transformer
    # Extracts graph nodes and edges from import analyses for diagram generation.
    # Nodes are all definitions (class/module/method/constant); edges are project-file
    # import/require dependencies (stdlib and gem requires are filtered out).
    class GraphDataBuilder
      # Stdlib and common gem names that should be filtered from edges.
      # These are single-word identifiers without "/" that do not resolve to project files.
      STD_LIBRARY_PATTERN = %r{\A[a-z][a-z0-9_]*\z}.freeze

      # @param analyses [Hash<String, Hash>] Full analysis data
      # @return [Array] Array of [nodes, edges] where nodes is a sorted array of unique
      #   definition names (class, module, method, constant) and edges is an array of
      #   { from:, to:, type: } hashes. Edges only include requires that resolve to
      #   project files (stdlib/gem requires are filtered out).
      def self.build(analyses)
        return [[], []] unless analyses.is_a?(Hash)

        nodes = []
        edges = []

        analyses.each do |file_path, analysis|
          next unless analysis.is_a?(Hash)

          rel_file = file_path.sub(%r{^.*/}, "")
          file_dir = File.dirname(file_path)

          # Collect ALL definition types as nodes (class, module, method, constant)
          defs = (analysis[:definitions] || analysis["definitions"] || []).select do |d|
            d.is_a?(Hash) && (d[:name] || d["name"])
          end

          defs.each do |d|
            nodes << (d[:name] || d["name"])
          end

          imports = analysis[:imports] || analysis["imports"] || []
          imports.each do |imp|
            next unless imp.is_a?(Hash)
            imp_path = imp[:path] || imp["path"]
            imp_type = imp[:type] || imp["type"]
            next unless imp_path

            # Skip stdlib/gem requires: single-word identifiers that look like
            # stdlib names (no "/" and matches lowercase pattern)
            next if imp_type.to_s == "require" && imp_path.to_s.match?(STD_LIBRARY_PATTERN)

            # Resolve require_relative paths: if the path contains "/" or starts with ".",
            # resolve it relative to the source file's directory
            resolved = if imp_path.to_s.include?("/") || imp_path.to_s.start_with?(".")
                         resolve_require_path(imp_path, file_dir)
                       else
                         imp_path
                       end

            edges << { from: rel_file, to: resolved, type: imp_type.to_s }
          end
        end

        [nodes.uniq.sort, edges]
      end

      private_class_method def self.resolve_require_path(imp_path, file_dir)
        # Normalize the path — remove .rb suffix for resolution since require doesn't include it
        normalized = imp_path.to_s
        normalized = normalized.sub(%r{\A\./}, "") # strip leading ./
        normalized = normalized.sub(/\.rb\z/, "") # strip .rb suffix for require resolution

        resolved = File.join(file_dir, normalized)
        # Return the basename with .rb extension for consistency
        File.basename(resolved)
      end
    end
  end
end
