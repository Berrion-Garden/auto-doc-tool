# frozen_string_literal: true

require "json"
require "fileutils"

module AutoDoc
  module Generator
    # Generates VECTORS.json files for project-level and directory-level
    # symbol indexing. Each vector entry contains metadata about a symbol
    # (class, module, or method) for cross-referencing and search.
    #
    # Entries include: id, symbol, type, scope, file, line, summary,
    # signature, visibility, keywords, dependencies, consumed_by, parent_module.
    class VectorGenerator
      STOP_WORDS = %w[
        the a an and or of in to for on with at by from as is it
        be has have do does not no yes this that these those
      ].freeze

      # Generates project-level vector data from all analyses.
      # @param analyses [Hash<String, Hash>] Full project analysis data
      # @param _config [AutoDoc::Config] Configuration object (unused)
      # @param llm_summaries [Hash<String, String>, nil] Optional map of entry_id => LLM summary text
      # @return [Hash] Project-level vectors hash with :symbols array
      def self.generate_project(analyses, _config = nil, llm_summaries: nil)
        build_vectors(analyses, llm_summaries: llm_summaries)
      end

      # Generates directory-level vector data from filtered analyses.
      # @param _dir_name [String] Directory name (for filtering context)
      # @param dir_analyses [Hash<String, Hash>] Analyses filtered to this directory
      # @param _config [AutoDoc::Config] Configuration object (unused)
      # @param llm_summaries [Hash<String, String>, nil] Optional map of entry_id => LLM summary text
      # @return [Hash] Directory-level vectors hash with :symbols array
      def self.generate_directory(_dir_name, dir_analyses, _config = nil, llm_summaries: nil)
        build_vectors(dir_analyses, llm_summaries: llm_summaries)
      end

      # Writes vector data as pretty-printed JSON to the given path.
      # @param output_path [String] File path to write JSON to
      # @param data [Hash] Vector data hash (from generate_project or generate_directory)
      # @return [void]
      def self.write(output_path, data)
        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, JSON.pretty_generate(data))
      end

      # Extracts up to 15 keywords from natural language text by
      # tokenizing, lowercasing, removing punctuation and stop words.
      # @param text [String] Natural language text (e.g., LLM summary)
      # @return [Array<String>] Top 15 normalized keywords
      def self.extract_keywords_from_text(text)
        text.to_s.split(/\s+/)
            .map(&:downcase)
            .map { |w| w.gsub(/[^a-z0-9]/, "") }
            .reject { |w| w.length < 3 }
            .reject { |w| STOP_WORDS.include?(w) }
            .uniq
            .first(15)
      end

      # Extracts up to 15 keywords from a symbol name by splitting
      # CamelCase and snake_case, deduplicating, and removing stop words.
      # @param name [String] Symbol name (e.g., "AgentsMdGenerator", "foo_bar")
      # @return [Array<String>] Top 15 normalized keywords
      def self.keyword_extraction(name, summary_text = nil)
        words = []

        # Split CamelCase
        words.concat(name.to_s.split(/(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])/))

        # Split snake_case
        words = words.flat_map { |w| w.split(/[_-]/) }

        # Split on any remaining non-word characters
        words = words.flat_map { |w| w.split(/[^a-zA-Z0-9]/) }

        # Remove empty strings, stop words, deduplicate, downcase
        words = words.reject(&:empty?)
                     .reject { |w| STOP_WORDS.include?(w.downcase) }
                     .map(&:downcase)
                     .uniq

        # Merge with summary-derived keywords when summary_text is provided
        if summary_text && !summary_text.empty?
          summary_keywords = extract_keywords_from_text(summary_text)
          words = (words + summary_keywords).uniq
        end

        words.first(15)
      end

      # Builds a doc lookup index from docs array.
      # @param docs [Array<Hash>] Array of doc records with :target_name, :target_type, :summary, etc.
      # @return [Hash] Lookup index keyed by ":type_name" symbols
      def self.build_doc_index(docs)
        docs.each_with_object({}) do |d, h|
          key_name = d[:target_name].to_s.gsub("::", "_")
          h[:"#{d[:target_type]}_#{key_name}"] = d
        end
      end

      # Builds a single vector entry hash from a definition, file path, and doc index.
      # @param defn [Hash] Definition hash with :name, :type, :line, :has_doc?, :signature, :visibility, etc.
      # @param file_path [String] Full file path
      # @param doc_index [Hash] Doc lookup index
      # @param llm_summaries [Hash<String, String>, nil] Optional map of entry_id => LLM summary text
      # @return [Hash] Vector entry with standard schema
      def self.build_vector_entry(defn, file_path, doc_index, llm_summaries = nil)
        type      = defn[:type].to_s.downcase
        type_prefix = type.to_s
        def_name  = defn[:name].to_s.gsub("::", "_")
        entry_id  = "#{type_prefix}_#{def_name}"

        doc_key = :"#{defn[:type]}_#{def_name}"
        doc_rec = doc_index[doc_key]
        summary = if doc_rec && doc_rec[:summary] && !doc_rec[:summary].empty?
                    doc_rec[:summary]
                  else
                    ""
                  end

        signature = defn[:signature] || defn[:name].to_s

        llm_summary_text = llm_summaries.is_a?(Hash) ? llm_summaries[entry_id] : nil

        entry = {
          id:            entry_id,
          symbol:        defn[:name].to_s,
          type:          type,
          scope:         "public",
          file:          file_path,
          line:          defn[:line] || 0,
          summary:       summary,
          signature:     signature.to_s,
          visibility:    defn[:visibility] || "public",
          keywords:      llm_summary_text ? extract_keywords_from_text(llm_summary_text) : keyword_extraction(defn[:name].to_s, summary),
          dependencies:  defn[:dependencies] || [],
          consumed_by:   [],
          parent_module: defn[:parent_module]
        }

        entry[:llm_summary] = llm_summary_text if llm_summary_text

        entry
      end

      # Builds vector data from analyses by iterating definitions and building entries.
      # Shared by both generate_project and generate_directory.
      # @param analyses [Hash<String, Hash>] Analysis data
      # @param llm_summaries [Hash<String, String>, nil] Optional map of entry_id => LLM summary text
      # @return [Hash] Vectors hash with :symbols array
      def self.build_vectors(analyses, llm_summaries: nil)
        symbols = []
        analyses.each do |file_path, analysis|
          defs = analysis[:definitions] || []
          docs = analysis[:docs] || []

          doc_index = build_doc_index(docs)

          defs.each do |defn|
            next unless defn.is_a?(Hash)
            symbols << build_vector_entry(defn, file_path, doc_index, llm_summaries)
          end
        end

        { symbols: symbols, generated_at: Time.now.utc.iso8601 }
      end

      private_class_method :build_doc_index, :build_vector_entry, :build_vectors
    end
  end
end
