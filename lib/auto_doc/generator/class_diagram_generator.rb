# frozen_string_literal: true

require "erb"
require "fileutils"

module AutoDoc
  module Generator
    # Generates a Mermaid classDiagram from class hierarchy data.
    # Renders templates/class_diagram_template.erb with class nodes and relationships.
    class ClassDiagramGenerator
      include TemplateHelper

      TEMPLATES_DIR = File.expand_path("../../../templates", __dir__).freeze
      DEFAULT_TEMPLATE = File.join(TEMPLATES_DIR, "class_diagram_template.erb").freeze

      # Generates a Mermaid classDiagram from class hierarchy data.
      # @param title [String] Diagram title (e.g., project name)
      # @param class_hierarchy [Array<Hash>] Class records: {name:, parent:, includes: [], extends: [], methods: []}
      # @param output_path [String, nil] Where to write .mmd file
      # @return [String] Generated Mermaid markdown
      def self.generate(title, class_hierarchy, output_path: nil)
        new(title, class_hierarchy).generate(output_path)
      end

      def initialize(title, class_hierarchy)
        @title = title
        @class_hierarchy = Array(class_hierarchy)
      end

      # Generates mermaid markdown and optionally writes to disk.
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
        template_path = ENV.fetch("AUTO_DOC_TEMPLATE_CLASS_DIAGRAM", DEFAULT_TEMPLATE)
        template_text = read_template(template_path)

        title    = @title
        classes  = @class_hierarchy
        generated_at = Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")

        ERB.new(template_text).result(binding)
      end
    end
  end
end
