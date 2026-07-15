# frozen_string_literal: true

module AutoDoc
  module Analyzer
    # In-process analysis cache to prevent redundant re-analysis of the same project.
    # Keyed by (project_dir + config fingerprint) — survives for the lifetime of the process.
    #
    # Usage:
    #   analyses = AnalysisCache.fetch(project_dir, config) do
    #     AnalysisPipeline.run(ruby_files)
    #   end
    #
    # The cache is invalidated when:
    #   - A different project_dir is requested
    #   - The config exclude_patterns change
    #   - Any .rb file's mtime changes (checked via fingerprint)
    class AnalysisCache
      @cache = {}
      @mutex = Mutex.new

      # Fetches cached analyses for a project, or runs the block to compute them.
      # @param project_dir [String] Absolute path to the project root
      # @param config [AutoDoc::Config] Configuration object (for exclude_patterns)
      # @param file_list [Array<String>, nil] Optional subset of files (for incremental)
      # @yield Block that performs the actual analysis
      # @return [Hash] Analysis results
      def self.fetch(project_dir, config, file_list: nil)
        raise ArgumentError, "Block required" unless block_given?

        # Don't cache incremental/subset analyses — only full project scans
        return yield if file_list

        fingerprint = compute_fingerprint(project_dir, config)

        @mutex.synchronize do
          cached = @cache[fingerprint]
          return cached if cached
        end

        analyses = yield

        @mutex.synchronize do
          @cache[fingerprint] = analyses
        end

        analyses
      end

      # Clears the entire cache. Useful in tests.
      def self.clear!
        @mutex.synchronize { @cache.clear }
      end

      # Returns the number of cached entries.
      def self.size
        @cache.size
      end

      # Computes a fingerprint for (project_dir, config) based on:
      #   - Project directory path
      #   - Exclude patterns
      #   - Latest mtime among .rb files (fast single-pass)
      #
      # @param project_dir [String] Absolute path to the project root
      # @param config [AutoDoc::Config] Configuration object
      # @return [String] Fingerprint string
      def self.compute_fingerprint(project_dir, config)
        excludes = (config.exclude_patterns || []).sort.join(",")
        latest_mtime = latest_ruby_mtime(project_dir, excludes)
        "#{project_dir}|#{excludes}|#{latest_mtime}"
      end

      # Finds the latest mtime among all .rb files in the project.
      # Returns 0 if no files found.
      # @param project_dir [String] Project root
      # @param excludes [String] Joined exclude patterns
      # @return [Integer] Unix timestamp of latest mtime
      def self.latest_ruby_mtime(project_dir, excludes)
        latest = 0
        pattern = File.join(project_dir, "**", "*.rb")

        Dir.glob(pattern).each do |fp|
          # Skip excluded patterns
          relative = fp.sub("#{project_dir}/", "")
          next if excludes.split(",").any? { |pat| !pat.empty? && File.fnmatch?(pat, relative, File::FNM_PATHNAME) }

          mtime = File.mtime(fp).to_i rescue next
          latest = mtime if mtime > latest
        end

        latest
      end

      private_class_method :compute_fingerprint, :latest_ruby_mtime
    end
  end
end
