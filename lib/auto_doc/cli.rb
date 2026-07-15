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
      orchestrator.generate(path, say: method(:say))
    end

    desc "diff SINCE", "Show documentation drift since a git ref or last generation"
    def diff(since)
      if since.nil? || since.empty?
        say "Error: SINCE argument is required (e.g., HEAD~1, main, v1.0.0)", :red
        exit(1)
      end

      current_dir = File.expand_path(".")
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

    desc "audit [PATH]", "Run documentation completeness audit on public symbols"
    method_option :threshold, type: :numeric, default: 80,
                              desc: "Minimum doc coverage percentage for passing CI gate"
    def audit(path = ".")
      report = orchestrator.audit(path, options[:threshold], say: method(:say))
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
      result = AutoDoc::Analyzer::OrphansService.run(path, say: method(:say))

      if result[:orphans].empty?
        say "No orphan files found.", :green
      else
        say "#{result[:orphans].size} orphan file(s) found:", :yellow
        result[:orphans].each { |f| say "  #{f}", :yellow }
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

    private

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
