# frozen_string_literal: true

require "erb"
require "fileutils"

module AutoDoc
  module Generator
    # Generates a Mermaid erDiagram from schema table and relationship data.
    # Renders templates/erd_template.erb with table definitions and relationship lines.
    class ERDGenerator
      include TemplateHelper

      TEMPLATES_DIR = File.expand_path("../../../templates", __dir__).freeze
      DEFAULT_TEMPLATE = File.join(TEMPLATES_DIR, "erd_template.erb").freeze

      # Generates a Mermaid erDiagram from table and relationship data.
      # @param title [String] Diagram title (e.g., project name)
      # @param tables [Array<Hash>] Table records: {name:, columns: [{name:, type:, pk:, fk:, null:}]}
      # @param relationships [Array<Hash>] Relationship records: {from:, to:, cardinality_from:, cardinality_to:, label:}
      # @param output_path [String, nil] Where to write .mmd file
      # @return [String] Generated Mermaid markdown
      def self.generate(title, tables, relationships, output_path: nil)
        new(title, tables, relationships).generate(output_path)
      end

      def initialize(title, tables, relationships = [])
        @title         = title
        @tables        = Array(tables)
        @relationships = Array(relationships)
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
        template_path = ENV.fetch("AUTO_DOC_TEMPLATE_ERD", DEFAULT_TEMPLATE)
        template_text = read_template(template_path)

        title         = @title
        tables        = @tables
        relationships = @relationships
        generated_at  = Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")

        ERB.new(template_text).result(binding)
      end
    end
  end
end
