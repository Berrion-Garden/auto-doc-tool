# frozen_string_literal: true

require_relative "auto_doc/version"

# Main entry point for the auto-doc gem.
# Requires all submodules; intended to be loaded once at application startup.
#
# Usage:
#   require 'auto_doc'
#   AutoDoc::CLI.start(ARGV)
module AutoDoc
  # Load config and utilities
  require_relative "auto_doc/config"
  require_relative "auto_doc/utils/yaml_config_loader"
  require_relative "auto_doc/utils/file_tree_builder"
  require_relative "auto_doc/utils/timestamp_tracker"

  # Load analyzers
  require_relative "auto_doc/analyzer/source_parser"
  require_relative "auto_doc/analyzer/import_extractor"
  require_relative "auto_doc/analyzer/yard_reader"

  # Load generators
  require_relative "auto_doc/generator/agents_md_generator"
  require_relative "auto_doc/generator/readme_generator"
  require_relative "auto_doc/generator/diagram_generator"

  # Load reporters
  require_relative "auto_doc/reporter/completeness_checker"
  require_relative "auto_doc/reporter/audit_reporter"

  # Load CLI
  require_relative "auto_doc/cli"

  # Load tester
  require_relative "auto_doc/tester/e2e_runner"

  # Load server
  require_relative "auto_doc/server"
end
