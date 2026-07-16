# frozen_string_literal: true

require "fileutils"
require "thor"
require "pathname"
require "shellwords"

module AutoDoc
  # Thor-based CLI with subcommands for documentation generation and auditing.
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    class_option :verbose, type: :boolean, aliases: "-v", default: false, desc: "Verbose output"
    class_option :json, type: :boolean, default: false, desc: "Output as JSON"
    class_option :agent, type: :boolean, default: false, desc: "Output compact agent-optimized JSON"

    # ── INIT ──────────────────────────────────────────────────────────

    desc "init [PATH]", "Initialize .autodoc.yml config file in directory"
    def init(path = ".")
      target_dir   = File.expand_path(path)
      config_file  = File.join(target_dir, ".autodoc.yml")

      if File.exist?(config_file)
        say "#{config_file} already exists — skipping", :yellow
        return
      end

      FileUtils.mkdir_p(target_dir)
      default_config = generate_default_config_yml
      File.write(config_file, default_config)
      say "Created #{config_file}", :green
    end

    # ── GENERATE / DOC ────────────────────────────────────────────────

    desc "generate [PATH]", "Generate AGENTS.md + README.md + diagrams for all module directories"
    method_option :incremental, type: :boolean, default: false,
                                desc: "Skip unchanged directories (full regeneration by default)"
    method_option :exclude,     type: :array,   default: %w[spec test vendor node_modules],
                                desc: "Directories to exclude from analysis"
    method_option :format,      type: :string,  default: "docs",
                                desc: "Output format: autodoc (.autodoc/) or docs (.docs/)"
    method_option :output_dir,  type: :string,
                                desc: "Output directory (default: .docs)"
    method_option :"llm-primary", type: :boolean, default: false,
                                desc: "Use LLM as primary documentation source"
    def generate(path = ".")
      return help("generate") if path == "--help" || path == "-h"

      output_format = output_format_for(options)
      if output_format != :text
        silent = ->(_msg, _color = nil) { }
        result = orchestrator.generate(path, say: silent)
        AutoDoc::Utils::OutputFormatter.format(result, format: output_format, say: method(:say))
        result
      else
        orchestrator.generate(path, say: method(:say))
      end
    end

    map "g"      => :generate
    map "doc"    => :generate
    map "gen"    => :generate

    # ── DIFF ──────────────────────────────────────────────────────────

    desc "diff SINCE [PATH]", "Show documentation drift since a git ref or last generation"
    def diff(since, path = ".")
      return help("diff") if since == "--help" || since == "-h"

      if since.nil? || since.empty?
        say "ERROR: SINCE argument is required (e.g., HEAD~1, main, v1.0.0)", :red
        exit(1)
      end

      target_dir = File.expand_path(path)
      output_format = output_format_for(options)

      if output_format != :text
        silent = ->(_msg, _color = nil) { }
        result = AutoDoc::Analyzer::DiffService.run(target_dir, since, say: silent)
        AutoDoc::Utils::OutputFormatter.format(result, format: output_format, say: method(:say))
      else
        result = AutoDoc::Analyzer::DiffService.run(target_dir, since, say: method(:say))

        if result[:changed_files].empty?
          say "No Ruby files changed since '#{since}'.", :green
        elsif result[:undocumented_changes].empty?
          say "All changed symbols have documentation.", :green
        else
          say "\nUndocumented changes since '#{since}':", :red
          result[:undocumented_changes].each do |change|
            say "  #{change[:type]} `#{change[:symbol]}` in #{change[:file]}", :yellow
          end
        end
      end
    end

    # ── AUDIT ─────────────────────────────────────────────────────────

    desc "audit [PATH]", "Run documentation completeness audit on public symbols"
    method_option :threshold, type: :numeric, default: 80,
                              desc: "Minimum doc coverage percentage for passing CI gate"
    method_option :fail, type: :boolean, default: false,
                         desc: "Exit with code 1 if coverage below threshold (CI mode)"
    method_option :"llm-primary", type: :boolean, default: false,
                              desc: "Use LLM as primary documentation source"
    def audit(path = ".")
      return help("audit") if path == "--help" || path == "-h"

      output_format = output_format_for(options)

      if output_format != :text
        silent = ->(_msg, _color = nil) { }
        report = orchestrator.audit(path, options[:threshold], say: silent)
        AutoDoc::Utils::OutputFormatter.format(report, format: output_format, say: method(:say))
      else
        report = orchestrator.audit(path, options[:threshold], say: method(:say))
        print_audit_summary(report)
      end

      if !report[:passed] && options[:fail]
        say "\nAudit FAILED: coverage #{report[:overall_coverage]}% < threshold #{report[:min_coverage]}%", :red
        exit(1)
      end
    end

    # ── VERSION ───────────────────────────────────────────────────────

    desc "version", "Print gem version"
    def version
      say "auto-doc #{AutoDoc::VERSION}"
    end

    # ── ORPHANS ───────────────────────────────────────────────────────

    desc "orphans [PATH]", "Find Ruby files that are not documented, imported, or referenced"
    method_option :rails, type: :boolean, default: false,
                          desc: "Skip Rails autoloaded paths (app/models/, app/controllers/, etc.)"
    def orphans(path = ".")
      return help("orphans") if path == "--help" || path == "-h"

      output_format = output_format_for(options)
      target_dir = File.expand_path(path)

      service_options = { rails: options[:rails] }

      if output_format != :text
        silent = ->(_msg, _color = nil) { }
        result = AutoDoc::Analyzer::OrphansService.run(target_dir, say: silent, options: service_options)
        AutoDoc::Utils::OutputFormatter.format(result, format: output_format, say: method(:say))
      else
        result = AutoDoc::Analyzer::OrphansService.run(target_dir, say: method(:say), options: service_options)

        if result[:orphans].empty?
          say "No orphan files found.", :green
        else
          # Show relative paths only
          relative_orphans = result[:orphans].map { |f| f.sub("#{target_dir}/", "") }
          say "#{relative_orphans.size} orphan file(s) found:", :yellow
          relative_orphans.each { |f| say "  #{f}", :yellow }

          # Show directory breakdown
          by_directory = result[:by_directory]
          if by_directory&.any?
            say "\nBreakdown by directory:", :cyan
            by_directory.sort_by { |_dir, count| -count }.each do |dir, count|
              say "  #{dir}/: #{count}", :cyan
            end
          end
        end
      end
    end

    # ── SERVE ─────────────────────────────────────────────────────────

    desc "serve [PATH]", "Start a web server to browse generated documentation"
    method_option :port, type: :numeric, default: 4567, desc: "Port to bind the server"
    def serve(path = ".")
      return help("serve") if path == "--help" || path == "-h"

      require_relative "../auto_doc/server"
      target_dir = File.expand_path(path)
      say "Starting auto-doc server on http://localhost:#{options[:port]}", :green
      say "Serving documentation from #{target_dir}", :green
      ENV["AUTO_DOC_SERVE_DIR"] = target_dir
      AutoDoc::Server.set :port, options[:port]
      AutoDoc::Server.run!
    end

    # ── E2E ───────────────────────────────────────────────────────────

    desc "e2e [PATH]", "Run end-to-end self-test against the project's own source"
    def e2e(path = ".")
      return help("e2e") if path == "--help" || path == "-h"

      target_dir = File.expand_path(path)
      success = AutoDoc::Tester::E2ERunner.run(target_dir)
      exit(1) unless success
    end

    # ── VERIFY ────────────────────────────────────────────────────────

    desc "verify [PATH]", "Generate documentation and run audit in one step"
    method_option :threshold, type: :numeric, default: 80,
              desc: "Minimum doc coverage percentage for passing CI gate"
    method_option :ci, type: :boolean, default: false,
              desc: "Exit with code 1 on audit failure (for CI pipelines)"
    method_option :"llm-primary", type: :boolean, default: false,
              desc: "Use LLM as primary documentation source"
    def verify(path = ".")
      return help("verify") if path == "--help" || path == "-h"

      orchestrator.generate(path, say: method(:say))
      report = orchestrator.audit(path, options[:threshold], say: method(:say))
      print_audit_summary(report)

      if !report[:passed] && options[:ci]
        say "\nAudit FAILED: coverage #{report[:overall_coverage]}% < threshold #{report[:min_coverage]}%", :red
        exit(1)
      end
    end

    # ── SEARCH ────────────────────────────────────────────────────────

    desc "search TERM [PATH]", "Search documentation for a term across INDEX.md, SUMMARY.md, vectors.json, and AGENTS.md"
    method_option :source, type: :boolean, default: false, desc: "Also search source .rb files"
    method_option :limit, type: :numeric, default: 20, desc: "Maximum number of results"
    def search(term, path = ".")
      if term == "--help" || term == "-h"
        return help("search")
      end

      output_format = output_format_for(options)
      project_dir = File.expand_path(path)

      result = AutoDoc::SearchService.search(project_dir, term, options: { source: options[:source], limit: options[:limit] })

      if output_format != :text
        AutoDoc::Utils::OutputFormatter.format(result, format: output_format, say: method(:say))
      else
        if result[:results].empty?
          say "No results found for '#{term}'."
          say "Tip: try --source to also search source .rb files" unless options[:source]
        else
          say "Search results for '#{term}':"
          result[:results].each do |r|
            say "  #{r[:file]}:#{r[:line]} (#{r[:match_type]}, score: #{r[:score]})"
            say "    #{r[:context]}"
          end
          say "Total: #{result[:total]} results"
        end
      end
    end

    # ── QUERY ─────────────────────────────────────────────────────────

    desc "query MODULE [PATH]", "Show structured summary for a module (INDEX.md + SUMMARY.md + VECTORS.json)"
    def query(mod, path = ".")
      return help("query") if mod == "--help" || mod == "-h"

      output_format = output_format_for(options)
      project_dir = File.expand_path(path)
      docs_dir = File.join(project_dir, ".docs", mod)

      index_path   = File.join(docs_dir, "INDEX.md")
      summary_path = File.join(docs_dir, "SUMMARY.md")
      vectors_path = File.join(docs_dir, "VECTORS.json")
      unless File.exist?(vectors_path)
        alt = Dir.glob(File.join(docs_dir, "vectors.json")).first
        vectors_path = alt if alt
      end

      if [index_path, summary_path, vectors_path].none? { |p| File.exist?(p) }
        say "No documentation found for module '#{mod}' in #{File.join(project_dir, '.docs')}", :yellow
        available = Dir.glob(File.join(project_dir, ".docs", "**", "INDEX.md")).map { |f|
          f.sub("#{File.join(project_dir, '.docs')}/", "").sub("/INDEX.md", "")
        }.uniq.sort
        unless available.empty?
          say "Available modules: #{available.join(', ')}", :cyan
        end
        return
      end

      result = {
        module: mod,
        index:   File.exist?(index_path)   ? File.read(index_path, encoding: "UTF-8")   : nil,
        summary: File.exist?(summary_path) ? File.read(summary_path, encoding: "UTF-8") : nil,
        vectors: (File.exist?(vectors_path) ? JSON.parse(File.read(vectors_path, encoding: "UTF-8")) : nil)
      }

      if output_format != :text
        AutoDoc::Utils::OutputFormatter.format(result, format: output_format, say: method(:say))
      else
        say "Module: #{mod}"
        say "  INDEX.md:   #{result[:index]   ? "#{result[:index].lines.count} lines" : 'not found'}"
        say "  SUMMARY.md: #{result[:summary] ? "#{result[:summary].lines.count} lines" : 'not found'}"
        say "  VECTORS.json: #{result[:vectors] ? "#{result[:vectors]['symbols']&.size || 0} symbols" : 'not found'}"
      end
    end

    # ── TREE ──────────────────────────────────────────────────────────

    desc "tree [PATH]", "Display directory tree with box-drawing characters"
    method_option :depth, type: :numeric, desc: "Maximum depth (default: unlimited)"
    def tree(path = ".")
      return help("tree") if path == "--help" || path == "-h"

      output_format = output_format_for(options)
      target = File.expand_path(path)

      tree_str = AutoDoc::Utils::FileTreeBuilder.build(target)

      if output_format != :text
        AutoDoc::Utils::OutputFormatter.format({ path: target, tree: tree_str }, format: output_format, say: method(:say))
      else
        say tree_str
      end
    end

    # ── DIAGRAM ───────────────────────────────────────────────────────

    desc "diagram NAME [PATH]", "Display a Mermaid diagram from .docs/diagrams/"
    method_option :format, type: :string, default: "mermaid", desc: "Output format: mermaid or ascii"
    def diagram(name, path = ".")
      return help("diagram") if name == "--help" || name == "-h"

      output_format = output_format_for(options)
      project_dir = File.expand_path(path)
      diagram_path = File.join(project_dir, ".docs", "diagrams", "#{name}.mmd")

      unless File.exist?(diagram_path)
        say "ERROR: Diagram '#{name}' not found at #{diagram_path}", :red
        available = Dir.glob(File.join(project_dir, ".docs", "diagrams", "*.mmd")).map { |f|
          File.basename(f, ".mmd")
        }.sort
        unless available.empty?
          say "Available diagrams: #{available.join(', ')}", :cyan
        end
        exit(1)
      end

      content = File.read(diagram_path, encoding: "UTF-8")
      result = { name: name, content: content, format: options[:format] }

      if output_format != :text
        AutoDoc::Utils::OutputFormatter.format(result, format: output_format, say: method(:say))
      else
        say content
      end
    end

    # ── AGENT ─────────────────────────────────────────────────────────

    desc "agent PROMPT", "Query documentation using natural language (e.g., 'what depends on Calculator')"
    method_option :path, type: :string, default: ".", desc: "Project path"
    long_desc <<~LONGDESC
      Interpret natural-language prompts about the project's documentation.
      Examples:
        auto-doc agent what depends on Calculator
        auto-doc agent describe the SearchService
        auto-doc agent diagram for architecture
        auto-doc agent --json list all symbols
    LONGDESC
    def agent(*prompt_parts)
      # Check for help request
      if prompt_parts.size == 1 && (prompt_parts[0] == "--help" || prompt_parts[0] == "-h")
        return help("agent")
      end

      output_format = output_format_for(options)
      prompt = prompt_parts.join(" ")
      if prompt.empty?
        say "ERROR: PROMPT is required", :red
        exit(1)
      end

      project_dir = File.expand_path(options[:path])
      result = AutoDoc::AgentQueryService.query(project_dir, prompt)

      if output_format != :text
        AutoDoc::Utils::OutputFormatter.format(result, format: output_format, say: method(:say))
      else
        say "Intent: #{result[:intent]}"
        if result[:result].nil? || (result[:result].is_a?(Array) && result[:result].empty?) || (result[:result].is_a?(Hash) && result[:result].empty?)
          say "No results found for your query.", :yellow
        elsif result[:result].is_a?(String)
          say result[:result]
        else
          formatted = JSON.pretty_generate(result[:result])
          # Truncate very long output
          if formatted.length > 2000
            say formatted[0..2000] + "\n... (truncated, use --json for full output)"
          else
            say formatted
          end
        end
      end
    end

    private

    # Prints a compact audit summary instead of the full failure list.
    def print_audit_summary(report)
      return unless report.is_a?(Hash)

      say "", :green
      say "Coverage: #{report[:overall_coverage]}% (#{report[:documented_count]} / #{report[:total_symbols]} documented)", :green
      say "Threshold: #{report[:min_coverage]}%", :green

      if report[:passed]
        say "✓ All documentation coverage targets met.", :green
      else
        say "✗ #{report[:undocumented_count]} symbols below threshold.", :red

        low_coverage = report[:low_coverage] || []
        if low_coverage.any?
          say "\nWorst offenders (use --verbose for full list):", :yellow
          low_coverage.sort_by { |f| f[:coverage_pct] || f[:coverage] || 0 }.first(5).each do |entry|
            file = entry[:file].to_s
            # Show relative path
            project_path = report[:project_path] || "."
            rel = file.sub(project_path, "").sub(%r{^/}, "")
            pct = entry[:coverage_pct] || entry[:coverage] || 0
            say "  #{rel} (#{pct}%)", :yellow
          end
          if low_coverage.size > 5
            say "  ... and #{low_coverage.size - 5} more (use --verbose to see all)", :yellow
          end
        end
      end

      say "", :green
    end

    # Determines the output format from CLI options.
    # Agent flag takes precedence over json flag.
    # @param opts [Thor::CoreExt::HashWithIndifferentAccess] CLI options
    # @return [Symbol] :text, :json, or :agent
    def output_format_for(opts)
      return :agent if opts[:agent]
      return :json if opts[:json]
      :text
    end

    # Returns a configured Orchestrator instance.
    def orchestrator
      @orchestrator ||= AutoDoc::Orchestrator.new(options.to_h)
    end

    # Returns the YAML content for a default .autodoc.yml config file.
    def generate_default_config_yml
      <<~YAML
        # Auto-doc configuration
        # Documentation: https://github.com/auto-doc-tool/auto-doc

        module_roots:
          - app
          - lib
          - bin

        exclude_patterns:
          - vendor/**/*
          - node_modules/**/*
          - spec/**/*

        output:
          directory: .docs
          format: markdown

        audit:
          min_doc_coverage: 80
          max_module_size: 50

        diagrams:
          generate_dag: true
          diagram_directory: diagrams
      YAML
    end
  end
end
