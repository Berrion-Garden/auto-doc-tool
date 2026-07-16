# frozen_string_literal: true

module AutoDoc
  module Generator
    # Shared template reading logic for all generators.
    # Included by generator classes to avoid duplicating read_template.
    module TemplateHelper
      # Read a template file from disk by its full path.
      # Raises if the file does not exist.
      #
      # @param path [String] Full path to the template file
      # @return [String] Template content with UTF-8 encoding forced
      def read_template(path)
        raise "Template not found: #{path}" unless File.exist?(path)

        content = File.read(path)
        content.force_encoding("UTF-8")
      rescue Errno::ENOENT
        raise
      end

      # Returns true when the config has LLM as the primary documentation source.
      # Handles both @auto_doc_config (ArchitectureGenerator) and @config (other generators).
      def llm_primary?
        cfg = @auto_doc_config || @config
        cfg.respond_to?(:llm_primary?) && cfg.llm_primary?
      end

      # Emits a consistent stderr warning when LLM fails in primary mode.
      # @param description [String] The field or section being generated (e.g. "overview", "purpose")
      def warn_llm_fallback(description)
        name = @dir_name || @project_name || @module_name || "unknown"
        $stderr.puts "[AutoDoc] LLM unavailable for #{name} #{description} — using static inference."
      end
    end
  end
end
