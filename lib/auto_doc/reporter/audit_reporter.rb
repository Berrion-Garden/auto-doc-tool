# frozen_string_literal: true

require "json"
require "time"
require "set"

module AutoDoc
  module Reporter
    # Generates audit reports summarizing documentation coverage across a project.
    class AuditReporter
      # Generates an audit report from analysis data and configuration.
      # @param project_dir [String] Root directory of the project
      # @param config [AutoDoc::Config] Configuration object with thresholds
      # @param analyses [Array<Hash>] Analysis results per file/module
      #   Each hash should contain :symbols, :documented, :file keys.
      # @return [Hash] Audit report with pass/fail status and details
      def self.generate(project_dir, config, analyses)
        new(project_dir, config).generate(analyses)
      end

      def initialize(project_dir, config)
        @project_dir = project_dir
        @config      = config
      end

      # Generates the full audit report using provided analysis data.
      # @param analyses [Array<Hash>] Analysis results to evaluate
      # @return [Hash] Complete audit report
      def generate(analyses)
        min_coverage = @config.respond_to?(:min_doc_coverage) ? @config.min_doc_coverage : 80
        max_module_size = @config.respond_to?(:max_module_size)   ? @config.max_module_size   : 50

        all_symbols     = []
        documented      = Set.new
        modules         = {}
        failures        = []

        # Accept both Array<Hash> (old format) and Hash<String, Hash> (CLI format)
        # When Hash format, delegate overall coverage to CompletenessChecker (single source of truth)
        overall_pct_from_checker = nil
        input = if analyses.is_a?(Hash)
                  cc_result = AutoDoc::Reporter::CompletenessChecker.check(analyses)
                  overall_pct_from_checker = cc_result[:coverage_pct]
                  analyses.map do |file_path, analysis|
                    definitions = analysis[:definitions] || []
                    {
                      file:       file_path,
                      symbols:    definitions.map { |d| "#{d[:type]}_#{d[:name]}" },
                      documented: definitions.select { |d| d[:has_doc?] }
                                            .map { |d| "#{d[:type]}_#{d[:name]}" }
                    }
                  end
                else
                  analyses
                end

        input.each do |analysis|
          file_path    = analysis[:file] || "(unknown)"
          symbols      = Array(analysis[:symbols])
          doc_symbols  = Set.new(Array(analysis[:documented]))

          all_symbols.concat(symbols)
          documented.merge(doc_symbols)

          module_name = File.basename(file_path, ".rb")
          modules[module_name] = {
            file:         file_path,
            total:        symbols.size,
            documented:   doc_symbols.size,
            coverage_pct: symbols.empty? ? 100.0 : (doc_symbols.to_a.select { |s| symbols.include?(s) }.size.to_f / symbols.size * 100).round(2)
          }

          # Check per-module thresholds
          if modules[module_name][:coverage_pct] < min_coverage
            failures << {
              file:         file_path,
              reason:       "low_coverage",
              coverage_pct: modules[module_name][:coverage_pct],
              threshold:    min_coverage
            }
          end

          if symbols.size > max_module_size
            failures << {
              file:   file_path,
              reason: "module_too_large",
              size:   symbols.size,
              limit:  max_module_size
            }
          end
        end

        # Compute overall coverage — use CompletenessChecker for Hash format (single source of truth),
        # fall back to inline calculation for Array format (legacy string symbols)
        if overall_pct_from_checker
          overall_pct = overall_pct_from_checker
        else
          overall_pct = all_symbols.empty? ? 100.0 : (documented.size.to_f / all_symbols.size * 100).round(2)
        end
        documented_symbols_set = documented.to_a
        undocumented_symbols  = all_symbols - documented_symbols_set
        passed       = overall_pct >= min_coverage && failures.empty?

        {
          project:           @project_dir,
          generated_at:      Time.now.iso8601,
          overall_coverage:  overall_pct.round(2),
          total_symbols:     all_symbols.size,
          documented_symbols: documented.size,
          undocumented:      undocumented_symbols.uniq,
          modules:           modules,
          failures:          failures,
          passed:            passed,
          min_coverage:      min_coverage
        }
      end

      # Formats audit report as human-readable text.
      # @param report [Hash] The audit report hash from generate()
      # @return [String] Formatted text output
      def self.format_text(report)
        lines = []
        lines << "=" * 60
        lines << "AUDIT REPORT"
        lines << "Project: #{report[:project]}"
        lines << "Generated at: #{report[:generated_at]}"
        lines << "=" * 60
        lines << ""

        min_cov = report[:min_coverage] || 80
        lines << "Coverage threshold: #{min_cov}%"
        lines << "Overall coverage:   #{report[:overall_coverage]}%"
        lines << "Total symbols:      #{report[:total_symbols]}"
        lines << "Documented:         #{report[:documented_symbols]}"
        lines << "Undocumented:       #{report[:undocumented].size}"
        lines << ""

        if report[:failures] && !report[:failures].empty?
          lines << "--- FAILURES ---"
          report[:failures].each do |failure|
            lines << "  [#{failure[:reason]}] #{failure[:file]}"
            case failure[:reason]
            when "low_coverage"
              lines << "    Coverage: #{failure[:coverage_pct]}% (threshold: #{failure[:threshold]}%)"
            when "module_too_large"
              lines << "    Size: #{failure[:size]} symbols (limit: #{failure[:limit]})"
            end
          end
        else
          lines << "--- NO FAILURES ---"
        end

        lines << ""
        status = report[:passed] ? "PASSED" : "FAILED"
        lines << "RESULT: #{status}"
        lines << "=" * 60

        lines.join("\n")
      end

      # Formats audit report as JSON.
      # @param report [Hash] The audit report hash from generate()
      # @return [String] JSON-encoded report
      def self.format_json(report)
        clean_report = report.dup
        JSON.pretty_generate(clean_report)
      end
    end
  end
end
