# frozen_string_literal: true

require "fileutils"
require "pathname"

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
    # @return [void]
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

      say.call("Generating documentation for #{target_dir}...", :green)

      module_roots = resolve_module_roots(target_dir, config)
      analyses     = if @options[:incremental]
                        stale = AutoDoc::Utils::TimestampTracker.stale_files(target_dir, output_dir).map { |f| File.join(target_dir, f) }
                        say.call("Incremental mode: #{stale.size} file(s) changed", :yellow)
                       analyze_project(target_dir, config, stale)
                     else
                       analyze_project(target_dir, config)
                     end

      # Generate AGENTS.md for each module root
      module_roots.each do |root|
        dir_name   = File.basename(root)
        tree_text  = AutoDoc::Utils::FileTreeBuilder.build(root, config.exclude_patterns || [])

        file_analyses = analyses.select { |fp, _| fp.start_with?(root) }

        files_data = build_files_data(file_analyses)

        output_path = File.join(target_dir, output_dir, dir_name, "AGENTS.md")
        AutoDoc::Generator::AgentsMdGenerator.generate(dir_name, tree_text, files_data, output_path: output_path)

        say.call("  Created #{output_path}", :green)
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
        say.call("  Created #{readme_path}", :green)
      end

      # Generate dependency DAG if enabled in config
      generate_dag = config.generate_dag?

      if generate_dag && !module_roots.empty?
        nodes, edges = build_graph_data(analyses)
        dag_path     = File.join(target_dir, output_dir, "diagrams", "deps.mmd")
        project_name = File.basename(target_dir)

        AutoDoc::Generator::DiagramGenerator.generate(project_name, nodes, edges, output_path: dag_path)
        say.call("  Created #{dag_path}", :green)
      end

      # Save manifest for incremental tracking
      ruby_files_list = Dir.glob(File.join(target_dir, "**", "*.rb")).reject do |f|
        relative = f.sub("#{target_dir}/", "")
        (config.exclude_patterns || []).any? { |pat| File.fnmatch?(pat, relative, File::FNM_PATHNAME) }
      end.map { |f| f.sub("#{target_dir}/", "") }
      AutoDoc::Utils::TimestampTracker.save_manifest(target_dir, ruby_files_list, output_dir)

      say.call("\nDocumentation generation complete.", :green)
    end

    # Runs audit analysis and returns the report hash (does NOT call exit).
    # @param path [String] Project directory path
    # @param threshold [Integer] Minimum coverage percentage
    # @param say [Proc] Callable for output messages (default: puts)
    # @return [Hash] Audit report with pass/fail status
    def audit(path, threshold = 80, say: method(:puts))
      target_dir = File.expand_path(path)
      say.call("Running documentation audit for #{target_dir}...", :green)

      config = AutoDoc::Config.load(target_dir, { audit: { min_doc_coverage: threshold } })

      analyses = analyze_project(target_dir, config)
      report   = AutoDoc::Reporter::AuditReporter.generate(target_dir, config, analyses)

      puts AutoDoc::Reporter::AuditReporter.format_text(report)

      # Write JSON report for CI pipelines
      json_path = File.join(target_dir, config.output_dir, "report.json")
      FileUtils.mkdir_p(File.dirname(json_path)) rescue nil
      File.write(json_path, AutoDoc::Reporter::AuditReporter.format_json(report)) if File.writable?(File.dirname(json_path))

      report
    end

    private

    # Extracts CLI overrides from options hash.
    def cli_overrides(options)
      overrides = {}
      overrides[:exclude_patterns] = options[:exclude] if options[:exclude]
      overrides[:incremental] = options[:incremental] if options.key?(:incremental)
      overrides.compact!
    end

    # Resolves which directories are module roots worth documenting.
    def resolve_module_roots(base_dir, config)
      roots = (config.module_roots || []).map { |r| File.join(base_dir, r) }.select { |d| File.directory?(d) }
      roots.empty? ? [base_dir] : roots
    end

    # Analyzes all Ruby files in the project and returns structured analysis data.
    def analyze_project(base_dir, config, file_list = nil)
      analyses = {}
      excludes = config.exclude_patterns || []

      ruby_files = if file_list
                     file_list.reject do |f|
                       relative = f.sub("#{base_dir}/", "")
                       excludes.any? { |pat| File.fnmatch?(pat, relative, File::FNM_PATHNAME) }
                     end
                   else
                     Dir.glob(File.join(base_dir, "**", "*.rb")).reject do |f|
                       relative = f.sub("#{base_dir}/", "")
                       excludes.any? { |pat| File.fnmatch?(pat, relative, File::FNM_PATHNAME) }
                     end
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
  end
end
