# frozen_string_literal: true

require "erb"
require "fileutils"

module AutoDoc
  module Generator
    # Generates an architecture.md document from project analysis data.
    # Renders templates/architecture_template.erb with sections for overview,
    # architecture style, module map, data flow, design decisions, and diagram links.
    class ArchitectureGenerator
      include TemplateHelper

      TEMPLATES_DIR = File.expand_path("../../../templates", __dir__).freeze
      DEFAULT_TEMPLATE = File.join(TEMPLATES_DIR, "architecture_template.erb").freeze

      # Generates an architecture markdown document.
      # @param project_name [String] Name of the project
      # @param schema_tables [Array] Table data from SchemaParser
      # @param models [Array] Model data from ModelAssociationParser
      # @param class_hierarchy [Array] Class hierarchy for class diagram
      # @param config [Hash] Configuration: {architecture_style:, overview:, design_decisions:, diagram_links:}
      # @param output_path [String, nil] Where to write .md file
      # @return [String] Generated markdown content
      def self.generate(project_name, schema_tables, models, class_hierarchy, config = {}, output_path: nil)
        new(project_name, schema_tables, models, class_hierarchy, config).generate(output_path)
      end

      def initialize(project_name, schema_tables, models, class_hierarchy, config = {})
        @project_name   = project_name
        @schema_tables  = Array(schema_tables)
        @models         = Array(models)
        @class_hierarchy = Array(class_hierarchy)
        @config         = config
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
        template_path = ENV.fetch("AUTO_DOC_TEMPLATE_ARCHITECTURE", DEFAULT_TEMPLATE)
        template_text = read_template(template_path)

        title            = @project_name
        generated_at     = Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")
        overview         = @config[:overview] || "No overview provided."
        design_decisions = @config[:design_decisions] || []
        diagram_links    = @config[:diagram_links] || []

        # Build modules from model data
        modules = @models.map do |m|
          responsibility = if m[:associations] && m[:associations].any?
                             m[:associations].map { |a| "#{a[:type]} #{a[:target]}" }.join(", ")
                           else
                             "Core entity"
                           end
          { name: m[:model], responsibility: responsibility }
        end

        # Detect or use explicit architecture style
        architecture_style = @config[:architecture_style] || detect_architecture_style(modules.size)

        # Build data flows from model associations
        data_flows = @models.flat_map do |m|
          (m[:associations] || []).map do |a|
            { from: m[:model], to: a[:target], description: "#{a[:type]} relationship" }
          end
        end

        ERB.new(template_text).result(binding)
      end

      def detect_architecture_style(module_count)
        if module_count <= 1
          "Monolithic"
        elsif module_count <= 3
          "Modular Monolith"
        else
          "Microservices"
        end
      end
    end
  end
end
