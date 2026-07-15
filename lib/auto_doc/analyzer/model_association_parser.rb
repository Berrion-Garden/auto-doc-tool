# frozen_string_literal: true

module AutoDoc
  module Analyzer
    # Parses Rails model files from app/models/ to extract ActiveRecord
    # associations (has_many, belongs_to, has_one, has_and_belongs_to_many)
    # and their options.
    class ModelAssociationParser
      # Parses all model files in a Rails project's app/models/ directory.
      # @param project_dir [String] Path to the Rails project root
      # @return [Array<Hash>] Array of model hashes:
      #   { model: String, table: String,
      #     associations: [{type: String, target: String, options: Hash}] }
      def self.parse(project_dir)
        new(project_dir).parse
      end

      ASSOCIATION_TYPES = %w[has_many belongs_to has_one has_and_belongs_to_many].freeze

      def initialize(project_dir)
        @project_dir = project_dir
      end

      # @return [Array<Hash>] Parsed model definitions with associations
      def parse
        models_dir = File.join(@project_dir, "app", "models")
        return [] unless File.directory?(models_dir)

        Dir.glob(File.join(models_dir, "*.rb")).filter_map do |path|
          parse_model_file(path)
        end
      end

      private

      def parse_model_file(path)
        content = File.read(path, encoding: "UTF-8")
        return nil if content.strip.empty?

        model_name = extract_model_name(content)
        return nil unless model_name

        table_name = extract_table_name(content, model_name)
        associations = extract_associations(content)

        {
          model: model_name,
          table: table_name,
          associations: associations
        }
      end

      def extract_model_name(content)
        match = content.match(/^\s*(?:class|module)\s+(\w+)/)
        match ? match[1] : nil
      end

      def extract_table_name(content, model_name)
        # Check for self.table_name = override
        override_match = content.match(/self\.table_name\s*=\s*["']([^"']+)["']/)
        return override_match[1] if override_match

        # Standard Rails convention: CamelCase → snake_case + pluralize
        # Simple pluralization: append "s"
        snake = model_name.gsub(/([A-Z])/) { "_#{$1}" }.sub(/\A_/, "").downcase
        # Basic pluralization rules
        pluralize(snake)
      end

      def pluralize(word)
        # Very basic English pluralization for test purposes
        case word
        when /s$/i then word + "es"
        when /y$/i then word.sub(/y$/, "ies")
        else word + "s"
        end
      end

      def extract_associations(content)
        associations = []
        content.each_line do |line|
          stripped = line.strip
          next if stripped.start_with?("#")

          assoc_match = stripped.match(/\A(has_many|belongs_to|has_one|has_and_belongs_to_many)\s+(?::(\w+)|\"{1}([^\"]+)\"{1})/)
          next unless assoc_match

          type = assoc_match[1]
          target = assoc_match[2] || assoc_match[3]
          options = extract_options(stripped)

          associations << {
            type: type,
            target: target,
            options: options
          }
        end
        associations
      end

      def extract_options(line)
        options = {}
        # Match options hash after the association name
        opts_match = line.match(/,(\s*.*)/)
        return options unless opts_match

        opts_str = opts_match[1].strip
        return options if opts_str.empty? || opts_str.start_with?("#")

        # Parse key: value pairs inside { }
        if opts_str.start_with?("{")
          # inline hash
          opts_str.scan(/(\w+):\s+([^,}\s]+)/) do |key, value|
            options[key.to_sym] = parse_option_value(value)
          end
        else
          # bare keyword arguments style
          opts_str.scan(/(\w+):\s+([^,}\s]+)/) do |key, value|
            options[key.to_sym] = parse_option_value(value)
          end
        end

        options
      end

      def parse_option_value(value)
        case value
        when /\Atrue\z/ then true
        when /\Afalse\z/ then false
        when /\A:(\w+)\z/ then $1.to_sym # Symbol value
        when /\A"([^"]*)"\z/ then ::Regexp.last_match(1)
        else value
        end
      end
    end
  end
end
