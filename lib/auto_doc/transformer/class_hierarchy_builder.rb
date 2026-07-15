# frozen_string_literal: true

module AutoDoc
  module Transformer
    # Builds class hierarchy from analysis data for the class diagram.
    # Extracts class names, parent classes, includes, and methods.
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
              methods: defn[:methods] || []
            }
          end
        end
        hierarchy
      end
    end
  end
end
