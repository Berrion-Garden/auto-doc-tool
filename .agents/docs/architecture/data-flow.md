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
            ├── AgentsOverviewStep.run(context)
            │       │
            │       └── AgentsOverviewGenerator.generate(project_name, tree_text, analyses,
            │               config:, output_path:)
            │               │
            │               ├── llm_primary? == true
            │               │       ├── llm_generate_section(:agents_overview_overview)
            │               │       ├── llm_generate_section(:agents_overview_tech_stack)
            │               │       ├── llm_generate_section(:agents_overview_architecture)
            │               │       └── llm_generate_section(:agents_overview_conventions)
            │               │       └── All delegate to PromptBuilder.build(:agents_overview_*)
            │               │
            │               └── llm_primary? == false → static overview text
            │
            ├── AgentsMdStep.run(context)
            │       │
            │       └── for each module_root:
            │               FileTreeBuilder.build(root, excludes)
            │               FilesDataBuilder.build(file_analyses)
            │               AgentsMdGenerator.generate(name, tree, files, config:, output_path:)
            │                       │
            │                       ├── llm_primary? == true (default)
            │                       │       ├── Client.build_if_configured(config)
            │                       │       │       ├── AUTO_DOC_DISABLE_LLM check
            │                       │       │       ├── config.llm_config validation
            │                       │       │       └── Client.configured? check
            │                       │       ├── (client available) Summarizer.summarize_module
            │                       │       │       └── PromptBuilder.build(:agents_md, ...)
            │                       │       │       └── ResponseParser.parse_purpose(...)
            │                       │       ├── (success) → purpose_summary = LLM result
            │                       │       └── (failure) → warn_llm_fallback + placeholder text
            │                       │
            │                       └── llm_primary? == false
            │                               └── purpose_summary = placeholder text (zero LLM calls)
            │
            ├── ReadmeStep.run(context)
            │       │
            │       └── ReadmeGenerator.generate(project_name, structure, stats,
            │               config:, analyses:, output_path:)
            │               │
            │               ├── llm_primary? == false → overview_text = placeholder
            │               └── llm_primary? == true
            │                       └── Summarizer.summarize_module → llm_module_overview
            │
            ├── IndexSummaryVectorsStep.run(context)
            │       │
            │       ├── IndexGenerator.generate(project-level)
            │       ├── SummaryGenerator.generate(project-level)
            │       │       │
            │       │       ├── llm_primary? == false
            │       │       │       └── infer_purpose, extract_key_components, infer_architecture_pattern
            │       │       │
            │       │       └── llm_primary? == true
            │       │               ├── llm_purpose → Summarizer.summarize_module
            │       │               ├── llm_architecture → Summarizer.summarize_architecture
            │       │               ├── llm_components → Summarizer.summarize_components
            │       │               └── any failure → warn_llm_fallback + static fallback
            │       │
            │       ├── VectorGenerator.generate(project-level)
            │       └── for each module_root:
            │               IndexGenerator.generate(module-level)
            │               SummaryGenerator.generate(module-level)  (same LLM gate pattern)
            │               VectorGenerator.generate(module-level)
            │
            ├── DiagramStep.run(context)
            │       │
            │       ├── GraphDataBuilder.build(analyses) → DAG data
            │       ├── ClassHierarchyBuilder.build(analyses) → inheritance
            │       ├── ContainerDataFlowBuilder.build(analyses) → containers
            │       ├── (if llm_primary?) Summarizer.summarize_system_context → C4 context
            │       ├── (if llm_primary?) Summarizer.summarize_containers → C4 containers
            │       ├── ERD (if Rails): SchemaParser + ModelAssociationParser
            │       └── Diagram generators for each type
            │
            ├── ArchitectureStep.run(context)
            │       │
            │       └── ArchitectureGenerator.generate(project_name, schema_tables, models,
            │               class_hierarchy, config, output_path:, analyses:, auto_doc_config:)
            │               │
            │               ├── llm_primary? == false or no analyses
            │               │       └── Model-based data (Rails associations, static heuristics)
            │               │
            │               └── llm_primary? == true && @auto_doc_config && @analyses
            │                       ├── Summarizer.summarize_architecture_full
            │                       │       └── PromptBuilder.build(:architecture_full, ...)
            │                       │       └── ResponseParser.parse_architecture_full(...)
            │                       │       └── returns { purpose:, style:, modules:, data_flow: }
            │                       ├── LLM success → use parsed results for sections
            │                       │       ├── Summarizer.parse_architecture_modules(summary)
            │                       │       └── Summarizer.parse_architecture_data_flows(summary)
            │                       └── rescue StandardError → full static fallback
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