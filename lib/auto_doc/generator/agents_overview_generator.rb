# frozen_string_literal: true

require "erb"
require "fileutils"
require "set"

module AutoDoc
  module Generator
    # Generates a project-root AGENTS.md for AI agent consumption.
    # Uses LLM (when primary mode) for rich content generation across sections:
    # project overview, technology stack, architecture, conventions, dependencies.
    # Falls back to static placeholder content when LLM is unavailable.
    class AgentsOverviewGenerator
      include TemplateHelper

      TEMPLATES_DIR = File.expand_path("../../../templates", __dir__).freeze
      DEFAULT_TEMPLATE = File.join(TEMPLATES_DIR, "agents_overview_template.erb").freeze

      # @param project_name [String] Name of the project
      # @param analyses [Hash] Full analysis data: { file_path => { definitions:, imports: } }
      # @param module_roots [Array<String>] Module root directory paths
      # @param tree_text [String] Combined directory tree text
      # @param config [AutoDoc::Config, nil] Configuration with LLM settings
      # @param output_path [String, nil] Where to write AGENTS.md
      # @return [String] Generated markdown content
      def self.generate(project_name, analyses, module_roots, tree_text, config: nil, output_path: nil)
        new(project_name, analyses, module_roots, tree_text, config).generate(output_path)
      end

      def initialize(project_name, analyses, module_roots, tree_text, config = nil)
        @project_name = project_name
        @analyses     = analyses
        @module_roots = module_roots
        @tree_text    = tree_text
        @config       = config
      end

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
        template_path = ENV.fetch("AUTO_DOC_TEMPLATE_AGENTS_OVERVIEW", DEFAULT_TEMPLATE)
        template_text = read_template(template_path)

        project_name  = @project_name
        tree_text     = @tree_text
        generated_at  = Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")

        # Derived data for template
        module_count = @module_roots.size
        total_files  = @analyses.size

        # Detect tech stack from file extensions and import statements
        tech_stack   = detect_technology_stack(@analyses)

        # Aggregate external dependencies from import statements across all analyses
        external_deps = aggregate_external_dependencies(@analyses)

        # LLM-generated sections (nil when not primary, placeholder when failed)
        llm_overview         = llm_generate_section(:agents_overview_overview)
        llm_tech_stack       = llm_generate_section(:agents_overview_tech_stack)
        llm_architecture     = llm_generate_section(:agents_overview_architecture)
        llm_conventions      = llm_generate_section(:agents_overview_conventions)

        # Fallback content — use LLM if available in primary mode, otherwise static
        overview_text    = if llm_primary?
                              llm_overview || handle_llm_failure("project overview") { "⚠ LLM unavailable — project overview" }
                            else
                              "developer to fill in"
                            end

        tech_stack_text  = if llm_primary?
                              llm_tech_stack || handle_llm_failure("tech stack") { tech_stack_description(tech_stack) }
                            else
                              "developer to fill in"
                            end

        architecture_text = if llm_primary?
                               llm_architecture || handle_llm_failure("architecture") { "⚠ LLM unavailable — architecture" }
                             else
                               "developer to fill in"
                             end

        conventions_text = if llm_primary?
                              llm_conventions || handle_llm_failure("conventions") { "⚠ LLM unavailable — conventions" }
                            else
                              "developer to fill in"
                            end

        ERB.new(template_text).result(binding)
      end

      # --- LLM section generators ---

      def llm_generate_section(prompt_type)
        return nil unless (client = build_llm_client)
        messages = AutoDoc::LLM::PromptBuilder.build(prompt_type, @project_name, @analyses)
        client.chat(messages)
      rescue
        nil
      end

      # --- Static detection helpers ---

      def detect_technology_stack(analyses)
        extensions = Hash.new(0)
        imports = Hash.new(0)

        analyses.each_key do |file_path|
          ext = File.extname(file_path).downcase
          extensions[ext] += 1

          analysis = analyses[file_path]
          if analysis && analysis[:imports]
            analysis[:imports].each do |import|
              target = import.is_a?(Hash) ? (import[:path] || import[:target]) : import.to_s
              imports[target] += 1 if target
            end
          end
        end

        { extensions: extensions, imports: imports }
      end

      def tech_stack_description(tech_stack)
        parts = []
        exts = tech_stack[:extensions]
        if exts[".rb"].to_i > 0
          ruby_frameworks = []
          imports = tech_stack[:imports]
          ruby_frameworks << "Rails" if imports.keys.any? { |k| k&.include?("rails") || k&.include?("active_record") || k&.include?("action_") }
          ruby_frameworks << "Sinatra" if imports.keys.any? { |k| k&.include?("sinatra") }
          framework_text = ruby_frameworks.any? ? " (#{ruby_frameworks.join(", ")})" : ""
          parts << "Ruby#{framework_text}"
        end
        exts.each do |ext, count|
          next if ext == ".rb"
          parts << ext.sub(/^\./, "").capitalize if count > 0
        end
        parts.any? ? parts.join(", ") : "developer to fill in"
      end

      def aggregate_external_dependencies(analyses)
        deps = []
        seen = Set.new

        analyses.each_value do |analysis|
          next unless analysis && analysis[:imports]
          analysis[:imports].each do |import|
            target = import.is_a?(Hash) ? (import[:path] || import[:target] || import.to_s) : import.to_s
            next if target.nil? || target.start_with?(".") || target.start_with?("/") # Skip relative/absolute requires
            next if seen.include?(target)
            seen.add(target)
            type = import.is_a?(Hash) ? import[:type] : "require"
            deps << { name: target, type: type }
          end
        end

        deps.sort_by { |d| d[:name] }
      end
    end
  end
end
