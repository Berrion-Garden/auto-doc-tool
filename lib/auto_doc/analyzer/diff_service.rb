# frozen_string_literal: true

module AutoDoc
  module Analyzer
    # Detects documentation drift by comparing current documentation state
    # against a git reference (commit, branch, tag).
    class DiffService
      # Runs the diff analysis between the current state and a git ref.
      # @param project_dir [String] Root directory of the project
      # @param since [String] Git ref to compare against (e.g., HEAD~1, main)
      # @param say [Proc] Callable for output messages (default: puts)
      # @return [Hash] Result with :changed_files and :undocumented_changes
      def self.run(project_dir, since, say: method(:puts))
        new(project_dir, since, say: say).run
      end

      def initialize(project_dir, since, say: method(:puts))
        @project_dir = project_dir
        @since       = since
        @say         = say
      end

      def run
        @say.call("Checking for undocumented changes since '#{@since}'...", :green)

        # Get changed Ruby files
        changed_files = git_changed_ruby_files
        return { changed_files: [], undocumented_changes: [] } if changed_files.empty?

        # Build current documentation state for changed files
        config     = AutoDoc::Config.load(@project_dir)
        analyses   = analyze_files(changed_files)

        undocumented = find_undocumented(analyses)

        {
          changed_files:      changed_files,
          undocumented_changes: undocumented
        }
      end

      private

      def git_changed_ruby_files
        `git diff --name-only #{@since} -- '*.rb'`.split("\n").map(&:strip).select do |f|
          File.exist?(File.join(@project_dir, f))
        end
      rescue => e
        @say.call("Warning: git diff failed: #{e.message}", :yellow)
        []
      end

      def analyze_files(file_list)
        analyses = {}
        excludes = config.exclude_patterns || []

        file_list.each do |relative_path|
          file_path = File.join(@project_dir, relative_path)
          next unless File.exist?(file_path)

          # Skip excluded patterns
          next if excludes.any? { |pat| File.fnmatch?(pat, relative_path, File::FNM_PATHNAME) }

          definitions = AutoDoc::Analyzer::SourceParser.parse_file(file_path)
          docs        = AutoDoc::Analyzer::YardReader.extract(file_path)

          # Build doc lookup index
          doc_index = docs.each_with_object({}) do |d, h|
            key_name = d[:target_name].to_s.gsub("::", "_")
            h[:"#{d[:target_type]}_#{key_name}"] = d
          end

          # Merge doc presence into definitions
          definitions.each do |defn|
            def_name = defn[:name].to_s.gsub("::", "_")
            key      = :"#{defn[:type]}_#{def_name}"
            doc_rec  = doc_index[key]
            defn[:has_doc?] = doc_rec && doc_rec[:has_summary?] == true
          end

          analyses[file_path] = { definitions: definitions, docs: docs }
        end

        analyses
      end

      def find_undocumented(analyses)
        undocumented = []
        analyses.each do |file_path, analysis|
          (analysis[:definitions] || []).each do |defn|
            next if defn[:has_doc?]

            undocumented << {
              type:   defn[:type].to_s,
              symbol: defn[:name],
              file:   file_path
            }
          end
        end
        undocumented
      end

      def config
        @config ||= AutoDoc::Config.load(@project_dir)
      end
    end
  end
end
