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

      # Generate AGENTS.md for each module root
      module_roots.each do |root|
        dir_name   = File.basename(root)
        tree_text  = AutoDoc::Utils::FileTreeBuilder.build(root, config.exclude_patterns || [])

        file_analyses = analyses.select { |fp, _| fp.start_with?("#{root}/") }

        files_data = build_files_data(file_analyses)

        output_path = File.join(target_dir, output_dir, dir_name, "AGENTS.md")
        AutoDoc::Generator::AgentsMdGenerator.generate(dir_name, tree_text, files_data, output_path: output_path)

        wrapped_say.call("  Created #{output_path}", :green)
      end

      # Walk all subdirectories under each module root for INDEX.md, SUMMARY.md, vectors.json
      module_roots.each do |root|
        walk_subdirectories(root, analyses, target_dir, output_dir, config, wrapped_say)
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

          root_analyses = analyses.select { |fp, _| fp.start_with?("#{root}/") }
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
        wrapped_say.call("  Created #{readme_path}", :green)
      end

      # Generate dependency DAG if enabled in config
      generate_dag = config.generate_dag?
      project_name = File.basename(target_dir)

      if generate_dag && !module_roots.empty?
        nodes, edges = build_graph_data(analyses)
        dag_path     = File.join(target_dir, output_dir, "diagrams", "deps.mmd")

        AutoDoc::Generator::DiagramGenerator.generate(project_name, nodes, edges, output_path: dag_path)
        wrapped_say.call("  Created #{dag_path}", :green)
      end

      # --- Smart Architecture Generation (Phase 2b) ---

      diagrams_dir = File.join(target_dir, output_dir, "diagrams")

      # Detect Rails project
      is_rails = File.exist?(File.join(target_dir, "db/schema.rb"))

      # Parse schema and models (Rails only)
      schema_tables = nil
      models = nil
      if is_rails
        schema_tables = AutoDoc::Analyzer::SchemaParser.parse(target_dir)
        models = AutoDoc::Analyzer::ModelAssociationParser.parse(target_dir)

        # Save schema.json
        schema_dir = File.join(target_dir, output_dir, "schema")
        FileUtils.mkdir_p(schema_dir)
        schema_path = File.join(schema_dir, "schema.json")
        File.write(schema_path, JSON.pretty_generate(schema_tables))
        wrapped_say.call("  Created #{schema_path}", :green)

        # Save models.json
        models_path = File.join(schema_dir, "models.json")
        File.write(models_path, JSON.pretty_generate(models))
        wrapped_say.call("  Created #{models_path}", :green)
      end

      # Build class hierarchy from source analyses (always)
      class_hierarchy = build_class_hierarchy(analyses)

      # Generate class_diagram.mmd (always)
      class_diagram_path = File.join(diagrams_dir, "class_diagram.mmd")
      AutoDoc::Generator::ClassDiagramGenerator.generate(project_name, class_hierarchy, output_path: class_diagram_path)
      wrapped_say.call("  Created #{class_diagram_path}", :green)

      # Generate erd.mmd (if schema tables found)
      erd_path = File.join(diagrams_dir, "erd.mmd")
      if schema_tables && !schema_tables.empty?
        relationships = build_erd_relationships(models, schema_tables)
        AutoDoc::Generator::ERDGenerator.generate(project_name, schema_tables, relationships, output_path: erd_path)
        wrapped_say.call("  Created #{erd_path}", :green)
      end

      # Build module info for C4 container diagram
      module_info = module_roots.map do |root|
        { name: File.basename(root), description: "#{File.basename(root)} module" }
      end

      # Determine data flows from analyses for C4 container
      container_data_flows = build_container_data_flows(analyses, module_roots)

      # Generate c4_context.mmd (always)
      c4_context_path = File.join(diagrams_dir, "c4_context.mmd")
      external_systems = [
        { name: "Developer", interaction: "Writes code and runs documentation commands" },
        { name: "File System", interaction: "Reads/writes documentation files" },
        { name: "Git", interaction: "Version control integration for diff and orphans" }
      ]
      internal_system = { name: project_name }
      AutoDoc::Generator::C4DiagramGenerator.generate_context(project_name, external_systems, internal_system, output_path: c4_context_path)
      wrapped_say.call("  Created #{c4_context_path}", :green)

      # Generate c4_container.mmd (always)
      c4_container_path = File.join(diagrams_dir, "c4_container.mmd")
      AutoDoc::Generator::C4DiagramGenerator.generate_container(project_name, module_info, container_data_flows, output_path: c4_container_path)
      wrapped_say.call("  Created #{c4_container_path}", :green)

      # Generate architecture.md (always)
      architecture_config = {
        overview: "Auto-generated architecture documentation for #{project_name}.",
        design_decisions: [],
        diagram_links: [
          { name: "C4 Context Diagram", path: "diagrams/c4_context.mmd" },
          { name: "C4 Container Diagram", path: "diagrams/c4_container.mmd" },
          { name: "Class Diagram", path: "diagrams/class_diagram.mmd" }
        ]
      }
      if schema_tables && !schema_tables.empty?
        architecture_config[:diagram_links] << { name: "ERD", path: "diagrams/erd.mmd" }
      end
      architecture_path = File.join(target_dir, output_dir, "architecture.md")
      AutoDoc::Generator::ArchitectureGenerator.generate(project_name, schema_tables || [], models || [], class_hierarchy, architecture_config, output_path: architecture_path)
      wrapped_say.call("  Created #{architecture_path}", :green)

      # Generate project-level INDEX.md, SUMMARY.md, VECTORS.json

      # Project-level INDEX.md using all analyses
      project_index_path = File.join(target_dir, output_dir, "INDEX.md")
      AutoDoc::Generator::IndexGenerator.generate(project_name, analyses, config, output_path: project_index_path)
      wrapped_say.call("  Created #{project_index_path}", :green)

      # Project-level SUMMARY.md using all analyses
      project_summary_path = File.join(target_dir, output_dir, "SUMMARY.md")
      AutoDoc::Generator::SummaryGenerator.generate(project_name, analyses, config, output_path: project_summary_path)
      wrapped_say.call("  Created #{project_summary_path}", :green)

      # Project-level VECTORS.json using all analyses
      project_vectors_path = File.join(target_dir, output_dir, "VECTORS.json")
      vectors_data = AutoDoc::Generator::VectorGenerator.generate_project(analyses, config)
      AutoDoc::Generator::VectorGenerator.write(project_vectors_path, vectors_data)
      wrapped_say.call("  Created #{project_vectors_path}", :green)

      # Save manifest for incremental tracking
      ruby_files_list = Dir.glob(File.join(target_dir, "**", "*.rb")).reject do |f|
        relative = f.sub("#{target_dir}/", "")
        (config.exclude_patterns || []).any? { |pat| File.fnmatch?(pat, relative, File::FNM_PATHNAME) }
      end.map { |f| f.sub("#{target_dir}/", "") }
      AutoDoc::Utils::TimestampTracker.save_manifest(target_dir, ruby_files_list, output_dir)

      # Generate .map.json master manifest
      map_extra = {
        coverage_pct: calculate_coverage(analyses),
        total_symbols: count_all_symbols(analyses)
      }
      AutoDoc::Generator::MapGenerator.generate(target_dir, output_dir, config, analyses, map_extra)
      wrapped_say.call("  Created #{File.join(target_dir, output_dir, ".map.json")}", :green)

      wrapped_say.call("\nDocumentation generation complete.", :green)

      # Return structured result for formatters
      {
        project: File.basename(target_dir),
        output_dir: output_dir,
        module_roots: module_roots.map { |r| File.basename(r) },
        created_files: created_files,
        analyses_count: analyses.size,
        generated_at: Time.now.iso8601,
        schema_tables: schema_tables,
        models: models
      }
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

      say.call(AutoDoc::Reporter::AuditReporter.format_text(report))

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

      analyses = AutoDoc::Analyzer::AnalysisPipeline.run(ruby_files)

      # Add import data (orchestrator-only — DiffService does not need it)
      analyses.each_key do |file_path|
        imports = AutoDoc::Analyzer::ImportExtractor.extract(file_path)
        analyses[file_path][:imports] = imports
      end

      analyses
    end

    # Converts raw file analyses into the structure expected by AgentsMdGenerator.
    def build_files_data(analyses)
      AutoDoc::Transformer::FilesDataBuilder.build(analyses)
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

    def count_all_symbols(analyses)
      analyses.sum { |_, a| (a[:definitions] || []).size }
    end

    # Builds class hierarchy from analysis data for the class diagram.
    # @param analyses [Hash<String, Hash>] Full analysis data
    # @return [Array<Hash>] Class hierarchy records
    def build_class_hierarchy(analyses)
      AutoDoc::Transformer::ClassHierarchyBuilder.build(analyses)
    end

    # Builds ERD relationship records from model associations and schema tables.
    # @param models [Array<Hash>, nil] Model association data
    # @param _schema_tables [Array<Hash>, nil] Schema table data (unused, kept for API consistency)
    # @return [Array<Hash>] Relationship records
    def build_erd_relationships(models, _schema_tables = nil)
      AutoDoc::Transformer::ERDRelationshipBuilder.build(models, _schema_tables)
    end

    # Builds data flow records between module roots for the C4 container diagram.
    # @param analyses [Hash<String, Hash>] Full analysis data
    # @param module_roots [Array<String>] Module root directory paths
    # @return [Array<Hash>] Data flow records
    def build_container_data_flows(analyses, module_roots)
      AutoDoc::Transformer::ContainerDataFlowBuilder.build(analyses, module_roots)
    end

    # Extracts graph nodes and edges from import analyses for diagram generation.
    def build_graph_data(analyses)
      AutoDoc::Transformer::GraphDataBuilder.build(analyses)
    end

    # Walks all subdirectories under a root and generates INDEX.md, SUMMARY.md,
    # and vectors.json for any directory that contains Ruby files.
    # @param root [String] Root directory path
    # @param analyses [Hash<String, Hash>] Full analysis data
    # @param target_dir [String] Project target directory
    # @param output_dir [String] Output directory name relative to target_dir
    # @param config [AutoDoc::Config] Configuration object
    # @param say [Proc] Callable for output messages
    # @return [void]
    def walk_subdirectories(root, analyses, target_dir, output_dir, config, say)
      # Collect all subdirectories including the root itself.
      # Skip the root if it equals target_dir to avoid duplicate project-level files
      # (project-level INDEX.md, SUMMARY.md, VECTORS.json are generated separately).
      dirs_to_process = [root]
      dirs_to_process.reject! { |d| d == target_dir }
      Dir.glob(File.join(root, "**", "*")).select { |e| File.directory?(e) }.each do |subdir|
        dirs_to_process << subdir
      end

      dirs_to_process.each do |dir|
        # Check if directory contains Ruby files
        ruby_files = Dir.glob(File.join(dir, "*.rb"))
        next if ruby_files.empty?

        display_name  = File.basename(dir)
        output_rel    = Pathname.new(dir).relative_path_from(Pathname.new(root)).to_s

        # Fix 6: When processing root itself, output_rel is ".". Use basename for
        # display and treat as root-level output (no subdirectory nesting).
        if output_rel == "."
          display_name = File.basename(root)
          output_rel   = display_name
        end

        dir_analyses  = analyses.select { |fp, _| fp.start_with?("#{dir}/") }
        next if dir_analyses.empty?

        # Generate INDEX.md
        index_path = File.join(target_dir, output_dir, output_rel, "INDEX.md")
        AutoDoc::Generator::IndexGenerator.generate(display_name, dir_analyses, config, output_path: index_path)
        say.call("  Created #{index_path}", :green)

        # Generate SUMMARY.md
        summary_path = File.join(target_dir, output_dir, output_rel, "SUMMARY.md")
        AutoDoc::Generator::SummaryGenerator.generate(display_name, dir_analyses, config, output_path: summary_path)
        say.call("  Created #{summary_path}", :green)

        # Fix 5: Skip vectors.json for the root directory itself — project-level
        # VECTORS.json is already generated separately and covers all analyses.
        next if dir == root

        # Generate vectors.json
        vectors_data = AutoDoc::Generator::VectorGenerator.generate_directory(display_name, dir_analyses, config)
        vectors_path = File.join(target_dir, output_dir, output_rel, "vectors.json")
        AutoDoc::Generator::VectorGenerator.write(vectors_path, vectors_data)
        say.call("  Created #{vectors_path}", :green)
      end
    end
  end
end
