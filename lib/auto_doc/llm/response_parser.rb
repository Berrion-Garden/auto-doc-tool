# frozen_string_literal: true

require "json"

module AutoDoc
  module LLM
    # Parses LLM responses into structured data.
    # Handles markdown headings, JSON arrays, and bullet list formats.
    class ResponseParser
      class << self
        # Extracts the first paragraph or section content as a purpose summary.
        #
        # @param text [String] Raw LLM response
        # @return [String] Purpose text (first non-empty paragraph or section)
        def parse_purpose(text)
          return "" if text.nil? || text.strip.empty?

          stripped = text.strip

          # Try to get content under ## Purpose section
          purpose_section = parse_section(stripped, "Purpose")
          return purpose_section.strip unless purpose_section.nil? || purpose_section.strip.empty?

          # Fall back to first paragraph
          stripped.split("\n\n").first&.strip || stripped
        end

        # Parses a markdown bullet list into component hashes.
        # Supports patterns:
        #   - Name: Description
        #   * Name: Description
        #
        # @param text [String] Markdown bullet list from LLM
        # @return [Array<Hash>] Array of {name:, description:}
        def parse_components(text)
          return [] if text.nil? || text.strip.empty?

          text.each_line.filter_map do |line|
            stripped = line.strip
            next if stripped.empty?

            # Try **Name** - Description first
            match = stripped.match(/^[\s]*[-*]\s+\*\*(.+?)\*\*\s*[-–—]\s*(.+)$/)
            if match
              { name: match[1].strip, description: match[2].strip }
            else
              # Try Name: Description
              match = stripped.match(/^[\s]*[-*]\s+(.+?):\s+(.+)$/)
              if match
                { name: match[1].strip, description: match[2].strip }
              end
            end
          end
        end

        # Parses a markdown response from the LLM into a structured hash for
        # architecture_full. Uses parse_section to extract each known section
        # by heading name.
        #
        # @param response [String] Raw LLM markdown response
        # @return [Hash] Hash with :purpose, :style, :modules, :data_flow keys
        def parse_architecture_full(response)
          return nil if response.nil?

          result = {
            purpose: parse_section(response, "Purpose") || "",
            style: parse_section(response, "Architectural Style") || "",
            modules: parse_section(response, "Main Modules") || "",
            data_flow: parse_section(response, "Data Flow") || ""
          }

          # If no sections were found, try alternative heading names
          if result.values.all?(&:empty?)
            result[:purpose] = parse_section(response, "Introduction") || ""
          end

          # If still no sections parsed (response is paragraph-only), put everything in :purpose
          result[:purpose] = response.strip if result.values.all?(&:empty?)

          result
        end

        # Parses the LLM response for system_context. Tries JSON first, then
        # falls back to markdown bullet list parsing.
        #
        # @param response [String] Raw LLM response (JSON array or markdown bullet list)
        # @return [Array<Hash>, nil] Array of {name:, interaction:} or nil on failure
        def parse_system_context(response)
          return nil if response.nil?

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
          return nil if response.nil?

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

        # Parses LLM markdown bullet list for modules.
        # Supports patterns:
        #   - **Name** - Description
        #   - Name: Description
        #   * Name: Description
        # @param text [String, nil] Markdown bullet list from LLM
        # @return [Array<Hash>] Array of {name:, responsibility:}
        def parse_llm_modules(text)
          return [] if text.nil? || text.empty?

          text.each_line.filter_map do |line|
            stripped = line.strip
            next if stripped.empty?

            # Try **Name** - Description first
            match = stripped.match(/^[\s]*[-*]\s+\*\*(.+?)\*\*\s*[-–—]\s*(.+)$/)
            if match
              { name: match[1].strip, responsibility: match[2].strip }
            else
              # Try Name: Description
              match = stripped.match(/^[\s]*[-*]\s+(.+?):\s+(.+)$/)
              if match
                { name: match[1].strip, responsibility: match[2].strip }
              end
            end
          end
        end

        # Parses LLM markdown bullet list for data flows.
        # Supports patterns:
        #   - From -> To: Description
        #   - From → To: Description
        # @param text [String, nil] Markdown bullet list from LLM
        # @return [Array<Hash>] Array of {from:, to:, description:}
        def parse_llm_data_flows(text)
          return [] if text.nil? || text.empty?

          text.each_line.filter_map do |line|
            stripped = line.strip
            next if stripped.empty?

            # Match: - From -> To: Description  or  - From → To: Description
            match = stripped.match(/^[\s]*[-*]\s+(.+?)\s*(?:->|→)\s*(.+?):\s+(.+)$/)
            if match
              { from: match[1].strip, to: match[2].strip, description: match[3].strip }
            end
          end
        end

        private

        # Extracts content under a named markdown section heading from an LLM response.
        # Looks for `## section_name` (case-insensitive) and returns content until
        # the next `##` heading or end-of-string. Returns nil if not found.
        #
        # @param response     [String] Raw LLM markdown response
        # @param section_name [String] The section heading to find (e.g. "Purpose")
        # @return [String, nil]        Extracted content (stripped whitespace) or nil
        def parse_section(response, section_name)
          return nil if response.nil? || response.empty?

          regex = /^##\s+#{Regexp.escape(section_name)}\s*$/i
          lines = response.lines
          start_idx = lines.index { |line| line.match?(regex) }
          return nil if start_idx.nil?

          # Skip the heading line
          content_start = start_idx + 1
          end_idx = lines[content_start..].index { |line| line.match?(/^##\s+/) }

          if end_idx
            lines[content_start, end_idx].join.strip
          else
            lines[content_start..].join.strip
          end
        end
      end
    end
  end
end
