# frozen_string_literal: true

require "fileutils"
require "pathname"
require_relative "transformer"

module AutoDoc
  # Extracted orchestration logic from CLI. Accepts explicit parameters and returns results.
  # CLI handles all output formatting; this class handles the "what to do."
  class Orchestrator
    def initialize(options = {})
      @options = options.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
    end

    # Performs full documentation generation for the given path.
    # @param path [String] Project directory path
    # @param say [Proc] Callable for output messages (default: puts)
    # @return [Hash]
    def generate(path, say: method(:puts))
      target_dir = File.expand_path(path)
      config     = AutoDoc::Config.load(target_dir, cli_overrides(@options))

      # Determine output directory: CLI flag > format option > config default
      output_dir = if @options[:output_dir]
                     @options[:output_dir]
                   elsif @options[:format] == "docs"
                     ".docs"
                   elsif @options[:format] == "autodoc"
                     ".autodoc"
                   else
                     config.output_dir
                   end

      created_files = []
      wrapped_say = ->(msg, color = nil) {
        created_files << msg.sub(/^  Created /, "") if msg.is_a?(String) && msg.start_with?("  Created ")
        say.call(msg, color)
      }

      wrapped_say.call("Generating documentation for #{target_dir}...", :green)

      module_roots = resolve_module_roots(target_dir, config)
      analyses     = if @options[:incremental]
                        stale = AutoDoc::Utils::TimestampTracker.stale_files(target_dir, output_dir).map { |f| File.join(target_dir, f) }
                        wrapped_say.call("Incremental mode: #{stale.size} file(s) changed", :yellow)
                        analyze_project(target_dir, config, stale)
                      else
                        analyze_project(target_dir, config)
                      end

      pipeline = Pipeline.new(config)
      stats    = pipeline.run(analyses,
                               target_dir: target_dir,
                               output_dir: output_dir,
                               module_roots: module_roots,
                               say: wrapped_say)

      # Print created files count (tracked by wrapped_say above)
      wrapped_say.call("  #{created_files.size} documentation files created", :green)

      stats.merge(created_files: created_files)
    end

    # Runs audit analysis and returns the report hash (does NOT call exit).
    # @param path [String] Project directory path
    # @param threshold [Integer] Minimum coverage percentage
    # @param say [Proc] Callable for output messages (default: puts)
    # @param analyses [Hash, nil] Optional pre-computed analyses (reuses cache if nil)
    # @return [Hash] Audit report with pass/fail status
    def audit(path, threshold = 80, say: method(:puts), analyses: nil)
      target_dir = File.expand_path(path)
      say.call("  Analyzing #{target_dir}...", :green)

      overrides = cli_overrides(@options).merge(audit: { min_doc_coverage: threshold })
      config = AutoDoc::Config.load(target_dir, overrides)

      analyses ||= analyze_project(target_dir, config)
      report   = AutoDoc::Reporter::AuditReporter.generate(target_dir, config, analyses)

      # Write JSON report for CI pipelines
      json_path = File.join(target_dir, config.output_dir, "report.json")
      begin
        FileUtils.mkdir_p(File.dirname(json_path))
      rescue Errno::EACCES, Errno::ENOSPC, SystemCallError => e
        $stderr.puts "[AutoDoc] Failed to create audit report directory: #{e.message}"
      end
      File.write(json_path, AutoDoc::Reporter::AuditReporter.format_json(report)) if File.writable?(File.dirname(json_path))

      report
    end

    private

    # Extracts CLI overrides from options hash.
    def cli_overrides(options)
      overrides = {}
      overrides[:exclude_patterns] = options[:exclude] if options[:exclude]
      overrides[:incremental] = options[:incremental] if options.key?(:incremental)
      overrides[:llm] = { primary: true } if options[:"llm-primary"]
      overrides
    end

    # Resolves which directories are module roots worth documenting.
    def resolve_module_roots(base_dir, config)
      roots = (config.module_roots || []).map { |r| File.join(base_dir, r) }.select { |d| File.directory?(d) }
      roots.empty? ? [base_dir] : roots
    end

    # Analyzes all Ruby files in the project and returns structured analysis data.
    # Results are cached in-process so that `verify` + `audit` + subsequent commands
    # reuse the same analysis without re-parsing every file.
    def analyze_project(base_dir, config, file_list = nil)
      excludes = config.exclude_patterns || []

      # Use cache only for full-project scans (no file_list)
      if file_list.nil?
        return AutoDoc::Analyzer::AnalysisCache.fetch(base_dir, config) do
          run_analysis_pipeline(base_dir, excludes, nil)
        end
      end

      run_analysis_pipeline(base_dir, excludes, file_list)
    end

    # Runs the full analysis pipeline: file globbing → SourceParser/GenericScanner → YARD → import extraction.
    def run_analysis_pipeline(base_dir, excludes, file_list)
      extensions = AutoDoc::Analyzer::GenericScanner::SUPPORTED_EXTENSIONS.keys.map { |e| e.delete_prefix(".") }
      glob_pattern = "**/*.{#{extensions.join(",")}}"

      source_files = if file_list
                       file_list.reject do |f|
                         relative = f.sub("#{base_dir}/", "")
                         excludes.any? { |pat| File.fnmatch?(pat, relative, File::FNM_PATHNAME) }
                       end
                     else
                       Dir.glob(File.join(base_dir, glob_pattern)).reject do |f|
                         next true unless File.file?(f)
                         relative = f.sub("#{base_dir}/", "")
                         excludes.any? { |pat| File.fnmatch?(pat, relative, File::FNM_PATHNAME) }
                       end
                     end

      analyses = AutoDoc::Analyzer::AnalysisPipeline.run(source_files)

      # Add import data (orchestrator-only — AnalysisPipeline and DiffService do not need it).
      # Language detection is handled inside AnalysisPipeline.
      analyses.each_key do |file_path|
        imports = AutoDoc::Analyzer::ImportExtractor.extract(file_path)
        analyses[file_path][:imports] = imports
      end

      analyses
    end
  end
end
