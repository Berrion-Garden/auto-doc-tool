# frozen_string_literal: true

require "erb"
require "fileutils"

module AutoDoc
  module Generator
    # Generates SUMMARY.md documentation for a Ruby directory.
    # Renders templates/summary_template.erb with inferred purpose,
    # key components, architecture pattern, and dependencies overview.
    class SummaryGenerator
      include TemplateHelper

      TEMPLATES_DIR = File.expand_path("../../../templates", __dir__).freeze

      DEFAULT_TEMPLATE = File.join(TEMPLATES_DIR, "summary_template.erb").freeze

      # Generates a SUMMARY.md file for the given directory.
      # @param dir_name [String] Name of the directory
      # @param analyses [Hash<String, Hash>] Analysis data: { file_path => { definitions:, imports:, docs: } }
      # @param config [AutoDoc::Config] Configuration object
      # @param output_path [String] Where to write SUMMARY.md (default: nil)
      # @return [String] Generated markdown content
      def self.generate(dir_name, analyses, config, output_path: nil)
        new(dir_name, analyses, config).generate(output_path)
      end

      def initialize(dir_name, analyses, config)
        @dir_name = dir_name
        @analyses = analyses
        @config   = config
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
        template_path = ENV.fetch("AUTO_DOC_TEMPLATE_SUMMARY", DEFAULT_TEMPLATE)
        template_text = read_template(template_path)

        dir_name             = @dir_name
        purpose              = llm_purpose || infer_purpose
        key_components       = llm_components || extract_key_components
        architecture_pattern = llm_architecture || infer_architecture_pattern
        dependencies_overview = build_dependencies_overview
        generated_at         = Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")

        ERB.new(template_text).result(binding)
      end

      # Attempts LLM-generated purpose summary. Falls back to nil on any failure.
      def llm_purpose
        return nil unless (client = build_llm_client)
        AutoDoc::LLM::Summarizer.summarize_module(@dir_name, @analyses, client)
      rescue => e
        nil
      end

      # Attempts LLM-generated architecture pattern. Falls back to nil on any failure.
      def llm_architecture
        return nil unless (client = build_llm_client)
        AutoDoc::LLM::Summarizer.summarize_architecture(@dir_name, @analyses, client)
      rescue => e
        nil
      end

      # Attempts LLM-generated component descriptions. Falls back to nil on any failure.
      def llm_components
        return nil unless (client = build_llm_client)
        result = AutoDoc::LLM::Summarizer.summarize_components(@analyses, client)
        return nil unless result
        # Wrap LLM text as a single key component entry
        [{ name: @dir_name, type: "module", summary: result }]
      rescue => e
        nil
      end

      def build_llm_client
        return nil unless @config.respond_to?(:llm_config)
        cfg = @config.llm_config
        return nil unless cfg
        client = AutoDoc::LLM::Client.new(cfg)
        return nil unless client.configured?
        client
      rescue => e
        # LLM is best-effort; silent fallback on any error
        nil
      end

      # Infers a purpose text from the directory name and file names.
      # @return [String] Human-readable purpose description
      def infer_purpose
        case @dir_name
        when "lib"
          "Core library code containing the primary implementation files."
        when "app"
          "Application code including controllers, models, services, and views."
        when "spec", "test"
          "Test and specification files for verifying application behavior."
        when "bin", "exe"
          "Executable entry points and command-line interface scripts."
        when "config"
          "Configuration files for environment, routing, and application setup."
        when "db", "migrate"
          "Database migration files and schema definitions."
        when "docs"
          "Documentation files and supplementary project references."
        else
          file_names = @analyses.keys.map { |fp| File.basename(fp) }
          base_words = @dir_name.split(/[_-]/).map(&:capitalize).join(" ")
          if file_names.any?
            "Ruby source files in the #{base_words} module (#{file_names.size} file(s))."
          else
            "Ruby source files in the #{base_words} directory."
          end
        end
      end

      # Extracts key component summaries from YARD doc data in analyses.
      # Uses definitions that have documented? info, plus doc summaries if available.
      # @return [Array<Hash>] Array of component records with :name, :type, :summary
      def extract_key_components
        components = []
        @analyses.each_value do |analysis|
          defs = analysis[:definitions] || []
          docs = analysis[:docs] || []

          # Build doc lookup: { target_name => doc_record }
          doc_index = docs.each_with_object({}) do |d, h|
            key_name = d[:target_name].to_s.gsub("::", "_")
            h[:"#{d[:target_type]}_#{key_name}"] = d
          end

          defs.each do |defn|
            next unless defn.is_a?(Hash)
            type = defn[:type].to_s.downcase
            next unless [:class, :module].include?(defn[:type])

            # Look up doc summary
            def_name = defn[:name].to_s.gsub("::", "_")
            doc_key  = :"#{defn[:type]}_#{def_name}"
            doc_rec  = doc_index[doc_key]
            summary  = if doc_rec && doc_rec[:summary] && !doc_rec[:summary].empty?
                         doc_rec[:summary]
                       elsif defn[:has_doc?]
                         "#{type.capitalize} documented in source."
                       else
                         "No documentation available."
                       end

            components << { name: defn[:name], type: type, summary: summary }
          end
        end
        components.sort_by! { |c| c[:name].to_s.downcase }
        components.first(20) # Limit to top 20 to keep summary concise
      end

      # Infers architecture pattern from directory structure and content.
      # @return [String] Description of architecture pattern
      def infer_architecture_pattern
        file_names = @analyses.keys.map { |fp| File.basename(fp) }
        all_names  = file_names.join(" ").downcase

        if all_names.include?("controller") || all_names.include?("model") || all_names.include?("view")
          "Model-View-Controller (MVC) — organized around models, views, and controllers."
        elsif all_names.include?("service") || all_names.include?("interactor")
          "Service-oriented — core logic encapsulated in service objects."
        elsif all_names.include?("serializer") || all_names.include?("representer")
          "Presentation-focused — data transformation and serialization pattern."
        elsif @dir_name == "lib"
          "Modular library — organized as a collection of reusable modules and classes."
        else
          "Modular composition — components organized by domain responsibility."
        end
      end

      # Builds dependencies overview from import data.
      # @return [Array<Hash>] Array of dependency records with :name and :type
      def build_dependencies_overview
        deps_map = {}
        @analyses.each_value do |analysis|
          imports = analysis[:imports] || []
          imports.each do |imp|
            dep_name = imp[:path].to_s
            next if dep_name.empty?

            # Group: stdlib gems vs local requires vs relative requires
            category = if dep_name.start_with?(".")
                         "local"
                       elsif dep_name.include?("/")
                         "path"
                       else
                         "stdlib/gem"
                       end

            deps_map[dep_name] = { name: dep_name, type: category } unless deps_map.key?(dep_name)
          end
        end

        deps_map.values.sort_by { |d| d[:name].downcase }
      end

    end
  end
end
