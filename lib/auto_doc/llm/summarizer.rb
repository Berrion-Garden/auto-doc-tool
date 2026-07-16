# frozen_string_literal: true

require "json"

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
        # @return [Hash, nil]           Hash with :purpose, :style, :modules, :data_flow keys or nil on failure
        def summarize_architecture_full(project_name, analyses, client)
          prompt = build_architecture_full_prompt(project_name, analyses)
          response = client.chat([{ role: "user", content: prompt }])
          return nil if response.nil?

          parse_architecture_full(response)
        end

        # Returns a structured list of external systems the project interacts with
        # (name + interaction description). The prompt asks for JSON or bullet list format.
        #
        # @param project_name [String]  The project name
        # @param analyses     [Hash]    Analysis data
        # @param client       [Client]  An LLM Client instance
        # @return [Array<Hash>, nil]    Array of {name:, interaction:} hashes or nil on failure
        def summarize_system_context(project_name, analyses, client)
          prompt = build_system_context_prompt(project_name, analyses)
          response = client.chat([{ role: "user", content: prompt }])
          return nil if response.nil?

          parse_system_context(response)
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
          prompt = build_containers_prompt(analyses, module_roots)
          response = client.chat([{ role: "user", content: prompt }])
          return nil if response.nil?

          parse_containers(response)
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

          lines.join("\n")
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength
        def build_components_prompt(analyses)
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

        # rubocop:disable Metrics/MethodLength
        def build_architecture_full_prompt(project_name, analyses)
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

          lines.join("\n")
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength
        def build_system_context_prompt(project_name, analyses)
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

          lines.join("\n")
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength
        def build_containers_prompt(analyses, module_roots)
          lines = []
          lines << "You are a software architecture documentation expert analyzing a software project."
          lines << ""
          lines << "Below is the metadata for the project's modules, grouped by module root directory. "
          lines << "For each module root, describe its purpose, key files, and overall responsibility. "
          lines << "Format your response as a markdown section per module root."
          lines << ""

          module_roots.each do |root|
            filtered = analyses.select { |path, _| path.include?("/#{root}/") }
            next if filtered.empty?

            lines << "## Module Root: #{root}"
            lines << ""
            extract_metadata_lines(filtered, lines)
          end

          lines.join("\n")
        end
        # rubocop:enable Metrics/MethodLength

        # Parses a markdown response from the LLM into a structured hash for
        # architecture_full. Looks for ## headings and maps known headings to
        # the expected keys.
        #
        # @param response [String] Raw LLM markdown response
        # @return [Hash] Hash with :purpose, :style, :modules, :data_flow keys
        def parse_architecture_full(response)
          result = { purpose: "", style: "", modules: "", data_flow: "" }
          current_section = nil
          current_content = []

          response.each_line do |line|
            if line.match?(/^##\s+/)
              # Save previous section content
              if current_section
                section_key = normalize_arch_section_heading(current_section)
                result[section_key] = current_content.join.strip if result.key?(section_key)
              end
              current_section = line.sub(/^##\s+/, "").strip
              current_content = []
            else
              current_content << line
            end
          end
          # Save last section
          if current_section
            section_key = normalize_arch_section_heading(current_section)
            result[section_key] = current_content.join.strip if result.key?(section_key)
          end

          # If no sections were parsed (response is paragraph-only), put everything in :purpose
          result[:purpose] = response.strip if result.values.all?(&:empty?)

          result
        end

        # Maps a markdown heading text to one of the four architecture keys.
        #
        # @param heading [String] The heading text (e.g. "Purpose", "Main Modules")
        # @return [Symbol] One of :purpose, :style, :modules, :data_flow
        def normalize_arch_section_heading(heading)
          mapping = {
            "purpose" => :purpose,
            "introduction" => :purpose,
            "overview" => :purpose,
            "architectural style" => :style,
            "architecture" => :style,
            "style" => :style,
            "main modules" => :modules,
            "modules" => :modules,
            "components" => :modules,
            "data flow" => :data_flow,
            "dataflow" => :data_flow
          }
          mapping[heading.downcase.strip] || :purpose
        end

        # Parses the LLM response for system_context. Tries JSON first, then
        # falls back to markdown bullet list parsing.
        #
        # @param response [String] Raw LLM response (JSON array or markdown bullet list)
        # @return [Array<Hash>, nil] Array of {name:, interaction:} or nil on failure
        def parse_system_context(response)
          # Try JSON first
          begin
            parsed = JSON.parse(response)
            if parsed.is_a?(Array) && parsed.all? { |item| item.is_a?(Hash) && item["name"].to_s.strip != "" && item["interaction"].to_s.strip != "" }
              return parsed.map { |item| { name: item["name"].to_s, interaction: item["interaction"].to_s } }
            end
          rescue JSON::ParserError
            # Fall through to markdown parsing
          end

          # Try markdown bullet list: - Name: Interaction or * Name: Interaction
          entries = response.each_line.filter_map do |line|
            match = line.match(/^[\s]*[-*]\s+(.+?):\s+(.+)$/)
            { name: match[1].strip, interaction: match[2].strip } if match
          end

          entries.empty? ? nil : entries
        end

        # Parses the LLM response for containers. Looks for ## Module Root: name
        # headings and collects content under each.
        #
        # @param response [String] Raw LLM markdown response
        # @return [Hash, nil] Hash of {module_root_name => description_string} or nil on failure
        def parse_containers(response)
          result = {}
          current_root = nil
          current_content = []

          response.each_line do |line|
            if line.match?(/^##\s+/)
              # Save previous module root content
              result[current_root] = current_content.join.strip if current_root
              current_root = line.sub(/^##\s+/, "").sub(/^Module Root:\s*/i, "").strip
              current_content = []
            elsif current_root
              current_content << line
            end
          end
          # Save last module root
          result[current_root] = current_content.join.strip if current_root

          result.empty? ? nil : result
        end
      end
    end
  end
end
