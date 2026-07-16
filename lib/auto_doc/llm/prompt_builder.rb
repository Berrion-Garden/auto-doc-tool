# frozen_string_literal: true

module AutoDoc
  module LLM
    # Builds metadata-only prompt messages for LLM summarization.
    # Never includes full source code — only file names, class/module names,
    # method names, and structural relationships extracted from analyses.
    class PromptBuilder
      class << self
        # Builds prompt messages for a given generator type.
        #
        # @param generator_type [Symbol] One of :agents_md, :summary, :architecture,
        #   :components, :architecture_full, :system_context, :containers, :readme,
        #   :agents_overview_overview, :agents_overview_tech_stack,
        #   :agents_overview_architecture, :agents_overview_conventions
        # @param name [String, nil] The name to use (dir name, project name, etc.)
        # @param analyses [Hash] Analysis data: { file_path => { definitions:, docs: } }
        # @param module_roots [Array<String>, nil] Module root dirs (for containers)
        # @return [Array<Hash>] Array of {role:, content:} message hashes
        def build(generator_type, name, analyses, module_roots = nil)
          case generator_type
          when :agents_md
            build_agents_md_messages(name, analyses)
          when :summary
            build_summary_messages(name, analyses)
          when :architecture
            build_architecture_messages(name, analyses)
          when :components
            build_components_messages(analyses)
          when :architecture_full
            build_architecture_full_messages(name, analyses)
          when :system_context
            build_system_context_messages(name, analyses)
          when :containers
            build_containers_messages(analyses, module_roots)
          when :agents_overview_overview
            build_agents_overview_overview_messages(name, analyses)
          when :agents_overview_tech_stack
            build_agents_overview_tech_stack_messages(name, analyses)
          when :agents_overview_architecture
            build_agents_overview_architecture_messages(name, analyses)
          when :agents_overview_conventions
            build_agents_overview_conventions_messages(name, analyses)
          when :readme
            build_readme_messages(name, analyses)
          when :symbol_summaries
            build_symbol_summaries_messages(name, analyses)
          else
            raise ArgumentError, "Unknown generator type: #{generator_type}"
          end
        end

        private

        # rubocop:disable Metrics/MethodLength
        def build_summary_messages(dir_name, analyses)
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

          [{ role: "user", content: lines.join("\n") }]
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength
        def build_architecture_messages(project_name, analyses)
          lines = []
          lines << "You are a software architecture documentation expert analyzing a software project."
          lines << ""
          lines << "Below is the metadata for the project \"#{project_name}\". "
          lines << "Provide a concise summary of the overall architecture, major modules, "
          lines << "and how they relate to each other."
          lines << "Do NOT include any source code in your response."
          lines << ""
          lines << "## Project: #{project_name}"
          lines << ""

          extract_metadata_lines(analyses, lines)

          [{ role: "user", content: lines.join("\n") }]
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength
        def build_components_messages(analyses)
          lines = []
          lines << "You are a software architecture documentation expert analyzing a software project."
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

          [{ role: "user", content: lines.join("\n") }]
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength
        def build_architecture_full_messages(project_name, analyses)
          lines = []
          lines << "You are a software architecture documentation expert analyzing a software project."
          lines << ""
          lines << "Below is the metadata for the project \"#{project_name}\". "
          lines << "Provide a detailed, multi-paragraph architecture overview covering the project's purpose, "
          lines << "architectural style, main modules, and data flow between them. "
          lines << "Use markdown sections (headings, paragraphs, bullet lists) in your response. "
          lines << "Do NOT include any source code in your response."
          lines << ""
          lines << "## Project: #{project_name}"
          lines << ""

          extract_metadata_lines(analyses, lines)

          [{ role: "user", content: lines.join("\n") }]
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength
        def build_system_context_messages(project_name, analyses)
          lines = []
          lines << "You are a software architecture documentation expert analyzing a software project."
          lines << ""
          lines << "Below is the metadata for the project \"#{project_name}\". "
          lines << "List the external systems, services, or libraries that this project interacts with. "
          lines << "For each external system, provide its name and a brief description of how the project interacts with it. "
          lines << "Format your response as a JSON array of objects with 'name' and 'interaction' fields, "
          lines << "OR as a markdown bullet list."
          lines << ""
          lines << "## Project: #{project_name}"
          lines << ""

          extract_metadata_lines(analyses, lines)

          [{ role: "user", content: lines.join("\n") }]
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength
        def build_containers_messages(analyses, module_roots)
          lines = []
          lines << "You are a software architecture documentation expert analyzing a software project."
          lines << ""
          lines << "Below is the metadata for the project's modules, grouped by module root directory. "
          lines << "For each module root, describe its purpose, key files, and overall responsibility. "
          lines << "Format your response as a markdown section per module root."
          lines << ""

          Array(module_roots).each do |root|
            filtered = analyses.select { |path, _| path.include?("/#{root}/") }
            next if filtered.empty?

            lines << "## Module Root: #{root}"
            lines << ""
            extract_metadata_lines(filtered, lines)
          end

          [{ role: "user", content: lines.join("\n") }]
        end
        # rubocop:enable Metrics/MethodLength

        def build_agents_md_messages(module_name, analyses)
          lines = []
          lines << <<~PROMPT.strip
            You are analyzing a software project's internal module to generate its AGENTS.md file.
            Below is the metadata for the "#{module_name}" module.
            Based on this metadata, describe what this module does, how it is organized, and how it fits into the larger project.
            Do NOT include any source code in your response.
          PROMPT
          lines << ""
          lines << "## Module: #{module_name}"
          lines << ""

          filtered = analyses.select { |path, _| path.include?("/#{module_name}/") }
          extract_metadata_lines(filtered, lines)

          [{ role: "user", content: lines.join("\n") }]
        end

        def build_readme_messages(project_name, analyses)
          lines = []
          lines << <<~PROMPT.strip
            You are generating a README for a software project called "#{project_name}".
            Below is the metadata for the project.
            Generate a concise README describing what the project does, its key components, and how to get started.
            Do NOT include any source code in your response.
          PROMPT
          lines << ""
          lines << "## Project: #{project_name}"
          lines << ""

          extract_metadata_lines(analyses, lines)

          [{ role: "user", content: lines.join("\n") }]
        end

        # rubocop:disable Metrics/MethodLength
        def build_agents_overview_overview_messages(project_name, analyses)
          lines = []
          lines << <<~PROMPT.strip
            You are generating a project overview for the "#{project_name}" codebase.
            Below is the metadata for the entire project.
            Provide a concise, 2-3 paragraph overview describing what the project does, its main purpose, and its key modules.
            Do NOT include any source code in your response.
          PROMPT
          lines << ""
          lines << "## Project: #{project_name}"
          lines << ""
          extract_metadata_lines(analyses, lines)
          [{ role: "user", content: lines.join("\n") }]
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength
        def build_agents_overview_tech_stack_messages(project_name, analyses)
          lines = []
          lines << <<~PROMPT.strip
            You are analyzing the technology stack of the "#{project_name}" codebase.
            Below is the metadata for the project.
            List the programming languages, frameworks, libraries, and tools used by this project.
            Format your response as a markdown bullet list.
            Do NOT include any source code in your response.
          PROMPT
          lines << ""
          lines << "## Project: #{project_name}"
          lines << ""
          extract_metadata_lines(analyses, lines)
          [{ role: "user", content: lines.join("\n") }]
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength
        def build_agents_overview_architecture_messages(project_name, analyses)
          lines = []
          lines << <<~PROMPT.strip
            You are analyzing the architecture of the "#{project_name}" codebase.
            Below is the metadata for the project.
            Describe the overall architecture, major components, how they relate, and any notable design patterns.
            Format your response as 2-3 paragraphs with markdown headings.
            Do NOT include any source code in your response.
          PROMPT
          lines << ""
          lines << "## Project: #{project_name}"
          lines << ""
          extract_metadata_lines(analyses, lines)
          [{ role: "user", content: lines.join("\n") }]
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength
        def build_agents_overview_conventions_messages(project_name, analyses)
          lines = []
          lines << <<~PROMPT.strip
            You are analyzing the coding conventions of the "#{project_name}" codebase.
            Below is the metadata for the project.
            Based on the file names, module structure, and class/module naming, describe the likely coding conventions used.
            Include naming conventions, file organization, documentation style, and any other patterns you observe.
            Format your response as a markdown bullet list.
            Do NOT include any source code in your response.
          PROMPT
          lines << ""
          lines << "## Project: #{project_name}"
          lines << ""
          extract_metadata_lines(analyses, lines)
          [{ role: "user", content: lines.join("\n") }]
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength
        def build_symbol_summaries_messages(module_name, analyses)
          lines = []
          lines << "You are analyzing a software module called \"#{module_name}\"."
          lines << ""
          lines << "Below is the metadata for each file and symbol in this module."
          lines << ""
          lines << "For EACH symbol below, provide a UNIQUE one-sentence description of what it specifically does. "
          lines << "Two symbols MUST NOT have the same description."
          lines << "Format EXACTLY: SymbolName: Unique description."
          lines << "Do NOT include any other text, headings, or commentary."
          lines << ""

          extract_numbered_metadata_lines(analyses, lines)

          [{ role: "user", content: lines.join("\n") }]
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

        # Like extract_metadata_lines but uses a single numbered list for all symbols
        # across all files, making it easier for the LLM to iterate through each one.
        def extract_numbered_metadata_lines(analyses, lines)
          num = 0
          analyses.each do |file_path, analysis|
            lines << "**File:** #{file_path}"
            definitions = analysis[:definitions] || []
            definitions.each do |defn|
              num += 1
              type_label = defn[:type].to_s.capitalize
              lines << "  #{num}. #{type_label}: #{defn[:name]}#{' (documented)' if defn[:has_doc?]}"
            end
            lines << ""
          end
        end
      end
    end
  end
end
