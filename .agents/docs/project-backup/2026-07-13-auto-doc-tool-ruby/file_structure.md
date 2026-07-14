# Auto-Doc Tool — File Structure

## Current State

All 13 lib files pass `ruby -c` syntax check. Only `file_tree_builder.rb` line ~82 has a TypeError in `should_exclude?` method (Array passed to `File.fnmatch` instead of String). All other modules are functional.

```
lib/
  auto-doc.rb                    — Gem entry point, requires all submodules
  auto-doc/
    version                      — Version constant
    config                       — Configuration loading and merging from YAML/env
    file_tree_builder            — Directory traversal, exclusion filtering ← BUG: should_exclude? receives Array instead of String on line ~82
    doc_generator                — Orchestrates tree building + template rendering
    template_engine              — ERB template compilation and rendering
    output_writer                — File system writes with directory creation
    cli                          — Thor-based command-line interface
    command                      — Command routing (init, generate, config)
    project_analyzer             — High-level project metadata extraction
    dependency_scanner           — External dependency detection
    route_mapper                 — Route/table mapping from source files
    section_builder              — Documentation section assembly
    error_handling               — Custom exceptions and error formatting

exe/
  auto-doc                       — CLI executable entry point (shebang wrapper)

templates/
  default                        — Default ERB template for generated docs
    README_template.erb          — Base README structure template
    config_example.yml           — Example configuration file scaffold

spec/                            — Test suite
  spec_helper                    — Test setup, fixtures path, shared contexts
  auto_doc_spec                  — Gem loading and version smoke test
  units/                         — Unit tests by module
    config_spec                  — Config parsing and env override tests
    file_tree_builder_spec       — Exclusion pattern matching tests
    template_engine_spec         — ERB rendering with locals tests
    output_writer_spec           — File write and directory creation tests
    cli_spec                     — Command argument parsing tests
  integration/                   — Cross-component flow tests
    doc_generator_spec           — Full pipeline: config → tree → render → write

fixtures/                        — Static test data
  sample_project/                — Mock project structure for traversal tests
    Gemfile                      — Fake dependency file
    lib/sample.rb                — Dummy source file
  configs/                       — Test configuration fixtures
    valid_config.yml             — Well-formed config YAML
    minimal_config.yml           — Config with only required keys
```

## Proposed Changes

Only one file is modified. The change normalizes exclusion patterns before the `File.fnmatch` call to handle nested arrays produced by config merge.

```
lib/
  auto-doc/
    file_tree_builder            — Normalize pattern in should_exclude? to String before File.fnmatch call
                                — Config merge can produce [pattern] or [[nested, array]] depending on source; flatten + take first element before matching
```
