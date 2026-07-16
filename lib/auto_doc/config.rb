# frozen_string_literal: true

begin
  require "yaml"
rescue LoadError
  # YAML/psych not available; will use defaults
end
require_relative "utils/yaml_config_loader"

module AutoDoc
  # Configuration loader that reads .autodoc.yml with fallback defaults.
  # CLI flags are merged on top; they take precedence over config values.
  class Config
    DEFAULTS = {
      module_roots: %w[app lib bin],
      exclude_patterns: %w[vendor/**/* node_modules/**/* spec/**/*],
      output: {
        directory: ".docs",
        format: "markdown"
      },
      audit: {
        min_doc_coverage: 80,
        max_module_size: 50
      },
      diagrams: {
        generate_dag: true,
        diagram_directory: "diagrams"
      },
      llm: {
        provider: "openai",
        endpoint: "https://llms.berrion.garden/v1",
        api_key: "autodoc",
        model: "summarizer",
        timeout: 120,
        primary: true,
        fail_fast: false
      }
    }.freeze

    attr_reader :config

    # Loads configuration from the given path.
    # Walks up directory tree looking for .autodoc.yml.
    # Merges any overrides provided (CLI flags take precedence).
    def self.load(path, overrides = {})
      new(path, overrides)
    end

    def initialize(path, overrides = {})
      @path = File.expand_path(path)
      file_config = read_file_config
      @config = deep_merge(DEFAULTS.dup, file_config)
      @config = deep_merge(@config, overrides) unless (overrides || {}).empty?
    end

    # Convenience accessors for nested config keys
    def module_roots
      @config[:module_roots] || DEFAULTS[:module_roots]
    end

    def exclude_patterns
      @config[:exclude_patterns] || DEFAULTS[:exclude_patterns]
    end

    def output_dir
      configured = (@config[:output] && @config[:output][:directory]) || DEFAULTS[:output][:directory]

      # Use the project root from @path (which is expanded in initialize)
      project_root = File.directory?(@path) ? @path : File.dirname(@path)

      # If the configured directory exists on disk, use it
      configured_path = File.join(project_root, configured)
      return configured if File.directory?(configured_path)

      # If configured dir doesn't exist but .autodoc/ does, fall back (migration notice)
      autodoc_path = File.join(project_root, ".autodoc")
      if File.directory?(autodoc_path)
        $stderr.puts "[auto-doc] Notice: Configuration specifies '#{configured}' but '#{File.basename(configured_path)}' not found. " \
                     "Falling back to existing '.autodoc/' directory. " \
                     "Run `auto-doc generate` to migrate to '#{configured}'."
        return ".autodoc"
      end

      # Neither exists, return configured path (will default to .docs)
      configured
    end

    def min_doc_coverage
      audit_config = @config[:audit]
      if audit_config && audit_config.key?(:min_doc_coverage)
        audit_config[:min_doc_coverage]
      else
        DEFAULTS[:audit][:min_doc_coverage]
      end
    end

    def max_module_size
      audit_config = @config[:audit]
      if audit_config && audit_config.key?(:max_module_size)
        audit_config[:max_module_size]
      else
        DEFAULTS[:audit][:max_module_size]
      end
    end

    def generate_dag?
      diagrams = @config[:diagrams]
      return DEFAULTS[:diagrams][:generate_dag] unless diagrams
      diagrams[:generate_dag] != false
    end

    def diagram_directory
      diagrams = @config[:diagrams]
      (diagrams && diagrams[:diagram_directory]) || DEFAULTS[:diagrams][:diagram_directory]
    end

    def llm_config
      @config[:llm] || DEFAULTS[:llm]
    end

    def llm_primary?
      @config.dig(:llm, :primary) == true
    end

    def llm_fail_fast?
      @config.dig(:llm, :fail_fast) == true
    end

    private

    # Walks up from the path looking for .autodoc.yml
    def read_file_config
      dir = @path
      while true
        config_path = File.join(dir, ".autodoc.yml")
        return Utils::YamlConfigLoader.load(config_path) if File.exist?(config_path)

        parent = File.dirname(dir)
        break if parent == dir # reached root
        dir = parent
      end
      {}
    end

    def deep_merge(hash1, hash2)
      result = hash1.dup
      hash2.each do |key, value|
        if result[key].is_a?(Hash) && value.is_a?(Hash)
          result[key] = deep_merge(result[key], value)
        else
          result[key] = value
        end
      end
      result
    end
  end
end
