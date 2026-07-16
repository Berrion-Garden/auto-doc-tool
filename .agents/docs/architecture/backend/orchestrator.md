# Auto-Doc — Orchestrator Pipeline

## Purpose

The orchestrator coordinates the full documentation generation workflow, from source analysis through artifact generation. It separates CLI concerns (output formatting, argument parsing) from workflow logic.

## Components

### `Orchestrator` (`orchestrator.rb`)

Top-level coordinator. Receives CLI options and manages the complete `generate` or `audit` workflow.

**`generate(path, say:)` workflow:**
1. Load `Config` from target directory with CLI overrides
2. Resolve output directory (CLI flag > format option > config default)
3. Resolve module roots (config `module_roots` → fall back to `[base_dir]`)
4. Run analysis pipeline (incremental if `--incremental` flag set)
5. Execute `Pipeline` with analysis results
6. Return stats hash merged with created files list

**`audit(path, threshold, say:, analyses:)` workflow:**
1. Load `Config` with threshold override
2. Run analysis pipeline (or reuse provided analyses)
3. Call `AuditReporter.generate` for coverage report
4. Write `report.json` to output directory
5. Return report hash

**Analysis caching:** Full-project scans use `AnalysisCache.fetch(base_dir, config)` for in-process caching. Incremental and file-list scans bypass the cache.

### `BaseStep` (`orchestrator/base_step.rb`)

Abstract base class defining the step interface.

```ruby
class BaseStep
  def run(context)
    raise NotImplementedError
  end

  protected
  def say(context, msg, color = nil)
    context[:say]&.call(msg, color)
  end
end
```

### `Pipeline` (`orchestrator/pipeline.rb`)

Sequential executor of pipeline steps. Steps share a mutable context hash that accumulates data.

**Step order:**
```ruby
STEPS = [
  AgentsMdStep.new,          # 1. Per-module AGENTS.md
  ReadmeStep.new,            # 2. Project README.md
  IndexSummaryVectorsStep.new, # 3. INDEX.md + SUMMARY.md + VECTORS.json
  DiagramStep.new,           # 4. Mermaid diagrams
  ArchitectureStep.new,      # 5. Architecture documentation
  ManifestStep.new           # 6. .map.json cross-reference manifest
]
```

**Context initialization:**
```ruby
{
  target_dir:     expanded_project_path,
  output_dir:     resolved_output_directory,
  config:         loaded_config_instance,
  module_roots:  ["/path/to/app", "/path/to/lib", ...],
  analyses:       { file_path => { definitions:, docs:, imports: }, ... },
  say:            ->(msg, color) { ... },
  all_classes:    0,          # Accumulated by steps
  all_methods:    0,          # Accumulated by steps
  coverage_pct:   "0",        # Calculated by steps
  schema_tables:  nil,        # Set if Rails project
  models:         nil,        # Set if Rails project
  class_hierarchy: [],        # Accumulated by DiagramStep
  container_data_flows: []    # Accumulated by DiagramStep
}
```

**Return shape:**
```ruby
{
  project:         File.basename(context[:target_dir]),
  output_dir:      context[:output_dir],
  module_roots:    [module_root_names],
  analyses_count:  number_of_files_analyzed,
  classes_count:   total_classes_and_modules,
  methods_count:   total_methods,
  coverage_pct:    coverage_percentage_float,
  generated_at:    ISO8601_timestamp,
  schema_tables:   schema_data_or_nil,
  models:          model_data_or_nil
}
```

### Pipeline Steps

#### `AgentsMdStep`

For each module root: builds file tree, transforms analyses to files data, calls `AgentsMdGenerator.generate` with `config: config`, writes `AGENTS.md` to output. The `config:` parameter enables LLM integration when LLM settings are configured.

#### `ReadmeStep`

Generates project-level `README.md` with project stats, module summary, and file count.

#### `IndexSummaryVectorsStep`

For each module root and the project level: generates `INDEX.md`, `SUMMARY.md`, and `VECTORS.json`.

#### `DiagramStep`

Conditionally generates Mermaid diagrams based on project content:
- DAG (dependency graph) — always if `generate_dag` config
- Class diagram — if class inheritance detected
- C4 context/container — always
- ERD — if Rails schema detected

#### `ArchitectureStep`

Generates `architecture.md` using C4-informed template with context and container data.

#### `ManifestStep`

Generates `.map.json` cross-reference manifest listing all generated artifacts.

## Data Flow Through Pipeline

```
Input: analyses hash
   │
   ▼
┌─────────────────┐
│  AgentsMdStep    │ → writes AGENTS.md per module
│  (FilesData      │
│   Builder)       │
└────────┬────────┘
         ▼
┌─────────────────┐
│  ReadmeStep      │ → writes README.md
└────────┬────────┘
         ▼
┌─────────────────────────┐
│ IndexSummaryVectorsStep │ → writes INDEX.md, SUMMARY.md, VECTORS.json
└────────┬────────────────┘
         ▼
┌─────────────────┐
│  DiagramStep     │ → writes diagrams/*.mmd
│  (GraphData      │
│   Builders)      │
└────────┬────────┘
         ▼
┌─────────────────┐
│  ArchitectureStep│ → writes architecture.md
└────────┬────────┘
         ▼
┌─────────────────┐
│  ManifestStep    │ → writes .map.json
└────────┬────────┘
         ▼
Output: stats hash
```