# frozen_string_literal: true

require "erb"
require "fileutils"

module AutoDoc
  module Generator
    # Generates INDEX.md documentation for a Ruby directory.
    # Renders templates/index_template.erb with analysis data including
    # files table, symbols table, dependencies, and cross-references.
    class IndexGenerator
      include TemplateHelper

      TEMPLATES_DIR = File.expand_path("../../../templates", __dir__).freeze

      DEFAULT_TEMPLATE = File.join(TEMPLATES_DIR, "index_template.erb").freeze

      # Generates an INDEX.md file for the given directory.
      # @param dir_name [String] Name of the directory
      # @param analyses [Hash<String, Hash>] Analysis data: { file_path => { definitions:, imports:, docs: } }
      # @param config [AutoDoc::Config] Configuration object
      # @param output_path [String] Where to write INDEX.md (default: nil)
      # @return [String] Generated markdown content
      def self.generate(dir_name, analyses, config, output_path: nil)
        new(dir_name, analyses, config).generate(output_path)
      end

      def initialize(dir_name, analyses, config)
        @dir_name = dir_name
        @analyses = analyses
        @config   = config
      end

      # Generates markdown and optionally writes to disk.
      # @param output_path [String, nil] File path or nil to return string only
      # @return [String] Rendered markdown content
      def generate(output_path = nil)
        rendered = render_template

        if output_path
          FileUtils.mkdir_p(File.dirname(output_path))
          File.write(output_path, rendered)
        end

        rendered
      end

      private

      def render_template
        template_path = ENV.fetch("AUTO_DOC_TEMPLATE_INDEX", DEFAULT_TEMPLATE)
        template_text = read_template(template_path)

        dir_name   = @dir_name
        files      = build_files_table
        symbols    = build_symbols_table
        dependencies = build_dependencies
        cross_references = build_cross_references
        coverage_pct = calculate_coverage
        generated_at = Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")

        ERB.new(template_text).result(binding)
      end

      # Builds the files table rows from analysis data.
      # @return [Array<Hash>] Array of file records with :name, :classes, :modules, :methods, :documented
      def build_files_table
        files = []
        @analyses.each do |file_path, analysis|
          defs = analysis[:definitions] || []
          classes   = defs.count { |d| d.is_a?(Hash) && d[:type] == :class }
          modules   = defs.count { |d| d.is_a?(Hash) && d[:type] == :module }
          methods_count = 0
          documented = false

          defs.each do |defn|
            next unless defn.is_a?(Hash)
            methods_list = defn[:methods] || []
            methods_count += methods_list.size
            documented = true if defn[:has_doc?] == true
          end

          files << {
            name:       File.basename(file_path),
            classes:    classes,
            modules:    modules,
            methods:    methods_count,
            documented: documented
          }
        end
        files.sort_by! { |f| f[:name].downcase }
      end

      # Builds the symbols table from analysis data, mirroring AgentsMdGenerator#build_public_symbols.
      # @return [Array<Hash>] Array of symbol records with :name, :type, :file, :line, :doc
      def build_symbols_table
        symbols = []
        @analyses.each do |file_path, analysis|
          file_name = File.basename(file_path)
          defs = analysis[:definitions] || []
          defs.each do |defn|
            next unless defn.is_a?(Hash)
            type = defn[:type].to_s.downcase
            next unless [:class, :module, :method].include?(defn[:type])

            symbols << {
              name: defn[:name],
              type: type,
              file: file_name,
              line: defn[:line] || 0,
              doc:  (defn[:has_doc?] == true)
            }
          end
        end
        symbols.sort_by! { |s| s[:name].to_s.downcase }
      end

      # Builds dependencies list from import data.
      # @return [Array<Hash>] Array of dependency records with :from, :type, :to
      def build_dependencies
        deps = []
        @analyses.each do |file_path, analysis|
          file_name = File.basename(file_path)
          imports = analysis[:imports] || []
          imports.each do |imp|
            deps << {
              from: file_name,
              type: imp[:type].to_s,
              to:   imp[:path]
            }
          end
        end
        deps.uniq!
        deps.sort_by! { |d| [d[:from].downcase, d[:to].downcase] }
        deps
      end

      # Builds cross-references hash for parent and sibling directories.
      # @return [Hash] Cross-reference data with :parent and :siblings keys
      def build_cross_references
        return {} if @analyses.empty?

        refs = {}

        # Determine parent directory from the first analysis file path
        first_path = @analyses.keys.first
        if first_path
          parent_dir = File.dirname(first_path)
          parent_name = File.basename(parent_dir)
          refs[:parent] = { name: parent_name, path: "../#{parent_name}/INDEX.md" }
        end

        # Siblings are other directories at the same level
        siblings = []
        seen = {}
        @analyses.each_key do |fp|
          dir = File.dirname(fp)
          Dir.glob(File.join(dir, "*")).each do |entry|
            next unless File.directory?(entry)
            sib_name = File.basename(entry)
            next if sib_name == @dir_name || seen[sib_name]
            seen[sib_name] = true
            siblings << { name: sib_name, path: "../#{sib_name}/INDEX.md" }
          end
        end
        refs[:siblings] = siblings.sort_by { |s| s[:name].downcase } if siblings.any?

        refs
      end

      # Calculates documentation coverage percentage for the directory's symbols.
      # @return [Integer] Coverage percentage (0-100)
      def calculate_coverage
        total   = 0
        covered = 0

        @analyses.each_value do |analysis|
          defs = analysis[:definitions] || []
          defs.each do |defn|
            next unless defn.is_a?(Hash)
            next unless [:class, :module, :method].include?(defn[:type])
            total += 1
            covered += 1 if defn[:has_doc?] == true
          end
        end

        return 0 if total.zero?
        ((covered.to_f / total) * 100).round
      end

    end
  end
end
