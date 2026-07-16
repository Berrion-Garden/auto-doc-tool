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
      # @param config [AutoDoc::Config, nil] Configuration object (optional; enables LLM summaries)
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
        purpose_summary   = llm_purpose_summary
        dependencies      = []

        ERB.new(template_text).result(binding)
      end

      # Attempts LLM-generated module purpose summary. Falls back to nil on any failure.
      def llm_purpose_summary
        return nil if @config.nil?
        return nil unless @config.respond_to?(:llm_config)
        cfg = @config.llm_config
        return nil unless cfg
        client = AutoDoc::LLM::Client.new(cfg)
        return nil unless client.configured?
        AutoDoc::LLM::Summarizer.summarize_module(@module_name, build_analyses, client)
      rescue => e
        nil
      end

      # Builds a simplified analyses hash from files data for the LLM summarizer.
      def build_analyses
        analyses = {}
        @files.each do |file_info|
          path = file_info[:path] || "#{@module_name}/#{file_info[:name]}"
          defs = (file_info[:classes] || []).map do |c|
            { name: c[:name], type: c[:type], has_doc?: c[:has_doc?] }
          end
          analyses[path] = { definitions: defs, docs: [], imports: file_info[:imports] || [] }
        end
        analyses
      end

      def build_public_symbols(files)
        symbols = []
        files.each do |file_info|
          (file_info[:classes] || []).each do |defn|
            next unless defn.is_a?(Hash)
            type = defn[:type].to_s.downcase
            next unless [:class, :module, :method].include?(defn[:type])
            symbols << {
              name:     defn[:name],
              type:     type,
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
