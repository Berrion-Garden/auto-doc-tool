# frozen_string_literal: true

module AutoDoc
  module Transformer
    # Builds ERD relationship records from model associations and schema tables.
    # Derives cardinality from association types (has_many -> one-to-many).
    class ERDRelationshipBuilder
      # @param models [Array<Hash>, nil] Model association data
      # @param _schema_tables [Array<Hash>, nil] Schema table data (unused, kept for API consistency)
      # @return [Array<Hash>] Relationship records with :from, :to, :cardinality_from, :cardinality_to, :label
      def self.build(models, _schema_tables = nil)
        return [] unless models

        models.flat_map do |m|
          (m[:associations] || []).map do |a|
            cardinality_from = a[:type] == "belongs_to" ? "many" : "one"
            cardinality_to   = a[:type] == "belongs_to" ? "one" : "many"
            {
              from: m[:table],
              to: a[:target_table] || a[:target].to_s.downcase,
              cardinality_from: cardinality_from,
              cardinality_to: cardinality_to,
              label: a[:type]
            }
          end
        end
      end
    end
  end
end
