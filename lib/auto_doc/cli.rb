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

    desc "generate [PATH]", "Generate AGENTS.md + README.md + diagrams for all module directories"
    method_option :incremental, type: :boolean, default: false,
                                desc: "Skip unchanged directories (full regeneration by default)"
    method_option :exclude,     type: :array,   default: %w[spec test vendor node_modules],
                                desc: "Directories to exclude from analysis"
    method_option :format,      type: :string,  default: "docs",
                                desc: "Output format: autodoc (.autodoc/) or docs (.docs/)"
    method_option :output_dir,  type: :string,
                                desc: "Output directory (default: .docs)"
    def generate(path = ".")
      output_format = output_format_for(options)
      # In json/agent mode, suppress text output and return structured data only
      if output_format != :text
        silent = ->(_msg, _color = nil) { }
        result = orchestrator.generate(path, say: silent)
        AutoDoc::Utils::OutputFormatter.format(result, format: output_format, say: method(:say))
        result
      else
        orchestrator.generate(path, say: method(:say))
      end
    end

    desc "diff SINCE", "Show documentation drift since a git ref or last generation"
    def diff(since)
      if since.nil? || since.empty?
        say "Error: SINCE argument is required (e.g., HEAD~1, main, v1.0.0)", :red
        exit(1)
      end

      current_dir = File.expand_path(".")
      output_format = output_format_for(options)

      if output_format != :text
        silent = ->(_msg, _color = nil) { }
        result = AutoDoc::Analyzer::DiffService.run(current_dir, since, say: silent)
        AutoDoc::Utils::OutputFormatter.format(result, format: output_format, say: method(:say))
      else
        result = AutoDoc::Analyzer::DiffService.run(current_dir, since, say: method(:say))

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

    desc "audit [PATH]", "Run documentation completeness audit on public symbols"
    method_option :threshold, type: :numeric, default: 80,
                              desc: "Minimum doc coverage percentage for passing CI gate"
    def audit(path = ".")
      output_format = output_format_for(options)
      if output_format != :text
        silent = ->(_msg, _color = nil) { }
        report = orchestrator.audit(path, options[:threshold], say: silent)
        AutoDoc::Utils::OutputFormatter.format(report, format: output_format, say: method(:say))
      else
        report = orchestrator.audit(path, options[:threshold], say: method(:say))
      end
      unless report[:passed]
        say "\nAudit FAILED: coverage #{report[:overall_coverage]}% < threshold #{report[:min_coverage]}%", :red
        exit(1)
      end
    end

    desc "version", "Print gem version"
    def version
      say "auto-doc #{AutoDoc::VERSION}"
    end

    desc "orphans [PATH]", "Find Ruby files that are not documented, not imported, and not referenced by any other file"
    def orphans(path = ".")
      output_format = output_format_for(options)

      if output_format != :text
        silent = ->(_msg, _color = nil) { }
        result = AutoDoc::Analyzer::OrphansService.run(path, say: silent)
        AutoDoc::Utils::OutputFormatter.format(result, format: output_format, say: method(:say))
      else
        result = AutoDoc::Analyzer::OrphansService.run(path, say: method(:say))

        if result[:orphans].empty?
          say "No orphan files found.", :green
        else
          say "#{result[:orphans].size} orphan file(s) found:", :yellow
          result[:orphans].each { |f| say "  #{f}", :yellow }
        end
      end
    end

    desc "serve [PATH]", "Start a web server to browse generated documentation"
    method_option :port, type: :numeric, default: 4567, desc: "Port to bind the server"
    def serve(path = ".")
      require_relative "../auto_doc/server"
      target_dir = File.expand_path(path)
      say "Starting auto-doc server on http://localhost:#{options[:port]}", :green
      say "Serving documentation from #{target_dir}", :green
      ENV["AUTO_DOC_SERVE_DIR"] = target_dir
      AutoDoc::Server.set :port, options[:port]
      AutoDoc::Server.run!
    end

    desc "e2e [PATH]", "Run end-to-end self-test against the project's own source"
    def e2e(path = ".")
      target_dir = File.expand_path(path)
      success = AutoDoc::Tester::E2ERunner.run(target_dir)
      exit(1) unless success
    end

    desc "verify [PATH]", "Generate documentation and run audit in one step"
    method_option :threshold, type: :numeric, default: 80,
              desc: "Minimum doc coverage percentage for passing CI gate"
    method_option :ci, type: :boolean, default: false,
              desc: "Exit with code 1 on audit failure (for CI pipelines)"
    def verify(path = ".")
      orchestrator.generate(path, say: method(:say))
      report = orchestrator.audit(path, options[:threshold], say: method(:say))
      if !report[:passed] && options[:ci]
        say "\nAudit FAILED: coverage #{report[:overall_coverage]}% < threshold #{report[:min_coverage]}%", :red
        exit(1)
      end
    end

    desc "search TERM [PATH]", "Search documentation for a term across INDEX.md, SUMMARY.md, vectors.json, and AGENTS.md"
    method_option :source, type: :boolean, default: false, desc: "Also search source .rb files"
    method_option :limit, type: :numeric, default: 20, desc: "Maximum number of results"
    def search(term, path = ".")
      output_format = output_format_for(options)
      project_dir = File.expand_path(path)

      result = AutoDoc::SearchService.search(project_dir, term, options: { source: options[:source], limit: options[:limit] })

      if output_format != :text
        AutoDoc::Utils::OutputFormatter.format(result, format: output_format, say: method(:say))
      else
        say "Search results for '#{term}':"
        result[:results].each do |r|
          say "  #{r[:file]}:#{r[:line]} (#{r[:match_type]}, score: #{r[:score]})"
          say "    #{r[:context]}"
        end
        say "Total: #{result[:total]} results"
      end
    end

    desc "query MODULE [PATH]", "Show structured summary for a module (INDEX.md + SUMMARY.md + VECTORS.json)"
    def query(mod, path = ".")
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
        say "  INDEX.md:   #{result[:index]   ? result[:index].lines.first&.strip : 'not found'}"
        say "  SUMMARY.md: #{result[:summary] ? result[:summary].lines.first&.strip : 'not found'}"
        say "  VECTORS.json: #{result[:vectors] ? "#{result[:vectors]['symbols']&.size || 0} symbols" : 'not found'}"
      end
    end

    desc "tree [PATH]", "Display directory tree with box-drawing characters"
    method_option :depth, type: :numeric, desc: "Maximum depth (default: unlimited)"
    def tree(path = ".")
      output_format = output_format_for(options)
      target = File.expand_path(path)

      tree_str = AutoDoc::Utils::FileTreeBuilder.build(target)

      if output_format != :text
        AutoDoc::Utils::OutputFormatter.format({ path: target, tree: tree_str }, format: output_format, say: method(:say))
      else
        say tree_str
      end
    end

    desc "diagram NAME [PATH]", "Display a Mermaid diagram from .docs/diagrams/"
    method_option :format, type: :string, default: "mermaid", desc: "Output format: mermaid or ascii"
    def diagram(name, path = ".")
      output_format = output_format_for(options)
      project_dir = File.expand_path(path)
      diagram_path = File.join(project_dir, ".docs", "diagrams", "#{name}.mmd")

      unless File.exist?(diagram_path)
        say "ERROR: Diagram '#{name}' not found at #{diagram_path}", :red
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

    desc "agent PROMPT", "Query documentation using natural language (e.g., 'what depends on Calculator')"
    long_desc <<~LONGDESC
      Interpret natural-language prompts about the project's documentation.
      Examples:
        auto-doc agent what depends on Calculator
        auto-doc agent describe the SearchService
        auto-doc agent diagram for architecture
        auto-doc agent --json list all symbols
    LONGDESC
    def agent(*prompt_parts)
      output_format = output_format_for(options)
      prompt = prompt_parts.join(" ")
      if prompt.empty?
        say "ERROR: PROMPT is required", :red
        exit(1)
      end

      project_dir = File.expand_path(".")
      result = AutoDoc::AgentQueryService.query(project_dir, prompt)

      if output_format != :text
        AutoDoc::Utils::OutputFormatter.format(result, format: output_format, say: method(:say))
      else
        say "Intent: #{result[:intent]}"
        formatted_result = result[:result].is_a?(String) ? result[:result] : JSON.pretty_generate(result[:result])
        say "Result: #{formatted_result}"
      end
    end

    private

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
