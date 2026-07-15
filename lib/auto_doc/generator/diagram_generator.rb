# frozen_string_literal: true

require "erb"
require "fileutils"

module AutoDoc
  module Generator
    # Generates a Mermaid dependency DAG diagram from import analysis.
    # Renders templates/diagram_dag_template.erb with graph nodes and edges.
    class DiagramGenerator
      include TemplateHelper

      TEMPLATES_DIR = File.expand_path("../../../templates", __dir__).freeze
      DEFAULT_TEMPLATE = File.join(TEMPLATES_DIR, "diagram_dag_template.erb").freeze

      # Generates a Mermaid DAG diagram from import data.
      # @param title [String] Diagram title (e.g., project name)
      # @param graph_nodes [Array<String>] Node labels for the diagram
      # @param graph_edges [Array<Hash>] Edge records: {from:, to:, type:}
      # @param output_path [String] Where to write .mmd file (default: ".autodoc/diagrams/deps.mmd")
      # @return [String] Generated markdown content containing the mermaid block
      def self.generate(title, graph_nodes, graph_edges, output_path: nil)
        new(title, graph_nodes, graph_edges).generate(output_path)
      end

      def initialize(title, graph_nodes, graph_edges)
        @title       = title
        @graph_nodes = Array(graph_nodes)
        @graph_edges = Array(graph_edges)
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
        template_path = ENV.fetch("AUTO_DOC_TEMPLATE_DIAGRAM", DEFAULT_TEMPLATE)
        template_text = read_template(template_path)

        title       = @title
        graph_nodes = @graph_nodes
        graph_edges = @graph_edges
        generated_at = Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")

        ERB.new(template_text).result(binding)
      end

    end
  end
end
