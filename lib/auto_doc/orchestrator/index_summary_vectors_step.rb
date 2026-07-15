# frozen_string_literal: true

require "pathname"

module AutoDoc
  class Orchestrator
    class IndexSummaryVectorsStep < BaseStep
      def run(context)
        target_dir   = context[:target_dir]
        output_dir   = context[:output_dir]
        config       = context[:config]
        module_roots = context[:module_roots]
        analyses     = context[:analyses]

        # Per-directory INDEX.md, SUMMARY.md, vectors.json
        module_roots.each do |root|
          walk_subdirectories(context, root, analyses, target_dir, output_dir, config)
        end

        # Project-level INDEX.md, SUMMARY.md, VECTORS.json
        project_name = File.basename(target_dir)

        project_index_path = File.join(target_dir, output_dir, "INDEX.md")
        AutoDoc::Generator::IndexGenerator.generate(project_name, analyses, config, output_path: project_index_path)
        say(context, "  Created #{project_index_path}", :green)

        project_summary_path = File.join(target_dir, output_dir, "SUMMARY.md")
        AutoDoc::Generator::SummaryGenerator.generate(project_name, analyses, config, output_path: project_summary_path)
        say(context, "  Created #{project_summary_path}", :green)

        project_vectors_path = File.join(target_dir, output_dir, "VECTORS.json")
        vectors_data = AutoDoc::Generator::VectorGenerator.generate_project(analyses, config)
        AutoDoc::Generator::VectorGenerator.write(project_vectors_path, vectors_data)
        say(context, "  Created #{project_vectors_path}", :green)

        context
      end

      private

      def walk_subdirectories(context, root, analyses, target_dir, output_dir, config)
        dirs_to_process = [root]
        dirs_to_process.reject! { |d| d == context[:target_dir] }

        Dir.glob(File.join(root, "**", "*")).select { |e| File.directory?(e) }.each do |subdir|
          dirs_to_process << subdir
        end

        dirs_to_process.each do |dir|
          ruby_files = Dir.glob(File.join(dir, "*.rb"))
          next if ruby_files.empty?

          display_name = File.basename(dir)
          output_rel   = Pathname.new(dir).relative_path_from(Pathname.new(root)).to_s

          if output_rel == "."
            display_name = File.basename(root)
            output_rel   = display_name
          end

          dir_analyses = analyses.select { |fp, _| fp.start_with?("#{dir}/") }
          next if dir_analyses.empty?

          # INDEX.md
          index_path = File.join(target_dir, output_dir, output_rel, "INDEX.md")
          AutoDoc::Generator::IndexGenerator.generate(display_name, dir_analyses, config, output_path: index_path)
          say(context, "  Created #{index_path}", :green)

          # SUMMARY.md
          summary_path = File.join(target_dir, output_dir, output_rel, "SUMMARY.md")
          AutoDoc::Generator::SummaryGenerator.generate(display_name, dir_analyses, config, output_path: summary_path)
          say(context, "  Created #{summary_path}", :green)

          # vectors.json — skip root to avoid duplicating project-level VECTORS.json
          next if dir == root

          vectors_data = AutoDoc::Generator::VectorGenerator.generate_directory(display_name, dir_analyses, config)
          vectors_path = File.join(target_dir, output_dir, output_rel, "vectors.json")
          AutoDoc::Generator::VectorGenerator.write(vectors_path, vectors_data)
          say(context, "  Created #{vectors_path}", :green)
        end
      end
    end
  end
end
