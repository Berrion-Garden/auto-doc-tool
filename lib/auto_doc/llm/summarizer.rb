# frozen_string_literal: true

module AutoDoc
  module LLM
    # Builds metadata-only prompts for LLM summarization and parses responses.
    # Delegates prompt construction to PromptBuilder and response parsing to
    # ResponseParser. Never includes full source code — only file names,
    # class/module names, method names, and structural relationships.
    class Summarizer
      class << self
        # Summarizes a specific module directory based on its analyses.
        #
        # @param dir_name [String]  The module/subdirectory name
        # @param analyses [Hash]    Analysis data: { file_path => { definitions:, docs: } }
        # @param client   [Client]  An LLM Client instance
        # @return [String, nil]     Summary text or nil on failure
        def summarize_module(dir_name, analyses, client)
          messages = PromptBuilder.build(:summary, dir_name, analyses)
          client.chat(messages)
        end

        # Summarizes overall project architecture.
        #
        # @param project_name [String]  The project name
        # @param analyses     [Hash]    Analysis data
        # @param client       [Client]  An LLM Client instance
        # @return [String, nil]         Summary text or nil on failure
        def summarize_architecture(project_name, analyses, client)
          messages = PromptBuilder.build(:architecture, project_name, analyses)
          client.chat(messages)
        end

        # Summarizes component relationships across the project.
        #
        # @param analyses [Hash]    Analysis data
        # @param client   [Client]  An LLM Client instance
        # @return [String, nil]     Summary text or nil on failure
        def summarize_components(analyses, client)
          messages = PromptBuilder.build(:components, nil, analyses)
          client.chat(messages)
        end

        # Returns a multi-paragraph architecture overview covering purpose, style,
        # modules, and data flow. The prompt asks for markdown sections but does
        # NOT include source code.
        #
        # @param project_name [String]  The project name
        # @param analyses     [Hash]    Analysis data
        # @param client       [Client]  An LLM Client instance
        # @return [Hash, nil]           Hash with :purpose, :style, :modules, :data_flow keys or nil on failure
        def summarize_architecture_full(project_name, analyses, client)
          messages = PromptBuilder.build(:architecture_full, project_name, analyses)
          response = client.chat(messages)
          return nil if response.nil?

          ResponseParser.parse_architecture_full(response)
        end

        # Returns a structured list of external systems the project interacts with
        # (name + interaction description). The prompt asks for JSON or bullet list format.
        #
        # @param project_name [String]  The project name
        # @param analyses     [Hash]    Analysis data
        # @param client       [Client]  An LLM Client instance
        # @return [Array<Hash>, nil]    Array of {name:, interaction:} hashes or nil on failure
        def summarize_system_context(project_name, analyses, client)
          messages = PromptBuilder.build(:system_context, project_name, analyses)
          response = client.chat(messages)
          return nil if response.nil?

          ResponseParser.parse_system_context(response)
        end

        # Returns container/module descriptions keyed by module root name.
        # Filters analyses to only include files within the given module roots,
        # then includes metadata grouped by root.
        #
        # @param analyses     [Hash]    Analysis data
        # @param module_roots [Array<String>] Module root directory names
        # @param client       [Client]  An LLM Client instance
        # @return [Hash, nil]           Hash of {module_root_name => description_string} or nil on failure
        def summarize_containers(analyses, module_roots, client)
          messages = PromptBuilder.build(:containers, nil, analyses, module_roots)
          response = client.chat(messages)
          return nil if response.nil?

          ResponseParser.parse_containers(response)
        end
      end
    end
  end
end
