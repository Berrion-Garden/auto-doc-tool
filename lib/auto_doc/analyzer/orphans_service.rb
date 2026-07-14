# frozen_string_literal: true

require "set"

module AutoDoc
  module Analyzer
    # Finds Ruby files that are not documented, not imported by any other file,
    # and not referenced by any other file in the project.
    class OrphansService
      # Runs the orphan detection analysis.
      # @param project_dir [String] Root directory of the project
      # @param say [Proc] Callable for output messages (default: puts)
      # @return [Hash] Result with :orphans array of relative file paths
      def self.run(project_dir, say: method(:puts))
        new(project_dir, say: say).run
      end

      def initialize(project_dir, say: method(:puts))
        @project_dir = project_dir
        @say         = say
      end

      def run
        @say.call("Scanning for orphan files in #{@project_dir}...", :green)

        ruby_files = collect_ruby_files
        if ruby_files.empty?
          @say.call("No Ruby files found.", :yellow)
          return { orphans: [] }
        end

        @say.call("  Found #{ruby_files.size} Ruby file(s)", :green)

        # Determine which files import which other files
        import_map = build_import_map(ruby_files)

        # Files that are imported/referenced by at least one other file
        referenced = build_referenced_set(import_map)

        # Files that are not documented (no YARD doc on their primary class/module)
        documented = build_documented_set(ruby_files)

        # Orphans: not referenced AND not documented
        orphans = ruby_files.reject { |f| referenced.include?(f) || documented.include?(f) }

        { orphans: orphans.sort }
      end

      private

      def collect_ruby_files
        config = AutoDoc::Config.load(@project_dir)
        excludes = config.exclude_patterns || []

        Dir.glob(File.join(@project_dir, "**", "*.rb")).reject do |f|
          relative = f.sub("#{@project_dir}/", "")
          excludes.any? { |pat| File.fnmatch?(pat, relative, File::FNM_PATHNAME) }
        end
      end

      def build_import_map(ruby_files)
        import_map = {}
        ruby_files.each do |file_path|
          imports = AutoDoc::Analyzer::ImportExtractor.extract(file_path)
          import_map[file_path] = imports
        end
        import_map
      end

      def build_referenced_set(import_map)
        referenced = Set.new
        import_map.each_value do |imports|
          imports.each do |imp|
            target = imp[:path]
            referenced.add(target) if target
          end
        end
        referenced
      end

      def build_documented_set(ruby_files)
        documented = Set.new
        ruby_files.each do |file_path|
          docs = AutoDoc::Analyzer::YardReader.extract(file_path)
          documented.add(file_path) if docs.any? { |d| d[:has_summary?] }
        end
        documented
      end
    end
  end
end
