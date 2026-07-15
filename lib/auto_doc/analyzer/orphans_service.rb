# frozen_string_literal: true

require "set"

module AutoDoc
  module Analyzer
    # Finds Ruby files that are not documented, not imported by any other file,
    # and not referenced by any other file in the project.
    class OrphansService
      # Runs the orphan detection analysis.
      # @param project_dir [String] Root directory of the project
      # @param options [Hash] Options hash
      # @option options [Boolean] :rails When true, skip Rails autoloaded paths if project is a Rails app
      # @param say [Proc] Callable for output messages (default: puts)
      # @return [Hash] Result with :orphans array and :by_directory breakdown
      def self.run(project_dir, options: {}, say: method(:puts))
        new(project_dir, options: options, say: say).run
      end

      def initialize(project_dir, options: {}, say: method(:puts))
        @project_dir = project_dir
        @options     = options
        @say         = say
      end

      def run
        @say.call("Scanning for orphan files in #{@project_dir}...", :green)

        ruby_files = collect_ruby_files
        if ruby_files.empty?
          @say.call("No Ruby files found.", :yellow)
          return { orphans: [], by_directory: {} }
        end

        @say.call("  Found #{ruby_files.size} Ruby file(s)", :green)

        # Apply Rails autoload filtering if requested
        ruby_files = filter_rails_autoloaded(ruby_files) if rails_mode?

        # Determine which files import which other files
        import_map = build_import_map(ruby_files)

        # Files that are imported/referenced by at least one other file
        referenced = build_referenced_set(import_map)

        # Files that are not documented (no YARD doc on their primary class/module)
        documented = build_documented_set(ruby_files)

        # Orphans: not referenced AND not documented
        orphans = ruby_files.reject { |f| referenced.include?(f) || documented.include?(f) }

        # Compute directory breakdown from orphans
        by_directory = compute_directory_breakdown(orphans)

        { orphans: orphans.sort, by_directory: by_directory }
      end

      # Detects whether the project is a Rails project by checking for
      # config/application.rb containing 'Rails::Application'.
      def rails_project?
        app_path = File.join(@project_dir, "config", "application.rb")
        File.exist?(app_path) && File.read(app_path).include?("Rails::Application")
      end

      # Returns true if Rails mode is active: the user opted in AND the project
      # actually is a Rails project.
      def rails_mode?
        @options[:rails] && rails_project?
      end

      # Autoloaded paths that Zeitwerk manages in a typical Rails application.
      RAILS_AUTOLOAD_PATHS = %w[
        app/models
        app/controllers
        app/serializers
        app/jobs
        app/mailers
        app/helpers
        app/services
        app/controllers/concerns
        app/models/concerns
      ].freeze

      # Removes files under Rails autoloaded paths from the file list.
      def filter_rails_autoloaded(files)
        files.reject do |f|
          relative = f.sub("#{@project_dir}/", "")
          RAILS_AUTOLOAD_PATHS.any? { |dir| relative.start_with?("#{dir}/") }
        end
      end

      # Groups a list of orphan files by their top-level directory
      # (e.g. 'lib', 'bin') relative to the project root.
      # @return [Hash] e.g. { "lib" => 2, "bin" => 1 }
      def compute_directory_breakdown(orphans)
        breakdown = Hash.new(0)
        orphans.each do |f|
          relative = f.sub("#{@project_dir}/", "")
          top_dir = relative.split("/").first
          breakdown[top_dir] += 1 if top_dir
        end
        breakdown
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
