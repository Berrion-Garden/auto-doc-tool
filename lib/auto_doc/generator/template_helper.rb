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

      # Builds an LLM client when LLM is configured as the primary documentation source.
      # Handles both @auto_doc_config (ArchitectureGenerator) and @config (other generators).
      # @return [AutoDoc::LLM::Client, nil] LLM client instance or nil if not available
      def build_llm_client
        return nil unless llm_primary?
        cfg = @auto_doc_config || @config
        AutoDoc::LLM::Client.build_if_configured(cfg)
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

      # Returns true when fail_fast mode is enabled for LLM operations.
      # When true, LLM failures raise LLMError instead of falling back silently.
      def fail_fast?
        cfg = @auto_doc_config || @config
        cfg.respond_to?(:llm_fail_fast?) && cfg.llm_fail_fast?
      end

      # Central handler for LLM call outcomes in generators.
      # Always emits a stderr warning about the failure.
      # When fail_fast mode is active, raises LLMError instead of yielding the fallback block.
      #
      # @param description [String] The field or section being generated (e.g. "overview", "purpose")
      # @yieldreturn [String] Fallback value to use when LLM is unavailable (normal mode only)
      # @return [String] The result of the fallback block (normal mode) or raises LLMError
      # @raise [AutoDoc::LLMError] When fail_fast mode is active
      def handle_llm_failure(description)
        warn_llm_fallback(description) if llm_primary?
        if fail_fast?
          raise AutoDoc::LLMError, "LLM unavailable for #{description}"
        end
        yield if block_given?
      end
    end
  end
end
