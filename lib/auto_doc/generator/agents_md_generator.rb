# frozen_string_literal: true

require "erb"
require "fileutils"

module AutoDoc
  module Generator
    # Generates AGENTS.md documentation for a Ruby module directory.
    # Renders templates/agents_md_template.erb with analysis data.
    class AgentsMdGenerator
      TEMPLATES_DIR = File.expand_path("../../../templates", __dir__).freeze

      DEFAULT_TEMPLATE = File.join(TEMPLATES_DIR, "agents_md_template.erb").freeze

      # Generates an AGENTS.md file for the given module.
      # @param module_name [String] Name of the module
      # @param tree_text [String] Directory tree output string
      # @param files [Array<Hash>] Array of file analysis records: {name:, path:, classes:[], imports:[]}
      # @param output_path [String] Where to write AGENTS.md (default: ".autodoc/AGENTS.md")
      # @return [String] Generated markdown content
      def self.generate(module_name, tree_text, files, output_path: nil)
        new(module_name, tree_text, files).generate(output_path)
      end

      def initialize(module_name, tree_text, files)
        @module_name = module_name
        @tree_text   = tree_text
        @files       = files
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
        purpose_summary   = nil
        dependencies      = []

        ERB.new(template_text).result(binding)
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

      def read_template(path)
        raise "Template not found: #{path}" unless File.exist?(path)
        content = File.read(path)
        content.force_encoding("UTF-8")
      rescue Errno::ENOENT
        raise
      end
    end
  end
end
