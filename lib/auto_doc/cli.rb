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

      default_config = generate_default_config_yml
      File.write(config_file, default_config)
      say "Created #{config_file}", :green
    end

    desc "generate [PATH]", "Generate AGENTS.md + README.md + diagrams for all module directories"
    method_option :incremental, type: :boolean, default: false,
                                desc: "Skip unchanged directories (full regeneration by default)"
    method_option :exclude,     type: :array,   default: %w[spec test vendor node_modules],
                                desc: "Directories to exclude from analysis"
    method_option :format,      type: :string,  default: "autodoc",
                                desc: "Output format: autodoc (.autodoc/) or docs (.docs/)"
    method_option :output_dir,  type: :string,
                                desc: "Output directory (default: .autodoc)"
    def generate(path = ".")
      target_dir = File.expand_path(path)
      config     = AutoDoc::Config.load(target_dir, cli_overrides(options))

      # Determine output directory: CLI flag > format option > config default
      output_dir = if options[:output_dir]
                     options[:output_dir]
                   elsif options[:format] == "docs"
                     config.instance_variable_get(:@config)[:output] ||= {}
                     config.instance_variable_get(:@config)[:output][:directory] = ".docs"
                     ".docs"
                   else
                     config.output_dir
                   end

      say "Generating documentation for #{target_dir}...", :green

      module_roots = resolve_module_roots(target_dir, config)
      analyses     = analyze_project(target_dir, config)

      # Generate AGENTS.md for each module root
      module_roots.each do |root|
        dir_name   = File.basename(root)
        tree_text  = AutoDoc::Utils::FileTreeBuilder.build(root, config.exclude_patterns || [])

        file_analyses = analyses.select { |fp, _| fp.start_with?(root) }

        files_data = build_files_data(file_analyses)

        output_path = File.join(target_dir, output_dir, dir_name, "AGENTS.md")
        content     = AutoDoc::Generator::AgentsMdGenerator.generate(dir_name, tree_text, files_data, output_path: output_path)

        say "  Created #{output_path}", :green
      end

      # Generate README.md at project level
      if module_roots.any?
        structure   = {}
        total_cls   = 0
        total_methods = 0

        module_roots.each do |root|
          dir_name  = File.basename(root)
          tree_text = AutoDoc::Utils::FileTreeBuilder.build(root, config.exclude_patterns || [])
          structure[dir_name] = tree_text

          root_analyses = analyses.select { |fp, _| fp.start_with?(root) }
          count_classes_and_methods(root_analyses) do |cls_count, method_count|
            total_cls       += cls_count
            total_methods  += method_count
          end
        end

        coverage_pct = calculate_coverage(analyses)

        summary = {
          total_modules: module_roots.size,
          total_classes: total_cls,
          total_methods: total_methods,
          coverage_pct:  coverage_pct
        }

        readme_path  = File.join(target_dir, output_dir, "README.md")
        project_name = File.basename(target_dir)

        AutoDoc::Generator::ReadmeGenerator.generate(project_name, structure, summary, output_path: readme_path)
        say "  Created #{readme_path}", :green
      end

      # Generate dependency DAG if enabled in config
      generate_dag = options[:incremental] ? true : true  # always generate for now

      if generate_dag && !module_roots.empty?
        nodes, edges = build_graph_data(analyses)
        dag_path     = File.join(target_dir, output_dir, "diagrams", "deps.mmd")
        project_name = File.basename(target_dir)

        AutoDoc::Generator::DiagramGenerator.generate(project_name, nodes, edges, output_path: dag_path)
        say "  Created #{dag_path}", :green
      end

      say "\nDocumentation generation complete.", :green
    end

    desc "diff SINCE", "Show documentation drift since a git ref or last generation"
    def diff(since)
      if since.nil? || since.empty?
        say "Error: SINCE argument is required (e.g., HEAD~1, main, v1.0.0)", :red
        exit(1)
      end

      current_dir = File.expand_path(".")
      config      = AutoDoc::Config.load(current_dir)

      say "Checking documentation drift since '#{since}'...", :yellow

      # Use git diff to find changed files
      output = `cd #{Shellwords.escape(current_dir)} && git diff --name-only #{Shellwords.escape(since)} -- '*.rb'` rescue ""
      changed_files = output.split("\n").reject(&:empty?)

      if changed_files.empty?
        say "No Ruby files changed since '#{since}'.", :green
        return
      end

      # Check which changed files have doc comments vs not
      undocumented_changes = []
      changed_files.each do |file_path|
        next unless File.exist?(file_path)

        docs = AutoDoc::Analyzer::YardReader.extract(file_path)
        definitions = AutoDoc::Analyzer::SourceParser.parse_file(file_path)

        # Build lookup index from the docs array
        doc_index = docs.each_with_object({}) do |d, h|
          key_name = d[:target_name].to_s.gsub("::", "_")
          h[:"#{d[:target_type]}_#{key_name}"] = d
        end

        definitions.each do |defn|
          def_name = defn[:name]
          key      = :"#{defn[:type]}_#{def_name.to_s.gsub("::", "_")}"

          unless doc_index.key?(key) || (doc_index.keys.any? { |k| k.to_s.include?(def_name.to_s) })
            undocumented_changes << { file: file_path, symbol: def_name, type: defn[:type] }
          end
        end
      end

      if undocumented_changes.empty?
        say "All changed symbols have documentation.", :green
      else
        say "\nUndocumented changes since '#{since}':", :red
        undocumented_changes.each do |change|
          say "  #{change[:type]} `#{change[:symbol]}` in #{change[:file]}", :yellow
        end
      end
    end

    desc "audit [PATH]", "Run documentation completeness audit on public symbols"
    method_option :threshold, type: :numeric, default: 80,
                              desc: "Minimum doc coverage percentage for passing CI gate"
    def audit(path = ".")
      target_dir = File.expand_path(path)
      config     = AutoDoc::Config.load(target_dir, { audit: { min_doc_coverage: options[:threshold] } })

      say "Running documentation audit for #{target_dir}...", :green

      analyses = analyze_project(target_dir, config)

      report = AutoDoc::Reporter::AuditReporter.generate(target_dir, config, analyses)

      puts AutoDoc::Reporter::AuditReporter.format_text(report)

      # Write JSON report for CI pipelines
      json_path = File.join(target_dir, ".autodoc", "report.json")
      FileUtils.mkdir_p(File.dirname(json_path)) rescue nil
      File.write(json_path, AutoDoc::Reporter::AuditReporter.format_json(report)) if File.writable?(File.dirname(json_path))

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
      target_dir = File.expand_path(path)
      config     = AutoDoc::Config.load(target_dir)

      # Find all .rb files excluding common non-project directories
      exclude_dirs = %w[spec test vendor node_modules]
      all_rb_files = Dir.glob(File.join(target_dir, "**", "*.rb")).select do |fp|
        relative = fp.sub("#{target_dir}/", "")
        exclude_dirs.none? { |d| relative.start_with?("#{d}/") || relative == d }
      end

      if all_rb_files.empty?
        say "No Ruby files found in #{target_dir}.", :yellow
        return
      end

      # Pre-compute content and metadata for every file
      file_data = {}
      all_rb_files.each do |fp|
        relative    = fp.sub("#{target_dir}/", "")
        stem        = File.basename(fp, ".rb")
        docs        = AutoDoc::Analyzer::YardReader.extract(fp)
        imports     = AutoDoc::Analyzer::ImportExtractor.extract(fp)
        definitions = AutoDoc::Analyzer::SourceParser.parse_file(fp)
        def_names   = definitions.map { |d| d[:name] }.compact

        file_data[fp] = {
          relative:  relative,
          stem:      stem,
          docs:      docs,
          imports:   imports,
          def_names: def_names,
          content:   File.read(fp)
        }
      end

      # Determine which files are orphans
      orphans = []

      file_data.each do |fp, data|
        has_docs    = !data[:docs].empty?
        has_imports = !data[:imports].empty?

        # Check if this file's stem or class/module names appear in any other file
        names_to_check = [data[:stem]] + data[:def_names]
        is_referenced = file_data.any? do |other_fp, other_data|
          next if other_fp == fp

          names_to_check.any? { |name| other_data[:content].include?(name) }
        end

        orphans << data[:relative] unless has_docs || has_imports || is_referenced
      end

      if orphans.empty?
        say "No orphan files found.", :green
      else
        say "#{orphans.size} orphan file(s) found:", :yellow
        orphans.each { |f| say "  #{f}", :yellow }
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
      # Run generate directly (not via Thor#invoke which resolves to the test
      # binary name when running under RSpec)
      generate(path)

      # Now run audit directly with the verify-specific threshold option
      target_dir  = File.expand_path(path)
      audit_cfg   = { audit: { min_doc_coverage: options[:threshold] } }
      config      = AutoDoc::Config.load(target_dir, audit_cfg)
      analyses    = analyze_project(target_dir, config)
      report      = AutoDoc::Reporter::AuditReporter.generate(target_dir, config, analyses)

      puts AutoDoc::Reporter::AuditReporter.format_text(report)

      json_path = File.join(target_dir, ".autodoc", "report.json")
      FileUtils.mkdir_p(File.dirname(json_path))
      File.write(json_path, AutoDoc::Reporter::AuditReporter.format_json(report))

      return if report[:passed]

      if options[:ci]
        say "\nAudit FAILED: coverage #{report[:overall_coverage]}% < threshold #{report[:min_coverage]}%", :red
        exit(1)
      else
        say "\nAudit failed (use --ci to exit with code 1)", :yellow
      end
    end

    private

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
          directory: .autodoc
          format: markdown

        audit:
          min_doc_coverage: 80
          max_module_size: 50

        diagrams:
          generate_dag: true
          diagram_directory: diagrams
      YAML
    end

    # Resolves which directories are module roots worth documenting.
    def resolve_module_roots(base_dir, config)
      roots = (config.module_roots || []).map { |r| File.join(base_dir, r) }.select { |d| File.directory?(d) }
      roots.empty? ? [base_dir] : roots
    end

    # Analyzes all Ruby files in the project and returns structured analysis data.
    def analyze_project(base_dir, config)
      analyses = {}
      excludes = config.exclude_patterns || []

      ruby_files = Dir.glob(File.join(base_dir, "**", "*.rb")).reject do |f|
        relative = f.sub("#{base_dir}/", "")
        excludes.any? { |pat| File.fnmatch?(pat, relative, File::FNM_PATHNAME) }
      end

      ruby_files.each do |file_path|
        definitions = AutoDoc::Analyzer::SourceParser.parse_file(file_path)
        imports     = AutoDoc::Analyzer::ImportExtractor.extract(file_path)
        docs        = AutoDoc::Analyzer::YardReader.extract(file_path)

        # Build lookup index: key = :"class_Foo" / :"module_Bar" / :"method_baz"
        doc_index = docs.each_with_object({}) do |d, h|
          key_name = d[:target_name].to_s.gsub("::", "_")
          h[:"#{d[:target_type]}_#{key_name}"] = d
        end

        # Merge documentation presence into each definition.
        # Only count a symbol as documented if its doc record has actual summary content.
        definitions.each do |defn|
          def_name = defn[:name].to_s.gsub("::", "_")
          key      = :"#{defn[:type]}_#{def_name}"
          doc_rec  = doc_index[key]
          defn[:has_doc?] = doc_rec && doc_rec[:has_summary?] == true
        end

        analyses[file_path] = { definitions: definitions, imports: imports, docs: docs }
      end

      analyses
    end

    # Converts raw file analyses into the structure expected by AgentsMdGenerator.
    def build_files_data(analyses)
      files = []
      analyses.each do |file_path, analysis|
        rel_path = file_path.sub(%r{^.*/}, "")
        files << {
          name:    File.basename(file_path),
          path:    file_path,
          classes: analysis[:definitions] || [],
          imports: analysis[:imports] || []
        }
      end
      files.sort_by! { |f| f[:name].downcase }
      files
    end

    # Helper to count classes and methods across analyses.
    def count_classes_and_methods(analyses)
      cls_count   = 0
      method_count = 0

      analyses.each_value do |analysis|
        defs = analysis[:definitions] || []
        cls_count += defs.count { |d| d.is_a?(Hash) && (d[:type] == :class || d[:type] == :module) }
        defs.each do |defn|
          methods_list = if defn.is_a?(Hash)
                           defn[:methods] || []
                         else
                           []
                         end
          method_count += methods_list.size
        end
      end

      yield cls_count, method_count if block_given?
      [cls_count, method_count]
    end

    # Calculates overall documentation coverage from analyses.
    def calculate_coverage(analyses)
      report = AutoDoc::Reporter::CompletenessChecker.check(analyses.map { |fp, a|
        [fp, { symbols: (a[:definitions] || []).map(&:to_h) }]
      }.to_h)
      report[:coverage_pct].to_s
    end

    # Extracts graph nodes and edges from import analyses for diagram generation.
    def build_graph_data(analyses)
      nodes = []
      edges = []

      analyses.each do |file_path, analysis|
        rel_file = file_path.sub(%r{^.*/}, "")
        defs = (analysis[:definitions] || []).select { |d| d.is_a?(Hash) && (d[:type] == :class || d[:type] == :module) }
        defs.each { |d| nodes << d[:name] if d[:name] }

        imports = analysis[:imports] || []
        imports.each do |imp|
          edges << { from: rel_file, to: imp[:path], type: imp[:type].to_s }
        end
      end

      [nodes.uniq.sort, edges]
    end

    # Extracts CLI overrides from Thor options.
    def cli_overrides(options)
      overrides = {}
      overrides[:exclude_patterns] = options[:exclude] if options[:exclude]
      overrides[:incremental] = options[:incremental] if options.key?(:incremental)
      overrides.compact!
    end

  end
end
