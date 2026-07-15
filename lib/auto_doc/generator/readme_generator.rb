# frozen_string_literal: true

require "erb"
require "fileutils"

module AutoDoc
  module Generator
    # Generates README.md documentation for a Ruby project or module root directory.
    # Renders templates/readme_template.erb with analysis and summary data.
    class ReadmeGenerator
      include TemplateHelper

      TEMPLATES_DIR = File.expand_path("../../../templates", __dir__).freeze
      DEFAULT_TEMPLATE = File.join(TEMPLATES_DIR, "readme_template.erb").freeze

      # Generates a README.md file for the given project or module root.
      # @param project_name [String] Name of the project/module
      # @param structure [Hash<String, String>] Mapping of root dirs to their tree output
      # @param summary_stats [Hash] Summary statistics including total_modules, total_classes, etc.
      # @param output_path [String] Where to write README.md (default: ".autodoc/README.md")
      # @return [String] Generated markdown content
      def self.generate(project_name, structure, summary_stats, output_path: nil)
        new(project_name, structure, summary_stats).generate(output_path)
      end

      def initialize(project_name, structure, summary_stats = {})
        @project_name  = project_name
        @structure     = structure
        @summary_stats = summary_stats
      end

      # Generates markdown and optionally writes to disk.
      # @param output_path [String, nil] File path or nil to return string only
      # @return [String] Rendered markdown content
      def generate(output_path = nil)
        rendered = render_template

        if output_path
          FileUtils.mkdir_p(File.dirname(output_path))
          File.write(output_path, rendered)
        end

        rendered
      end

      private

      def render_template
        template_path = ENV.fetch("AUTO_DOC_TEMPLATE_README", DEFAULT_TEMPLATE)
        template_text = read_template(template_path)

        project_name  = @project_name
        structure     = @structure
        summary_stats = @summary_stats
        generated_at  = Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")

        # Build files array from structure for template rendering
        files = @structure.map do |dir_name, _tree|
          {
            name: dir_name,
            class_count: "-",
            method_count: "-",
            any_documented?: false
          }
        end

        ERB.new(template_text).result(binding)
      end

    end
  end
end
