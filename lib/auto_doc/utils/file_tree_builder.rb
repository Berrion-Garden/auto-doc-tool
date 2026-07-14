# frozen_string_literal: true

module AutoDoc
  module Utils
    # Builds an indented directory tree text representation (like `tree` output).
    # Uses Dir.glob and File.stat to distinguish directories from files.
    class FileTreeBuilder
      # Entry point — builds the full tree string for a directory path.
      #
      # @param path [String] the directory to render as a tree
      # @param exclude_patterns [Array<String>] fnmatch patterns to skip
      # @return [String] formatted tree with box-drawing characters
      def self.build(path, exclude_patterns = [])
        new(path, exclude_patterns).build
      end

      def initialize(path, exclude_patterns = [])
        @root = File.expand_path(path)
        @exclude_patterns = Array(exclude_patterns).flatten(1)
      end

      # Returns the complete directory tree as a formatted string.
      # Lines use ├── / └── connectors and │ continuation prefixes.
      def build
        children = entries(@root)
        return "" if children.empty?

        lines = render_children(children, "")
        lines.join("\n") + "\n"
      end

      private

      # Lists immediate children of a directory, sorted alphabetically.
      # Skips dotfiles/dotdirs and anything matching an exclude pattern.
      def entries(dir)
        return [] unless Dir.exist?(dir)

        Dir.entries(dir)
            .reject { |e| e.start_with?(".") }
            .sort
            .map do |name|
          full_path = File.join(dir, name)
          next if should_exclude?(full_path)

          stat = File.stat(full_path) rescue nil
          next unless stat && (stat.directory? || stat.file?)

          {
            name: name,
            path: full_path,
            type: stat.directory? ? :directory : :file
          }
        end.compact
      end

      # Renders a list of entries with proper tree connectors and recurses into directories.
      def render_children(children, prefix)
        return [] if children.empty?

        lines = []
        children.each_with_index do |entry, index|
          last = (index == children.length - 1)
          connector = last ? "└── " : "├── "
          continuation = last ? "    " : "│   "

          lines << "#{prefix}#{connector}#{entry[:name]}"

          if entry[:type] == :directory
            sub_children = entries(entry[:path])
            lines.concat(render_children(sub_children, prefix + continuation))
          end
        end
        lines
      end

      # Checks whether a file path matches any configured exclusion pattern.
      def should_exclude?(filepath)
        return false if @exclude_patterns.empty?

        rel_path = filepath.sub(@root.chomp("/"), "").sub(%r{^/}, "")
        @exclude_patterns.flatten.each do |pattern|
          next unless pattern.is_a?(String)

          return true if File.fnmatch?(pattern, rel_path)
        end
        false
      end
    end
  end
end
