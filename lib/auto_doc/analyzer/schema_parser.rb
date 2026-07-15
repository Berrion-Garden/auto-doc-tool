# frozen_string_literal: true

module AutoDoc
  module Analyzer
    # Parses Rails db/schema.rb and db/migrate/ to extract table schemas,
    # column definitions, indexes, foreign keys, and migration timestamps.
    class SchemaParser
      # Parses a Rails project's db/schema.rb for table definitions.
      # @param project_dir [String] Path to the Rails project root
      # @return [Array<Hash>] Array of table hashes:
      #   { table_name: String, columns: [{name:, type:, null:, default:}],
      #     indexes: [{name:, columns:}], foreign_keys: [{from_table:, to_table:, column:}],
      #     migration_timestamps: [String] }
      def self.parse(project_dir)
        new(project_dir).parse
      end

      def initialize(project_dir)
        @project_dir = project_dir
      end

      # @return [Array<Hash>] Parsed table definitions
      def parse
        schema_path = File.join(@project_dir, "db", "schema.rb")
        return [] unless File.exist?(schema_path)

        content = File.read(schema_path, encoding: "UTF-8")
        return [] if content.strip.empty?

        tables = parse_tables(content)
        parse_foreign_keys!(content, tables)
        migration_ts = migration_timestamps

        tables.each { |t| t[:migration_timestamps] = migration_ts }
        tables
      end

      private

      def parse_tables(content)
        tables = []
        current_table = nil

        content.each_line do |line|
          stripped = line.strip
          next if stripped.empty? || stripped.start_with?("#")

          if stripped =~ /create_table\s+"([^"]+)"/
            table_name = Regexp.last_match(1)
            current_table = {
              table_name: table_name,
              columns: [],
              indexes: [],
              foreign_keys: [],
              migration_timestamps: []
            }
            tables << current_table
          elsif stripped == "end" && current_table
            current_table = nil
          elsif current_table
            parse_column_line(stripped, current_table)
            parse_index_line(stripped, current_table)
          end
        end

        tables
      end

      def parse_column_line(stripped, table)
        match = stripped.match(/\At\.(string|integer|datetime|boolean|text|bigint|float|decimal|date|time|binary)\s+(?:"([^"]+)"|:(\w+))/)
        return unless match

        col_type = match[1]
        col_name = match[2] || match[3]
        null_val = !stripped.include?("null: false")

        # Extract default value
        default_val = stripped[/default:\s+([^,\s]+)/, 1]

        table[:columns] << {
          name: col_name,
          type: col_type,
          null: null_val,
          default: default_val
        }
      end

      def parse_index_line(stripped, table)
        match = stripped.match(/\At\.index\s+\["([^"]+)"\](?:,\s*name:\s+"([^"]+)")?/)
        return unless match

        table[:indexes] << {
          name: match[2],
          columns: [match[1]]
        }
      end

      def parse_foreign_keys!(content, tables)
        content.each_line do |line|
          stripped = line.strip
          match = stripped.match(/\Aadd_foreign_key\s+"([^"]+)",\s+"([^"]+)"/)
          next unless match

          from_table = match[1]
          to_table = match[2]

          table = tables.find { |t| t[:table_name] == from_table }
          next unless table

          # Infer the FK column name: singularize to_table + _id
          fk_column = if to_table.end_with?("s")
                        "#{to_table[0..-2]}_id"
                      else
                        "#{to_table}_id"
                      end

          table[:foreign_keys] << {
            from_table: from_table,
            to_table: to_table,
            column: fk_column
          }
        end
      end

      def migration_timestamps
        migrate_dir = File.join(@project_dir, "db", "migrate")
        return [] unless File.directory?(migrate_dir)

        Dir.glob(File.join(migrate_dir, "*.rb")).filter_map do |path|
          basename = File.basename(path)
          match = basename.match(/\A(\d{14})_/)
          match[1] if match
        end.sort
      end
    end
  end
end
