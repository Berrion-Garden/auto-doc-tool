# frozen_string_literal: true

module AutoDoc
  module Generator
    # Shared template reading logic for all generators.
    # Included by generator classes to avoid duplicating read_template.
    module TemplateHelper
      # Read a template file from disk by its full path.
      # Raises if the file does not exist.
      #
      # @param path [String] Full path to the template file
      # @return [String] Template content with UTF-8 encoding forced
      def read_template(path)
        raise "Template not found: #{path}" unless File.exist?(path)

        content = File.read(path)
        content.force_encoding("UTF-8")
      rescue Errno::ENOENT
        raise
      end
    end
  end
end
