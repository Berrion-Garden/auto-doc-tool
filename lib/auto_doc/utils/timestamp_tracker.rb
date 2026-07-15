# frozen_string_literal: true

require "json"
require "fileutils"

module AutoDoc
  module Utils
    # Tracks file modification times to detect which files have changed
    # since the last documentation generation run.
    #
    # Manifests are stored as `generation_manifest.json` within the output
    # directory (`.docs/` by default) in the project directory. The format is:
    #   { "generated_at": "ISO8601", "files": { "rel/path.rb": mtime_epoch, ... } }
    class TimestampTracker
      MANIFEST_FILENAME = "generation_manifest.json"

      # Returns all Ruby files that have changed (or are new) since the last manifest.
      # Returns ALL Ruby files if no manifest exists (first run).
      #
      # @param project_dir [String] the project root directory
      # @param output_dir [String] output directory relative to project root (default: ".docs")
      # @return [Array<String>] relative paths of stale files, or empty array if none
      def self.stale_files(project_dir, output_dir = ".docs")
        all_files = Dir.glob("**/*.rb", base: project_dir).sort
        manifest_path = File.join(project_dir, output_dir, MANIFEST_FILENAME)

        return all_files unless File.exist?(manifest_path)

        manifest = JSON.parse(File.read(manifest_path))
        stored_files = manifest.fetch("files", {})

        stale = all_files.select do |rel_path|
          full_path = File.join(project_dir, rel_path)
          current_mtime = File.mtime(full_path).to_i
          stored_mtime = stored_files[rel_path]

          stored_mtime.nil? || current_mtime != stored_mtime
        end

        stale
      rescue Errno::ENOENT, JSON::ParserError
        all_files
      end

      # Saves a manifest with current mtimes for the given file list.
      # Creates the output directory if it doesn't exist.
      #
      # @param project_dir [String] the project root directory
      # @param file_list [Array<String>] relative file paths to track
      # @param output_dir [String] output directory relative to project root (default: ".docs")
      # @return [Boolean] true on success, false on file permission errors
      def self.save_manifest(project_dir, file_list, output_dir = ".docs")
        files = file_list.each_with_object({}) do |rel_path, hash|
          full_path = File.join(project_dir, rel_path)
          hash[rel_path] = File.mtime(full_path).to_i
        end

        manifest = {
          "generated_at" => Time.now.iso8601,
          "files" => files
        }

        dir = File.join(project_dir, output_dir)
        FileUtils.mkdir_p(dir)

        manifest_path = File.join(project_dir, output_dir, MANIFEST_FILENAME)
        File.write(manifest_path, JSON.pretty_generate(manifest))

        true
      rescue Errno::EACCES, Errno::ENOENT
        false
      end
    end
  end
end
