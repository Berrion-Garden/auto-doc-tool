# frozen_string_literal: true

require "json"
require "fileutils"

module AutoDoc
  module Generator
    # Generates .map.json manifest files that inventory all generated documentation
    # artifacts. The map file serves as a machine-readable index of what was generated,
    # categorized by artifact type (indexes, summaries, vectors, diagrams, etc.).
    #
    # The map is the final step of documentation generation, written after everything
    # else is in place. It enables tools (CLI, server, frontend) to discover what
    # documentation artifacts exist without re-scanning the filesystem.
    class MapGenerator
      MAP_FILENAME = ".map.json"
      SCHEMA_VERSION = 1

      CATEGORIES = {
        agents_docs:  ->(rel_path) { rel_path.end_with?("AGENTS.md") },
        indexes:      ->(rel_path) { rel_path.end_with?("INDEX.md") },
        summaries:    ->(rel_path) { rel_path.end_with?("SUMMARY.md") },
        readme:       ->(rel_path) { rel_path.end_with?("README.md") },
        vectors:      ->(rel_path) { rel_path.match?(/vectors\.json$/i) },
        diagrams:     ->(rel_path) { rel_path.include?("diagrams/") && rel_path.end_with?(".mmd") },
        architecture: ->(rel_path) { rel_path.end_with?("architecture.md") },
        schema:       ->(rel_path) { rel_path.include?("schema/") && rel_path.end_with?(".json") },
        audit:        ->(rel_path) { rel_path.end_with?("report.json") }
      }.freeze

      # Generates the .map.json manifest.
      #
      # @param project_dir [String] Absolute path to the project root
      # @param output_dir [String] Output directory name (relative to project_dir)
      # @param project_name [String] Name of the project
      # @param coverage_pct [Integer, nil] Documentation coverage percentage
      # @param total_symbols [Integer, nil] Total number of documented symbols
      # @param output_path [String, nil] Custom output path (defaults to output_dir/.map.json)
      # @return [Hash] The map data hash
      def self.generate(project_dir, output_dir, project_name, coverage_pct: nil, total_symbols: nil, output_path: nil)
        new(project_dir, output_dir, project_name, coverage_pct: coverage_pct, total_symbols: total_symbols).generate(output_path)
      end

      def initialize(project_dir, output_dir, project_name, coverage_pct: nil, total_symbols: nil)
        @project_dir   = File.expand_path(project_dir)
        @output_dir    = output_dir
        @project_name  = project_name
        @coverage_pct  = coverage_pct
        @total_symbols = total_symbols
      end

      # Generates the map data and writes it to disk.
      # @param output_path [String, nil] Custom output path
      # @return [Hash] The map data hash
      def generate(output_path = nil)
        map_data = build_map_data
        map_data[:total_symbols] ||= count_symbols_from_vectors

        path = output_path || File.join(@project_dir, @output_dir, MAP_FILENAME)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(map_data))

        map_data
      end

      private

      # Builds the complete map data hash by walking the output directory.
      # @return [Hash] Map data with schema_version, generated_at, project, artifacts, etc.
      def build_map_data
        artifacts = inventory_files
        module_roots = discover_module_roots

        {
          schema_version: SCHEMA_VERSION,
          generated_at: Time.now.utc.iso8601,
          project: @project_name,
          artifacts: artifacts,
          module_roots: module_roots,
          coverage_pct: @coverage_pct,
          total_symbols: @total_symbols
        }
      end

      # Walks the output directory and categorizes every generated file.
      # Returns a hash where keys are category symbols and values are arrays of
      # relative file paths (relative to the output directory).
      # @return [Hash<Symbol, Array<String>>]
      def inventory_files
        output_abs = File.join(@project_dir, @output_dir)
        return default_empty_artifacts unless File.directory?(output_abs)

        artifacts = default_empty_artifacts

        Dir.glob(File.join(output_abs, "**", "*")).sort.each do |abs_path|
          next unless File.file?(abs_path)

          rel_path = abs_path.sub("#{output_abs}/", "")
          category = classify_file(rel_path)
          artifacts[category] << rel_path if category
        end

        artifacts
      end

      # Determines the category for a relative file path.
      # Returns the category symbol or nil if the file should be excluded.
      # @param rel_path [String] Relative path within the output directory
      # @return [Symbol, nil]
      def classify_file(rel_path)
        CATEGORIES.each do |category, matcher|
          return category if matcher.call(rel_path)
        end
        nil # uncategorized file, excluded from map
      end

      # Discovers module roots by looking for directories that contain AGENTS.md files.
      # @return [Array<String>] Module root directory names (relative to output_dir)
      def discover_module_roots
        output_abs = File.join(@project_dir, @output_dir)
        return [] unless File.directory?(output_abs)

        roots = []
        Dir.glob(File.join(output_abs, "*", "AGENTS.md")).each do |agents_path|
          dir_name = File.basename(File.dirname(agents_path))
          roots << dir_name
        end
        roots.sort
      end

      # Counts symbols from the project-level VECTORS.json or vectors.json file.
      # Falls back to directory-level vectors.json files if project-level doesn't exist.
      # @return [Integer] Number of symbols found, or 0
      def count_symbols_from_vectors
        output_abs = File.join(@project_dir, @output_dir)

        # Try project-level vectors file
        project_vectors = Dir.glob(File.join(output_abs, "vectors.json")).first
        if project_vectors && File.exist?(project_vectors)
          data = JSON.parse(File.read(project_vectors))
          symbols = data.is_a?(Hash) ? (data["symbols"] || []) : []
          return symbols.size
        end

        # Fall back to directory-level vectors files
        total = 0
        Dir.glob(File.join(output_abs, "**", "vectors.json")).each do |vf|
          data = JSON.parse(File.read(vf))
          symbols = data.is_a?(Hash) ? (data["symbols"] || []) : []
          total += symbols.size
        end
        total
      rescue JSON::ParserError
        0
      end

      # Returns the default empty artifacts hash with all categories initialized to [].
      # @return [Hash<Symbol, Array>]
      def default_empty_artifacts
        {
          indexes: [],
          summaries: [],
          readme: [],
          vectors: [],
          diagrams: [],
          agents_docs: [],
          architecture: [],
          schema: [],
          audit: []
        }
      end
    end
  end
end
