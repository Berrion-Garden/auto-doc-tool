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
      # @param analyses [Hash, nil] Analysis data hash from AnalysisPipeline
      # @param auto_doc_config [Object, nil] Config object responding to llm_config
      # @return [String] Generated markdown content
      def self.generate(project_name, schema_tables, models, class_hierarchy, config = {}, output_path: nil, analyses: nil, auto_doc_config: nil)
        new(project_name, schema_tables, models, class_hierarchy, config, analyses: analyses, auto_doc_config: auto_doc_config).generate(output_path)
      end

      def initialize(project_name, schema_tables, models, class_hierarchy, config = {}, analyses: nil, auto_doc_config: nil)
        @project_name    = project_name
        @schema_tables   = Array(schema_tables)
        @models          = Array(models)
        @class_hierarchy = Array(class_hierarchy)
        @config          = config
        @analyses        = analyses
        @auto_doc_config = auto_doc_config
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

        # Try LLM-enhanced generation first
        llm_overview = nil
        llm_style = nil
        llm_modules = nil
        llm_data_flows = nil

        if llm_primary? && @auto_doc_config && @analyses && !@analyses.empty?
          begin
            client = AutoDoc::LLM::Client.build_if_configured(@auto_doc_config)
            if client
              summary = AutoDoc::LLM::Summarizer.summarize_architecture_full(@project_name, @analyses, client)
              if summary.is_a?(Hash)
                llm_overview = summary[:purpose] if summary[:purpose] && !summary[:purpose].empty?
                llm_style    = summary[:style] if summary[:style] && !summary[:style].empty?
                llm_modules  = AutoDoc::LLM::Summarizer.parse_architecture_modules(summary)
                llm_data_flows = AutoDoc::LLM::Summarizer.parse_architecture_data_flows(summary)
              end
            end
          rescue StandardError => e
            warn "LLM unavailable for #{@project_name}: #{e.message}"
          end
        end

        # Use LLM results where available, fall through to model-based logic
        overview = if llm_overview
                     llm_overview
                   else
                     warn_llm_fallback("overview") if llm_primary?
                     @config[:overview] || "No overview provided."
                   end

        # Build modules — prefer LLM, fall back to model-based
        modules = if llm_modules && !llm_modules.empty?
                    llm_modules
                  else
                    warn_llm_fallback("modules") if llm_primary?
                    @models.map do |m|
                      responsibility = if m[:associations] && m[:associations].any?
                                         m[:associations].map { |a| "#{a[:type]} #{a[:target]}" }.join(", ")
                                       else
                                         "Core entity"
                                       end
                      { name: m[:model], responsibility: responsibility }
                    end
                  end

        # Detect or use explicit architecture style
        architecture_style = if llm_style
                               llm_style
                             else
                               warn_llm_fallback("architecture style") if llm_primary?
                               @config[:architecture_style] || detect_architecture_style(modules.size)
                             end

        # Build data flows — prefer LLM, fall back to model-based
        data_flows = if llm_data_flows && !llm_data_flows.empty?
                       llm_data_flows
                     else
                       warn_llm_fallback("data flows") if llm_primary?
                       @models.flat_map do |m|
                         (m[:associations] || []).map do |a|
                           { from: m[:model], to: a[:target], description: "#{a[:type]} relationship" }
                         end
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
