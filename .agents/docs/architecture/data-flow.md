# Auto-Doc — Data Flow

## Request Lifecycle

### `auto-doc generate` Command

```
CLI (generate command)
    │
    ▼
Orchestrator.generate(path, say:)
    │
    ├── Config.load(target_dir, cli_overrides)
    │       │
    │       ├── Walk up directory tree for .autodoc.yml
    │       ├── deep_merge(DEFAULTS, file_config)
    │       └── deep_merge(result, cli_overrides)
    │
    ├── resolve_module_roots(target_dir, config)
    │       │
    │       └── config.module_roots → filter existing dirs → fallback [base_dir]
    │
    ├── analyze_project(target_dir, config, [file_list])
    │       │
    │       ├── AnalysisCache.fetch(base_dir, config) { ... }  (full scans only)
    │       │       │
    │       │       └── run_analysis_pipeline(base_dir, excludes, file_list)
    │       │               │
    │       │               ├── Dir.glob("**/*.rb") → filter excludes
    │       │               ├── AnalysisPipeline.run(ruby_files)
    │       │               │       │
    │       │               │       ├── SourceParser.parse_file(file) → definitions
    │       │               │       ├── YardReader.extract(file) → docs
    │       │               │       └── Merge has_doc? onto definitions
    │       │               │
    │       │               └── ImportExtractor.extract(file) → imports (per file)
    │       │
    │       └── (incremental mode: TimestampTracker.stale_files → file_list)
    │
    └── Pipeline.run(analyses, target_dir:, output_dir:, module_roots:, say:)
            │
            ├── AgentsMdStep.run(context)
            │       │
            │       └── for each module_root:
            │               FileTreeBuilder.build(root, excludes)
            │               FilesDataBuilder.build(file_analyses)
            │               AgentsMdGenerator.generate(name, tree, files, config:, output_path:)
            │                       │
            │                       ├── (if LLM configured) LLM::Client.build_if_configured(config)
            │                       │       ├── AUTO_DOC_DISABLE_LLM check
            │                       │       ├── config.llm_config validation
            │                       │       └── Client.configured? check
            │                       ├── (if client available) Summarizer.summarize_module → purpose_summary
            │                       └── (fallback) purpose_summary = nil → placeholder text
            │
            │   Additional Summarizer methods (available but not yet wired into pipeline steps):
            │   ├── Summarizer.summarize_architecture_full → multi-paragraph architecture overview
            │   ├── Summarizer.summarize_system_context → external systems interaction list (JSON or bullets)
            │   └── Summarizer.summarize_container_descriptions → module root descriptions keyed by name
            │
            ├── ReadmeStep.run(context)
            │       │
            │       └── ReadmeGenerator.generate(...)
            │
            ├── IndexSummaryVectorsStep.run(context)
            │       │
            │       ├── IndexGenerator.generate(project-level)
            │       ├── SummaryGenerator.generate(project-level)
            │       │       │
            │       │       ├── (if LLM configured) llm_purpose → Summarizer.summarize_module
            │       │       ├── (if LLM configured) llm_architecture → Summarizer.summarize_architecture
            │       │       ├── (if LLM configured) llm_components → Summarizer.summarize_components
            │       │       └── (fallback) infer_purpose, extract_key_components, infer_architecture_pattern
            │       │
            │       │   Additional Summarizer methods (available but not yet wired into SummaryGenerator):
            │       │   ├── Summarizer.summarize_architecture_full → multi-paragraph overview
            │       │   ├── Summarizer.summarize_system_context → external systems list
            │       │   └── Summarizer.summarize_container_descriptions → module descriptions
            │       ├── VectorGenerator.generate(project-level)
            │       └── for each module_root:
            │               IndexGenerator.generate(module-level)
            │               SummaryGenerator.generate(module-level)  (same LLM/fallback pattern)
            │               VectorGenerator.generate(module-level)
            │
            ├── DiagramStep.run(context)
            │       │
            │       ├── GraphDataBuilder.build(analyses) → DAG data
            │       ├── ClassHierarchyBuilder.build(analyses) → inheritance
            │       ├── ContainerDataFlowBuilder.build(analyses) → containers
            │       ├── ERD (if Rails): SchemaParser + ModelAssociationParser
            │       └── Diagram generators for each type
            │
            ├── ArchitectureStep.run(context)
            │       │
            │       └── ArchitectureGenerator.generate(context_data)
            │
            └── ManifestStep.run(context)
                    │
                    └── MapGenerator.generate(all_artifacts)
```

### `auto-doc audit` Command

```
CLI (audit command)
    │
    ▼
Orchestrator.audit(path, threshold, say:, analyses:)
    │
    ├── Config.load(target_dir, { audit: { min_doc_coverage: threshold } })
    │
    ├── analyze_project(target_dir, config)  (or reuse provided analyses)
    │       │
    │       └── AnalysisCache.fetch → same pipeline as generate
    │
    ├── AuditReporter.generate(target_dir, config, analyses)
    │       │
    │       ├── CompletenessChecker.check(analyses)
    │       │       │
    │       │       └── Count documented vs undocumented symbols
    │       │       └── Calculate per-file coverage percentages
    │       │
    │       └── Build report hash: { total_symbols, documented, undocumented,
    │            coverage_percent, passed_threshold, failures, ... }
    │
    └── Write report.json to output directory
```

### `auto-doc search` Command

```
CLI (search command)
    │
    ▼
SearchService.search(project_dir, term, options:)
    │
    ├── Search INDEX.md files (full-text)
    ├── Search VECTORS.json files (keyword match)
    ├── Search AGENTS.md files (full-text)
    └── (if --source) Search .rb source files
```

### `auto-doc serve` Command

```
CLI (serve command)
    │
    ▼
Sinatra server startup
    │
    ├── Set AUTO_DOC_SERVE_DIR environment variable
    ├── Configure port (default: 4567)
    └── Server.run!
```

## Data Transformation Pipeline

```
Raw Source Files (.rb)
    │
    ▼
┌───────────────────────────┐
│  SourceParser (Ripper)     │ → definitions array
│  YardReader               │ → docs array
│  ImportExtractor          │ → imports array
└───────────┬───────────────┘
            │
            ▼
    analyses hash: {
      "/path/to/file.rb" => {
        definitions: [{ name, type, line, methods, has_doc? }],
        docs: [{ target_name, target_type, summary }],
        imports: [{ path, type, line }]
      }
    }
            │
            ▼
┌───────────────────────────┐
│  Transformers              │
│  FilesDataBuilder          │ → files array for generators
│  ClassHierarchyBuilder     │ → inheritance relationships
│  GraphDataBuilder          │ → DAG nodes and edges
│  ContainerDataFlowBuilder  │ → container diagram data
│  ErdRelationshipBuilder    │ → ERD data (Rails)
└───────────┬───────────────┘
            │
            ▼
┌───────────────────────────┐
│  Generators (ERB)          │
│  AgentsMdGenerator         │ → AGENTS.md
│  ReadmeGenerator           │ → README.md
│  IndexGenerator            │ → INDEX.md
│  SummaryGenerator          │ → SUMMARY.md
│  VectorGenerator           │ → VECTORS.json
│  Diagram generators        │ → .mmd files
│  ArchitectureGenerator     │ → architecture.md
│  MapGenerator              │ → .map.json
└───────────────────────────┘
```

## Cache State Machine

```
┌──────────────────┐
│  No Cache Entry   │
└──────┬───────────┘
       │ AnalysisCache.fetch { block }
       ▼
┌──────────────────┐     File changed (mtime)
│  Cache Hit        │─────────────────────┐
│  (return cached) │                      │
└──────────────────┘                      ▼
                                        ┌──────────────┐
                                        │ Cache Miss /  │
                                        │ Re-analyze    │
                                        └──────┬───────┘
                                               │
                                               ▼
                                        ┌──────────────┐
                                        │ Cache Write   │
                                        │ (new results) │
                                        └──────────────┘
```