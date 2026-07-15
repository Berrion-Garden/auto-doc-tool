# frozen_string_literal: true

require "erb"
require "fileutils"

module AutoDoc
  module Generator
    # Generates C4 context and container Mermaid diagrams from project metadata.
    # Renders templates/c4_context_template.erb and templates/c4_container_template.erb.
    class C4DiagramGenerator
      include TemplateHelper

      TEMPLATES_DIR = File.expand_path("../../../templates", __dir__).freeze
      CONTEXT_TEMPLATE = File.join(TEMPLATES_DIR, "c4_context_template.erb").freeze
      CONTAINER_TEMPLATE = File.join(TEMPLATES_DIR, "c4_container_template.erb").freeze

      # Generates a C4 context diagram showing external systems and the internal system.
      # @param title [String] Diagram title (e.g., project name)
      # @param external_systems [Array<Hash>] External system records: {name:, interaction:}
      # @param internal_system [Hash] The system under documentation: {name:}
      # @param output_path [String, nil] Where to write .mmd file
      # @return [String] Generated Mermaid markdown
      def self.generate_context(title, external_systems, internal_system, output_path: nil)
        new(:context, title,
            external_systems: external_systems,
            internal_system: internal_system).generate(output_path)
      end

      # Generates a C4 container diagram showing internal modules and data flows.
      # @param title [String] Diagram title (e.g., project name)
      # @param modules [Array<Hash>] Module records: {name:, description:}
      # @param data_flows [Array<Hash>] Data flow records: {from:, to:, label:}
      # @param output_path [String, nil] Where to write .mmd file
      # @return [String] Generated Mermaid markdown
      def self.generate_container(title, modules, data_flows, output_path: nil)
        new(:container, title,
            modules: modules,
            data_flows: data_flows).generate(output_path)
      end

      def initialize(template_key, title, **data)
        @template_key = template_key
        @title = title
        @data = data
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
        template_path = if @template_key == :context
                          ENV.fetch("AUTO_DOC_TEMPLATE_C4_CONTEXT", CONTEXT_TEMPLATE)
                        else
                          ENV.fetch("AUTO_DOC_TEMPLATE_C4_CONTAINER", CONTAINER_TEMPLATE)
                        end
        template_text = read_template(template_path)

        title           = @title
        generated_at    = Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")
        external_systems = @data[:external_systems] || []
        internal_system  = @data[:internal_system] || { name: @title }
        modules          = @data[:modules] || []
        data_flows       = @data[:data_flows] || []

        ERB.new(template_text).result(binding)
      end
    end
  end
end
