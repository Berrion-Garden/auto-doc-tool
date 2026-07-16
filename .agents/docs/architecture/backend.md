# Auto-Doc — Backend Architecture

## Directory Layout

```
lib/auto_doc/
├── version.rb                     # VERSION = "1.0.0"
├── config.rb                      # Configuration management
├── cli.rb                         # Thor-based CLI
├── orchestrator.rb                # Workflow orchestration
├── documentation_index.rb         # Index document building
├── search_service.rb              # Full-text search across docs
├── agent_query_service.rb         # Natural-language query interpreter
├── server.rb                      # Sinatra web server
├── llm.rb                         # LLM module loader
│   ├── client.rb                  # OpenAI-compatible HTTP client
│   └── summarizer.rb              # Metadata-only prompt builder
├── analyzer/                      # Source code analysis
│   ├── analysis_cache.rb          # In-process analysis caching
│   ├── analysis_pipeline.rb       # Shared analysis pipeline
│   ├── source_parser.rb           # Ripper-based Ruby parser
│   ├── schema_parser.rb           # Rails db/schema.rb parser
│   ├── model_association_parser.rb # Rails model associations
│   ├── import_extractor.rb        # require/include/extend extraction
│   ├── yard_reader.rb             # YARD doc comment extraction
│   ├── diff_service.rb            # Documentation drift detection
│   └── orphans_service.rb         # Undocumented file finder
├── transformer/                   # Data transformation
│   ├── files_data_builder.rb      # Analysis → files array
│   ├── class_hierarchy_builder.rb # Inheritance hierarchy extraction
│   ├── erd_relationship_builder.rb # ERD relationship mapping
│   ├── container_data_flow_builder.rb # Container diagram data
│   └── graph_data_builder.rb      # DAG graph data
├── generator/                     # Document generators
│   ├── template_helper.rb         # ERB template reading mixin
│   ├── agents_md_generator.rb     # AGENTS.md generation
│   ├── readme_generator.rb        # README.md generation
│   ├── index_generator.rb         # INDEX.md generation
│   ├── summary_generator.rb       # SUMMARY.md generation
│   ├── vector_generator.rb        # VECTORS.json generation
│   ├── diagram_generator.rb       # Generic diagram generation
│   ├── c4_diagram_generator.rb    # C4 context/container diagrams
│   ├── class_diagram_generator.rb # Class inheritance diagrams
│   ├── erd_generator.rb           # Entity-relationship diagrams
│   ├── architecture_generator.rb  # Architecture documentation
│   └── map_generator.rb           # .map.json manifest
├── reporter/                      # Reporting
│   ├── completeness_checker.rb    # Documentation coverage checker
│   └── audit_reporter.rb          # Audit report generation
├── orchestrator/                  # Pipeline steps
│   ├── base_step.rb               # Step interface
│   ├── pipeline.rb                # Step orchestration
│   ├── agents_md_step.rb          # AGENTS.md step
│   ├── readme_step.rb             # README.md step
│   ├── index_summary_vectors_step.rb # INDEX/SUMMARY/VECTORS step
│   ├── diagram_step.rb            # Diagrams step
│   ├── architecture_step.rb       # Architecture doc step
│   └── manifest_step.rb           # Manifest step
├── utils/                         # Utilities
│   ├── yaml_config_loader.rb      # YAML parsing with fallback
│   ├── file_tree_builder.rb       # Directory tree with box-drawing chars
│   ├── output_formatter.rb        # Text/JSON/agent output formatting
│   ├── markdown_helper.rb         # Markdown formatting utilities
│   └── timestamp_tracker.rb       # Mtime-based change detection
└── tester/
    └── e2e_runner.rb              # End-to-end test runner
```

## Key Modules

### Config (`config.rb`)

Loads `.autodoc.yml` configuration with fallback defaults. Walks up directory tree to find config file. Merges CLI overrides on top.

**Defaults:**
- `module_roots`: `%w[app lib bin]`
- `exclude_patterns`: `%w[vendor/**/* node_modules/**/* spec/**/*]`
- `output.directory`: `".docs"`
- `audit.min_doc_coverage`: `80`
- `audit.max_module_size`: `50`
- `diagrams.generate_dag`: `true`
- `diagrams.diagram_directory`: `"diagrams"`
- `llm.provider`: `nil`
- `llm.endpoint`: `nil`
- `llm.api_key`: `nil`
- `llm.model`: `nil`
- `llm.timeout`: `30`

**Accessors:** `module_roots`, `exclude_patterns`, `output_dir`, `min_doc_coverage`, `max_module_size`, `generate_dag?`, `diagram_directory`, `llm_config`

### CLI (`cli.rb`)

Thor-based command interface with 17 commands. All commands support `--json` and `--agent` output format flags. Commands are delegated to the `Orchestrator` for `generate` and `audit`, or directly to service classes.

**Commands:** `init`, `generate` (`g`, `doc`, `gen`), `diff`, `audit`, `verify`, `search`, `query`, `tree`, `diagram`, `agent`, `orphans`, `serve`, `e2e`, `version`

**Output formats:** text (default), JSON (`--json`), agent-optimized JSON (`--agent`)

### Orchestrator (`orchestrator.rb`)

Central coordinator for documentation generation and auditing. Handles:
- Config loading and CLI override merging
- Output directory resolution (CLI flag > format option > config default)
- Module root detection
- Analysis pipeline execution with optional incremental mode
- Pipeline step execution
- Audit report generation and JSON output

**Key method:** `generate(path, say:)` — full documentation generation returning stats hash
**Key method:** `audit(path, threshold, say:, analyses:)` — coverage audit returning report hash

### Orchestrator Pipeline (`orchestrator/pipeline.rb`)

Sequential step pipeline that transforms analysis data into generated documents. Steps share a mutable context hash.

**Step order:**
1. `AgentsMdStep` — Generate per-module AGENTS.md
2. `ReadmeStep` — Generate project README.md
3. `IndexSummaryVectorsStep` — Generate INDEX.md, SUMMARY.md, VECTORS.json
4. `DiagramStep` — Generate Mermaid diagrams (DAG, class, C4, ERD)
5. `ArchitectureStep` — Generate architecture.md
6. `ManifestStep` — Generate .map.json cross-reference manifest

**Context shape:** `{ target_dir, output_dir, config, module_roots, analyses, say, all_classes, all_methods, coverage_pct, schema_tables, models, class_hierarchy, container_data_flows }`

**Return shape:** `{ project, output_dir, module_roots, analyses_count, classes_count, methods_count, coverage_pct, generated_at, schema_tables, models }`

### Analyzer Module

| Class | Purpose |
|-------|---------|
| `SourceParser` | Ripper.sexp-based Ruby parser. Extracts classes, modules, methods with line numbers and nesting. Returns `Definition` structs. |
| `YardReader` | Extracts YARD-style doc comments. Returns docs with `target_name`, `target_type`, `summary`, `has_summary?`. |
| `ImportExtractor` | Extracts `require`, `require_relative`, `include`, `extend`, `prepend` statements from source. |
| `SchemaParser` | Parses Rails `db/schema.rb` to extract table definitions and columns. |
| `ModelAssociationParser` | Extracts Rails model associations (`belongs_to`, `has_many`, etc.). |
| `AnalysisPipeline` | Shared pipeline: iterates files → `SourceParser.parse_file` + `YardReader.extract` → merges doc presence into definitions. |
| `AnalysisCache` | In-process caching of analysis results keyed by directory + config. Clearable via `clear!`. Used for `verify` and repeated commands. |
| `DiffService` | Compares current analysis against a git ref to find documentation drift. |
| `OrphansService` | Finds `.rb` files that are not documented, imported, or referenced. |

### Generator Module

Each generator reads an ERB template from `templates/` and renders it with analysis data. Generators share the `TemplateHelper` mixin for template loading.

| Generator | Output | Template |
|-----------|--------|----------|
| `AgentsMdGenerator` | `AGENTS.md` per module | `agents_md_template.erb` |
| `ReadmeGenerator` | `README.md` project-level | `readme_template.erb` |
| `IndexGenerator` | `INDEX.md` project/module level | `index_template.erb` |
| `SummaryGenerator` | `SUMMARY.md` per module | `summary_template.erb` |
| `VectorGenerator` | `VECTORS.json` | N/A (JSON output) |
| `DiagramGenerator` | Generic `.mmd` diagrams | `diagram_dag_template.erb` |
| `C4DiagramGenerator` | C4 context/container diagrams | `c4_context_template.erb`, `c4_container_template.erb` |
| `ClassDiagramGenerator` | Class inheritance diagrams | `class_diagram_template.erb` |
| `ErdGenerator` | Entity-relationship diagrams | `erd_template.erb` |
| `ArchitectureGenerator` | Architecture documentation | `architecture_template.erb` |
| `MapGenerator` | `.map.json` manifest | N/A (JSON output) |

### LLM Module

| Class | Purpose |
|-------|---------|
| `LLM::Client` | OpenAI-compatible HTTP client using `net/http` + `json` stdlib. Supports `chat(messages, options)`, `configured?`, `.from_config(config)`, `.build_if_configured(config)`. 30s timeout. Graceful failure (returns nil). |
| `LLM::Summarizer` | Builds metadata-only prompts (no source code). Class methods: `summarize_module(dir_name, analyses, client)`, `summarize_architecture(project_name, analyses, client)`, `summarize_components(analyses, client)`. |

**Status:** Fully implemented and integrated into `SummaryGenerator` (3 LLM calls: purpose, architecture, components) and `AgentsMdGenerator` (1 LLM call: purpose summary). All LLM calls use `Client.build_if_configured(config)` for safe client construction and have graceful fallback to static inference methods.

### Transformer Module

| Class | Purpose |
|-------|---------|
| `FilesDataBuilder` | Converts analysis hash to file array format for generators |
| `ClassHierarchyBuilder` | Extracts inheritance relationships from class definitions |
| `ErdRelationshipBuilder` | Builds ERD relationships from Rails schema/associations |
| `ContainerDataFlowBuilder` | Builds container diagram data from module structure |
| `GraphDataBuilder` | Builds DAG graph nodes and edges from import data |

### Reporter Module

| Class | Purpose |
|-------|---------|
| `CompletenessChecker` | Calculates documentation coverage percentage |
| `AuditReporter` | Generates audit reports with pass/fail status, per-file coverage, failure list |

### Server (`server.rb`)

Sinatra-based web server for browsing generated documentation. Binds to localhost:4567 by default. Provides HTML views and JSON API endpoints.

### Utilities

| Class | Purpose |
|-------|---------|
| `YamlConfigLoader` | YAML file parsing with safe load and fallback to empty hash |
| `FileTreeBuilder` | Builds directory tree string with Unicode box-drawing characters |
| `OutputFormatter` | Formats result hashes as text, JSON, or agent-optimized JSON |
| `MarkdownHelper` | Markdown formatting utilities for generators |
| `TimestampTracker` | Mtime-based file change detection for incremental generation |