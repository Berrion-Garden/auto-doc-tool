# frozen_string_literal: true

module AutoDoc
  module Transformer
    # Builds class hierarchy from analysis data for the class diagram.
    # Extracts class names, parent classes, includes, and methods.
    # Methods are formatted as Mermaid-compatible strings (e.g., "+method_name()").
    class ClassHierarchyBuilder
      # @param analyses [Hash<String, Hash>] Full analysis data
      # @return [Array<Hash>] Class hierarchy records with :name, :parent, :includes, :extends, :methods
      def self.build(analyses)
        hierarchy = []
        analyses.each_value do |analysis|
          defs = analysis[:definitions] || []
          defs.each do |defn|
            next unless defn.is_a?(Hash) && defn[:type] == :class

            hierarchy << {
              name: defn[:name],
              parent: defn[:parent],
              includes: defn[:includes] || [],
              extends: defn[:extends] || [],
              methods: format_methods(defn[:methods] || [])
            }
          end
        end
        hierarchy
      end

      # Formats a method definition hash as a Mermaid-compatible string.
      # @param methods [Array<Hash>] Array of method hashes with :name key
      # @return [Array<String>] Array of Mermaid method declarations
      def self.format_methods(methods)
        methods.map do |m|
          m_name = m.is_a?(Hash) ? m[:name] : m.to_s
          "+#{m_name}()"
        end
      end

      private_class_method :format_methods
    end
  end
end
