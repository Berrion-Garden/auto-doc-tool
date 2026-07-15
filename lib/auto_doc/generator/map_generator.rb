# frozen_string_literal: true

require "json"
require "fileutils"

module AutoDoc
  module Generator
    # Generates .map.json — a master manifest of all generated documentation artifacts.
    # Provides a single entry point for agents and tools to discover what's available.
    class MapGenerator
      # Generates the .map.json manifest for a project.
      # @param project_dir [String] Project root directory
      # @param output_dir [String] Output directory name (e.g., ".docs")
      # @param config [AutoDoc::Config] Configuration object
      # @param analyses [Hash] Analysis data from orchestrator
      # @param extra [Hash] Extra data: schema_tables, models, coverage_pct, etc.
      # @return [Hash] The manifest data (also written to disk)
      def self.generate(project_dir, output_dir, config, analyses, extra = {})
        full_output = File.join(project_dir, output_dir)
        artifacts = {
          indexes: [],
          summaries: [],
          vectors: [],
          diagrams: [],
          agents_docs: [],
          architecture: [],
          schema: [],
          readme: []
        }

        # Walk the full output directory
        if File.directory?(full_output)
          Dir.glob(File.join(full_output, "**", "*")).each do |path|
            next unless File.file?(path)
            rel = Pathname.new(path).relative_path_from(Pathname.new(full_output)).to_s
            basename = File.basename(path)
            case basename
            when "README.md" then artifacts[:readme] << rel
            when "INDEX.md" then artifacts[:indexes] << rel
            when "SUMMARY.md" then artifacts[:summaries] << rel
            when "VECTORS.json", "vectors.json" then artifacts[:vectors] << rel
            when /\.mmd\z/ then artifacts[:diagrams] << rel
            when "AGENTS.md" then artifacts[:agents_docs] << rel
            when "architecture.md" then artifacts[:architecture] << rel
            when "schema.json", "models.json" then artifacts[:schema] << rel
            end
          end
        end

        manifest = {
          schema_version: "1.0",
          generated_at: Time.now.iso8601,
          project: File.basename(project_dir),
          artifacts: artifacts,
          module_roots: (config.module_roots || []),
          coverage_pct: (extra[:coverage_pct] || 0).to_f,
          total_symbols: (extra[:total_symbols] || 0),
          total_files: analyses.size
        }

        manifest_path = File.join(full_output, ".map.json")
        FileUtils.mkdir_p(File.dirname(manifest_path))
        File.write(manifest_path, JSON.pretty_generate(manifest))

        manifest
      end
    end
  end
end
