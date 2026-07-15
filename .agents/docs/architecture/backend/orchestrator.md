# Orchestrator Module

## Class: `AutoDoc::Orchestrator`

**File:** `lib/auto_doc/orchestrator.rb`

### Purpose

Extracted orchestration logic from CLI. Accepts explicit parameters and returns results. CLI handles all output formatting; this class handles the "what to do."

### Constructor

```ruby
def initialize(options = {})
  @options = options.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
end
```

Converts all CLI option keys to symbols for consistent lookup.

### Public Methods

#### `generate(path, say: method(:puts)) → Hash`

Performs full documentation generation:

1. Resolves config from `path`, applies CLI overrides.
2. Determines output directory: CLI `--output_dir` > `--format` ("docs"/"autodoc") > config default.
3. Resolves module roots from config.
4. Analyzes project (incremental or full).
5. Generates AGENTS.md per module root.
6. Walks subdirectories → INDEX.md, SUMMARY.md, vectors.json per directory.
7. Generates project-level README.md.
8. Generates diagrams: deps.mmd, class_diagram.mmd, ERD (Rails only), C4 context/container, architecture.md.
9. Generates project-level INDEX.md, SUMMARY.md, VECTORS.json.
10. Saves timestamp manifest for incremental tracking.
11. Returns structured result hash with created files, analyses count, schema/models data.

#### `audit(path, threshold = 80, say: method(:puts)) → Hash`

Runs documentation audit:

1. Analyzes project files.
2. Generates audit report via `AuditReporter`.
3. Formats and prints report.
4. Writes `report.json` to output directory.
5. Returns report hash.

### Private Helper Methods

| Method | Purpose |
|--------|---------|
| `cli_overrides(options)` | Extracts `exclude` and `incremental` options |
| `resolve_module_roots(base_dir, config)` | Filters config module_roots to existing directories |
| `analyze_project(base_dir, config, file_list=nil)` | Parses all Ruby files, builds definitions+imports+docs per file |
| `build_files_data(analyses)` | Converts raw analyses to structure for AgentsMdGenerator |
| `count_classes_and_methods(analyses)` | Counts classes/modules and methods across analyses |
| `calculate_coverage(analyses)` | Delegates to CompletenessChecker, returns coverage percentage |
| `build_class_hierarchy(analyses)` | Extracts class names, parents, includes, methods for diagram |
| `build_erd_relationships(models, schema_tables)` | Derives cardinality from association types |
| `build_container_data_flows(analyses, module_roots)` | Derives cross-module imports for C4 diagram |
| `build_graph_data(analyses)` | Extracts nodes+edges for deps.mmd DAG |
| `walk_subdirectories(root, analyses, target_dir, output_dir, config, say)` | Walks all subdirs, generates INDEX/SUMMARY/vectors per dir with Ruby files |

### Phase 2a Changes

- **`walk_subdirectories`** — Lines 484-485: `dirs_to_process.reject! { |d| d == target_dir }` prevents duplicate project-level file generation. Was a reported issue (Major #4).
- **Output directory resolution** — `generate` method now uses a cascade: `@options[:output_dir]` → `@options[:format]` → `config.output_dir`.