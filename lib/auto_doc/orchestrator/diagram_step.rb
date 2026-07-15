# frozen_string_literal: true

require "fileutils"

module AutoDoc
  class Orchestrator
    class DiagramStep < BaseStep
      def run(context)
        target_dir   = context[:target_dir]
        output_dir   = context[:output_dir]
        config       = context[:config]
        module_roots = context[:module_roots]
        analyses     = context[:analyses]

        project_name = File.basename(target_dir)
        diagrams_dir = File.join(target_dir, output_dir, "diagrams")
        FileUtils.mkdir_p(diagrams_dir)

        # Dependency DAG (if enabled)
        if config.generate_dag? && !module_roots.empty?
          nodes, edges = AutoDoc::Transformer::GraphDataBuilder.build(analyses)
          dag_path     = File.join(diagrams_dir, "deps.mmd")
          AutoDoc::Generator::DiagramGenerator.generate(project_name, nodes, edges, output_path: dag_path)
          say(context, "  Created #{dag_path}", :green)
        end

        # Detect Rails project
        is_rails = File.exist?(File.join(target_dir, "db/schema.rb"))
        schema_tables = nil
        models = nil

        if is_rails
          schema_tables = AutoDoc::Analyzer::SchemaParser.parse(target_dir)
          models        = AutoDoc::Analyzer::ModelAssociationParser.parse(target_dir)

          schema_dir = File.join(target_dir, output_dir, "schema")
          FileUtils.mkdir_p(schema_dir)

          schema_path = File.join(schema_dir, "schema.json")
          File.write(schema_path, JSON.pretty_generate(schema_tables))
          say(context, "  Created #{schema_path}", :green)

          models_path = File.join(schema_dir, "models.json")
          File.write(models_path, JSON.pretty_generate(models))
          say(context, "  Created #{models_path}", :green)
        end

        context[:schema_tables] = schema_tables
        context[:models]        = models

        # Class hierarchy (always)
        class_hierarchy = AutoDoc::Transformer::ClassHierarchyBuilder.build(analyses)
        context[:class_hierarchy] = class_hierarchy

        class_diagram_path = File.join(diagrams_dir, "class_diagram.mmd")
        AutoDoc::Generator::ClassDiagramGenerator.generate(project_name, class_hierarchy, output_path: class_diagram_path)
        say(context, "  Created #{class_diagram_path}", :green)

        # ERD (if schema tables found)
        erd_path = File.join(diagrams_dir, "erd.mmd")
        if schema_tables && !schema_tables.empty?
          relationships = AutoDoc::Transformer::ERDRelationshipBuilder.build(models)
          AutoDoc::Generator::ERDGenerator.generate(project_name, schema_tables, relationships, output_path: erd_path)
          say(context, "  Created #{erd_path}", :green)
        end

        # C4 context diagram (always)
        c4_context_path = File.join(diagrams_dir, "c4_context.mmd")
        external_systems = [
          { name: "Developer", interaction: "Writes code and runs documentation commands" },
          { name: "File System", interaction: "Reads/writes documentation files" },
          { name: "Git", interaction: "Version control integration for diff and orphans" }
        ]
        internal_system = { name: project_name }
        AutoDoc::Generator::C4DiagramGenerator.generate_context(project_name, external_systems, internal_system,
                                                                 output_path: c4_context_path)
        say(context, "  Created #{c4_context_path}", :green)

        # C4 container diagram (always)
        c4_container_path = File.join(diagrams_dir, "c4_container.mmd")
        module_info = module_roots.map do |root|
          { name: File.basename(root), description: "#{File.basename(root)} module" }
        end
        container_data_flows = AutoDoc::Transformer::ContainerDataFlowBuilder.build(analyses, module_roots)
        context[:container_data_flows] = container_data_flows

        AutoDoc::Generator::C4DiagramGenerator.generate_container(project_name, module_info, container_data_flows,
                                                                   output_path: c4_container_path)
        say(context, "  Created #{c4_container_path}", :green)

        context
      end
    end
  end
end
