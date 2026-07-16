# frozen_string_literal: true

module AutoDoc
  class Orchestrator
    class AgentsOverviewStep < BaseStep
      def run(context)
        target_dir    = context[:target_dir]
        output_dir    = context[:output_dir]
        config        = context[:config]
        module_roots  = context[:module_roots]
        analyses      = context[:analyses]

        # Build combined directory tree from all module roots
        tree_parts = module_roots.map do |root|
          relative = root.start_with?(target_dir) ? root.sub("#{target_dir}/", "") : root
          tree_text = AutoDoc::Utils::FileTreeBuilder.build(root, config.exclude_patterns || [])
          "#{relative}/\n#{tree_text.lines.map { |l| "  #{l}" }.join}"
        end
        combined_tree = tree_parts.join("\n")

        project_name  = File.basename(target_dir)
        output_path   = File.join(target_dir, output_dir, "AGENTS.md")

        AutoDoc::Generator::AgentsOverviewGenerator.generate(
          project_name, analyses, module_roots, combined_tree,
          config: config,
          output_path: output_path
        )

        say(context, "  Created #{output_path}", :green)

        context
      end
    end
  end
end
