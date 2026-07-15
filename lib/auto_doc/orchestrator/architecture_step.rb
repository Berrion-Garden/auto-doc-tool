# frozen_string_literal: true

module AutoDoc
  class Orchestrator
    class ArchitectureStep < BaseStep
      def run(context)
        target_dir     = context[:target_dir]
        output_dir     = context[:output_dir]
        project_name   = File.basename(target_dir)
        schema_tables  = context[:schema_tables] || []
        models         = context[:models] || []
        class_hierarchy = context[:class_hierarchy] || []

        architecture_config = {
          overview: "Auto-generated architecture documentation for #{project_name}.",
          design_decisions: [],
          diagram_links: [
            { title: "C4 Context",    path: "diagrams/c4_context.mmd" },
            { title: "C4 Container",  path: "diagrams/c4_container.mmd" },
            { title: "Class Diagram", path: "diagrams/class_diagram.mmd" }
          ]
        }

        if schema_tables && !schema_tables.empty?
          architecture_config[:diagram_links] << { title: "ERD", path: "diagrams/erd.mmd" }
        end

        architecture_path = File.join(target_dir, output_dir, "architecture.md")
        AutoDoc::Generator::ArchitectureGenerator.generate(project_name, schema_tables, models, class_hierarchy,
                                                            architecture_config, output_path: architecture_path)
        say(context, "  Created #{architecture_path}", :green)

        context
      end
    end
  end
end
