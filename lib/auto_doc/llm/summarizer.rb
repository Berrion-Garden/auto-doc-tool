# frozen_string_literal: true

module AutoDoc
  module LLM
    # Builds metadata-only prompts for LLM summarization.
    # Never includes full source code — only file names, class/module names,
    # method names, and structural relationships extracted from analyses.
    class Summarizer
      class << self
        # Summarizes a specific module directory based on its analyses.
        #
        # @param dir_name [String]  The module/subdirectory name
        # @param analyses [Hash]    Analysis data: { file_path => { definitions:, docs: } }
        # @param client   [Client]  An LLM Client instance
        # @return [String, nil]     Summary text or nil on failure
        def summarize_module(dir_name, analyses, client)
          prompt = build_module_prompt(dir_name, analyses)
          client.chat([{ role: "user", content: prompt }])
        end

        # Summarizes overall project architecture.
        #
        # @param project_name [String]  The project name
        # @param analyses     [Hash]    Analysis data
        # @param client       [Client]  An LLM Client instance
        # @return [String, nil]         Summary text or nil on failure
        def summarize_architecture(project_name, analyses, client)
          prompt = build_architecture_prompt(project_name, analyses)
          client.chat([{ role: "user", content: prompt }])
        end

        # Summarizes component relationships across the project.
        #
        # @param analyses [Hash]    Analysis data
        # @param client   [Client]  An LLM Client instance
        # @return [String, nil]     Summary text or nil on failure
        def summarize_components(analyses, client)
          prompt = build_components_prompt(analyses)
          client.chat([{ role: "user", content: prompt }])
        end

        # Returns a multi-paragraph architecture overview covering purpose, style,
        # modules, and data flow. The prompt asks for markdown sections but does
        # NOT include source code.
        #
        # @param project_name [String]  The project name
        # @param analyses     [Hash]    Analysis data
        # @param client       [Client]  An LLM Client instance
        # @return [String, nil]         Summary text or nil on failure
        def summarize_architecture_full(project_name, analyses, client)
          prompt = build_architecture_full_prompt(project_name, analyses)
          client.chat([{ role: "user", content: prompt }])
        end

        # Returns a structured list of external systems the project interacts with
        # (name + interaction description). The prompt asks for JSON or bullet list format.
        #
        # @param project_name [String]  The project name
        # @param analyses     [Hash]    Analysis data
        # @param client       [Client]  An LLM Client instance
        # @return [String, nil]         Summary text or nil on failure
        def summarize_system_context(project_name, analyses, client)
          prompt = build_system_context_prompt(project_name, analyses)
          client.chat([{ role: "user", content: prompt }])
        end

        # Returns container/module descriptions keyed by module root name.
        # Filters analyses to only include files within the given module roots,
        # then includes metadata grouped by root.
        #
        # @param analyses     [Hash]    Analysis data
        # @param module_roots [Array<String>] Module root directory names
        # @param client       [Client]  An LLM Client instance
        # @return [String, nil]         Summary text or nil on failure
        def summarize_containers(analyses, module_roots, client)
          prompt = build_containers_prompt(analyses, module_roots)
          client.chat([{ role: "user", content: prompt }])
        end

        private

        # rubocop:disable Metrics/MethodLength
        def build_module_prompt(dir_name, analyses)
          lines = []
          lines << "You are a software documentation expert analyzing a software project."
          lines << ""
          lines << "Below is the metadata for the \"#{dir_name}\" module. "
          lines << "Provide a concise summary of what this module does, its purpose, and its key components."
          lines << "Do NOT include any source code in your response."
          lines << ""
          lines << "## Module: #{dir_name}"
          lines << ""

          filtered = analyses.select { |path, _| path.include?("/#{dir_name}/") }
          extract_metadata_lines(filtered, lines)

          lines.join("\n")
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength
        def build_architecture_prompt(project_name, analyses)
          lines = []
          lines << "You are a software architecture documentation expert analyzing a Ruby project."
          lines << ""
          lines << "Below is the metadata for the project \"#{project_name}\". "
          lines << "Provide a concise summary of the overall architecture, major modules, "
          lines << "and how they relate to each other."
          lines << "Do NOT include any source code in your response."
          lines << ""
          lines << "## Project: #{project_name}"
          lines << ""

          extract_metadata_lines(analyses, lines)

          lines.join("\n")
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength
        def build_components_prompt(analyses)
          lines = []
          lines << "You are a software architecture documentation expert analyzing a Ruby project."
          lines << ""
          lines << "Below is the metadata for the project's components. "
          lines << "Provide a concise summary of the component relationships, dependencies, "
          lines << "and how data flows between components."
          lines << "Do NOT include any source code in your response."
          lines << ""
          lines << "## Components"
          lines << ""

          # Group by top-level directory to identify components
          grouped = analyses.group_by { |path, _| path.split("/").first(2).join("/") }
          grouped.each do |component, comp_analyses|
            lines << "### #{component}"
            extract_metadata_lines(comp_analyses, lines)
          end

          lines.join("\n")
        end
        # rubocop:enable Metrics/MethodLength

        def extract_metadata_lines(analyses, lines)
          analyses.each do |file_path, analysis|
            lines << "**File:** #{file_path}"
            definitions = analysis[:definitions] || []
            definitions.each do |defn|
              case defn[:type].to_s
              when "class"
                lines << "  - Class: `#{defn[:name]}`#{' (documented)' if defn[:has_doc?]}"
              when "module"
                lines << "  - Module: `#{defn[:name]}`#{' (documented)' if defn[:has_doc?]}"
              when "method"
                lines << "  - Method: `#{defn[:name]}`#{' (documented)' if defn[:has_doc?]}"
              when "constant"
                lines << "  - Constant: `#{defn[:name]}`"
              end
            end
            lines << ""
          end
        end
      end
    end
  end
end
