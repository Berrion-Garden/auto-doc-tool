# frozen_string_literal: true

require "erb"
require "fileutils"

module AutoDoc
  module Generator
    # Generates AGENTS.md documentation for a Ruby module directory.
    # Renders templates/agents_md_template.erb with analysis data.
    class AgentsMdGenerator
      include TemplateHelper

      TEMPLATES_DIR = File.expand_path("../../../templates", __dir__).freeze

      DEFAULT_TEMPLATE = File.join(TEMPLATES_DIR, "agents_md_template.erb").freeze

      # Generates an AGENTS.md file for the given module.
      # @param module_name [String] Name of the module
      # @param tree_text [String] Directory tree output string
      # @param files [Array<Hash>] Array of file analysis records: {name:, path:, classes:[], imports:[]}
      # @param config [AutoDoc::Config, nil] Optional configuration object for LLM integration
      # @param output_path [String] Where to write AGENTS.md (default: ".autodoc/AGENTS.md")
      # @return [String] Generated markdown content
      def self.generate(module_name, tree_text, files, config: nil, output_path: nil)
        new(module_name, tree_text, files, config).generate(output_path)
      end

      def initialize(module_name, tree_text, files, config = nil)
        @module_name = module_name
        @tree_text   = tree_text
        @files       = files
        @config      = config
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
        template_path = ENV.fetch("AUTO_DOC_TEMPLATE", DEFAULT_TEMPLATE)
        template_text = read_template(template_path)

        module_name  = @module_name
        tree_text    = @tree_text
        files      = @files
        generated_at = Time.now.strftime("%Y-%m-%d %H:%M:%S %Z")

        # Derived variables for the template binding
        source_file_count = files.size
        public_symbols    = build_public_symbols(files)
        public_symbol_count = public_symbols.size
        dependencies      = []

        purpose_summary = if llm_primary?
                             llm_purpose_summary || (warn_llm_fallback("purpose summary"); "⚠ LLM unavailable — static summary")
                           else
                             "developer to fill in"
                           end

        ERB.new(template_text).result(binding)
      end

      # Attempts LLM-generated purpose summary, falling back to nil on any failure.
      def llm_purpose_summary
        return nil unless (client = build_llm_client)
        analyses = build_analyses(@files)
        result = AutoDoc::LLM::Summarizer.summarize_module(@module_name, analyses, client)
        return nil if result.to_s.strip.empty?
        result
      rescue
        nil
      end

      def build_llm_client
        AutoDoc::LLM::Client.build_if_configured(@config)
      end

      # Converts file analysis records into the analyses hash format expected by Summarizer.
      #
      # @param files [Array<Hash>] Array of file analysis records with :path, :classes, etc.
      # @return [Hash] Analyses hash: { file_path => { definitions: [...] } }
      def build_analyses(files)
        analyses = {}
        files.each do |file_info|
          path = file_info[:path] || file_info[:name]
          defs = (file_info[:classes] || []).map do |cls|
            { name: cls[:name], type: cls[:type] || "class", has_doc?: cls[:has_doc?] == true }
          end
          analyses[path] = { definitions: defs } unless defs.empty?
        end
        analyses
      end

      def build_public_symbols(files)
        return nil if files.nil?
        symbols = []
        files.each do |file_info|
          (file_info[:classes] || []).each do |defn|
            next unless defn.is_a?(Hash)
            type_sym = defn[:type].to_s.downcase.to_sym
            next unless %i[class module method].include?(type_sym)
            symbols << {
              name:     defn[:name],
              type:     type_sym.to_s,
              line:     defn[:line] || 0,
              has_doc?: (defn[:has_doc?] == true)
            }
          end
        end
        symbols.sort_by! { |s| s[:name].to_s.downcase }
      end

    end
  end
end
