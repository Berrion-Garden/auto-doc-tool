# frozen_string_literal: true

module AutoDoc
  class Orchestrator
    class ReadmeStep < BaseStep
      include CountingHelper

      def run(context)
        target_dir    = context[:target_dir]
        output_dir    = context[:output_dir]
        config        = context[:config]
        module_roots  = context[:module_roots]
        analyses      = context[:analyses]

        return context unless module_roots.any?

        structure = {}

        module_roots.each do |root|
          dir_name  = File.basename(root)
          tree_text = AutoDoc::Utils::FileTreeBuilder.build(root, config.exclude_patterns || [])
          structure[dir_name] = tree_text
        end

        all_cls, all_methods = count_classes_and_methods(analyses)
        coverage_pct         = calculate_coverage(analyses)

        summary = {
          total_modules: module_roots.size,
          total_classes: all_cls,
          total_methods: all_methods,
          coverage_pct:  coverage_pct
        }

        readme_path  = File.join(target_dir, output_dir, "README.md")
        project_name = File.basename(target_dir)

        AutoDoc::Generator::ReadmeGenerator.generate(project_name, structure, summary, output_path: readme_path)
        say(context, "  Created #{readme_path}", :green)

        context[:all_classes]  = all_cls
        context[:all_methods]  = all_methods
        context[:coverage_pct] = coverage_pct

        context
      end

    end
  end
end
