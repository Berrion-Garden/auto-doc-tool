# Orchestrator Submodule — Backend

## Orchestrator (`orchestrator.rb`)

The top-level orchestration class extracted from the CLI. Accepts explicit parameters and returns results. Handles three main entry points:

### `#generate(path, say:)`

Full documentation generation pipeline:
1. Load config (`Config.load`)
2. Resolve module roots
3. Run analysis pipeline (with optional incremental mode)
4. **Enrich analyses** with LLM-generated summaries via `Enricher.enrich_analyses(analyses, config, base_dir: target_dir)`
5. Run the generation pipeline (`Pipeline.new(config).run(...)`)
6. Return stats merged with created files list

Key implementation detail: the Enricher is called **after** `analyze_project` but **before** the pipeline steps. This ensures all downstream steps have access to enriched `analyses[:docs]`.

### `#audit(path, threshold, say:, analyses:)`

Documentation coverage audit:
1. Run or reuse analysis
2. Generate audit report via `AuditReporter.generate`
3. Write JSON report to `<output_dir>/report.json`
4. Return report with pass/fail status

### Private methods

- `cli_overrides(options)` — Extracts CLI flags into config overrides (`exclude`, `incremental`, `llm-primary`)
- `resolve_module_roots(base_dir, config)` — Resolves module root paths to actual directories
- `analyze_project(base_dir, config, file_list)` — Runs analysis with optional cache for full-project scans
- `run_analysis_pipeline(base_dir, excludes, file_list)` — File globbing → `AnalysisPipeline.run` → `ImportExtractor` per file

## Pipeline (`orchestrator/pipeline.rb`)

Orchestrates 7 generation steps in order:

```
1. AgentsOverviewStep
2. AgentsMdStep
3. ReadmeStep
4. IndexSummaryVectorsStep
5. DiagramStep
6. ArchitectureStep
7. ManifestStep
```

Each step receives a shared `context` hash containing:
- `target_dir`, `output_dir`, `config`, `module_roots`
- `analyses` (the enriched analyses hash)
- `say` (output callback)
- `all_classes`, `all_methods`, `coverage_pct`
- `schema_tables`, `models`
- `class_hierarchy`, `container_data_flows`

Returns a stats hash with project name, output dir, module roots, counts, coverage percentage, and timestamps.

## Steps

### `base_step.rb` — Step Base Class

Abstract base class for pipeline steps. Provides common utilities:

- `say(context, msg, color)` — Formatting output through context callback
- `collect_symbol_summaries(analyses)` — **Shared method extracted during M3-R remediation**. Collects LLM-generated symbol summaries from `analyses[:docs]` arrays (populated by Enricher) and returns `{entry_id => summary_text}` hash. Used by both `AgentsMdStep` and `IndexSummaryVectorsStep`.

### `index_summary_vectors_step.rb` — INDEX/SUMMARY/VECTORS Generation

**Key change (from vectorize-everything task):**

The `collect_symbol_summaries` method was refactored to read pre-enriched summaries from `analyses[:docs]` instead of making separate LLM calls. By the time this step runs, the Enricher has already populated `analyses[:docs]` arrays with LLM-generated summaries.

**`collect_symbol_summaries(analyses, _module_roots, _config)`** — Builds an `llm_summaries` hash by iterating `analyses[:docs]` arrays and extracting `{entry_id => summary_text}` mappings. Returns nil when empty (preserving backward compat with code expecting nil).

**`walk_subdirectories`** — For each module root and its subdirectories, generates:
- INDEX.md (via `IndexGenerator`)
- SUMMARY.md (via `SummaryGenerator`)
- vectors.json (via `VectorGenerator.generate_directory`, for non-root dirs only)

### `agents_md_step.rb` — AGENTS.md Generation

Generates AGENTS.md files at each directory level.

### `agents_overview_step.rb` — Project Overview Generation

Generates the project-level AGENTS overview (overview, tech stack, architecture, conventions).

### `readme_step.rb` — README Generation

Generates project-level README.

### `diagram_step.rb` — Diagram Generation

Generates dependency, class, and ER diagrams.

### `architecture_step.rb` — Architecture Documentation

Generates architecture.md with LLM-powered content.

### `manifest_step.rb` — Manifest Generation

Generates the manifest.json cross-reference map.

### `metrics_helper.rb` — Metrics Utilities

Shared metrics calculation methods (counting classes, methods, coverage percentage).

## Analysis Pipeline (`analyzer/analysis_pipeline.rb`)

Distinct from `Orchestrator::Pipeline`. This is the source code analysis pipeline:

**Flow:**
```
Source files → SourceParser (AST parsing) → YardReader (doc extraction) → GenericScanner (language detection) → analyses hash
```

Returns `Hash<String, Hash>` of `file_path => { definitions: [...], docs: [...], language: ... }`.