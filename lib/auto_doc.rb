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
  require_relative "auto_doc/utils/output_formatter"
  require_relative "auto_doc/utils/markdown_helper"

  require_relative "auto_doc/documentation_index"
  # Load analyzers
  require_relative "auto_doc/analyzer/analysis_cache"
  require_relative "auto_doc/analyzer/source_parser"
  require_relative "auto_doc/analyzer/schema_parser"
  require_relative "auto_doc/analyzer/model_association_parser"
  require_relative "auto_doc/analyzer/import_extractor"
  require_relative "auto_doc/analyzer/yard_reader"
  require_relative "auto_doc/analyzer/analysis_pipeline"
  require_relative "auto_doc/analyzer/diff_service"
  require_relative "auto_doc/analyzer/orphans_service"

  # Load LLM services
  require_relative "auto_doc/llm"

  # Load generators
  require_relative "auto_doc/generator/template_helper"
  require_relative "auto_doc/generator/agents_md_generator"
  require_relative "auto_doc/generator/readme_generator"
  require_relative "auto_doc/generator/diagram_generator"
  require_relative "auto_doc/generator/index_generator"
  require_relative "auto_doc/generator/summary_generator"
  require_relative "auto_doc/generator/vector_generator"
  require_relative "auto_doc/generator/c4_diagram_generator"
  require_relative "auto_doc/generator/class_diagram_generator"
  require_relative "auto_doc/generator/erd_generator"
  require_relative "auto_doc/generator/architecture_generator"
  require_relative "auto_doc/generator/map_generator"

  # Load reporters
  require_relative "auto_doc/reporter/completeness_checker"
  require_relative "auto_doc/reporter/audit_reporter"

  # Load search services
  require_relative "auto_doc/search_service"
  require_relative "auto_doc/agent_query_service"

  # Load transformer services
  require_relative "auto_doc/transformer"

  # Load orchestrator
  require_relative "auto_doc/orchestrator"

  # Load orchestrator pipeline steps
  require_relative "auto_doc/orchestrator/base_step"
  require_relative "auto_doc/orchestrator/agents_md_step"
  require_relative "auto_doc/orchestrator/readme_step"
  require_relative "auto_doc/orchestrator/index_summary_vectors_step"
  require_relative "auto_doc/orchestrator/diagram_step"
  require_relative "auto_doc/orchestrator/architecture_step"
  require_relative "auto_doc/orchestrator/manifest_step"
  require_relative "auto_doc/orchestrator/pipeline"

  # Load CLI
  require_relative "auto_doc/cli"

  # Load tester
  require_relative "auto_doc/tester/e2e_runner"

  # Load server
  require_relative "auto_doc/server"
end
