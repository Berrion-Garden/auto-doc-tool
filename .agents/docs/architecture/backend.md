# Backend — Directory Layout and Modules

## Directory Layout

```
lib/
├── auto_doc.rb                          # Main entry point; requires all submodules
├── auto_doc/
│   ├── version.rb                       # VERSION = "0.2.0"
│   ├── config.rb                        # Configuration loader with .autodoc→.docs migration
│   ├── cli.rb                           # Thor CLI with subcommands
│   ├── orchestrator.rb                  # Pipeline coordinator
│   ├── server.rb                        # Sinatra web server for browsing docs
│   ├── search_service.rb               # Full-text search service
│   ├── analyzer/
│   │   ├── source_parser.rb             # Parses Ruby source: classes, modules, methods
│   │   ├── import_extractor.rb          # Extracts require/include/extend statements
│   │   ├── yard_reader.rb               # Extracts YARD doc comments
│   │   ├── schema_parser.rb             # Parses Rails db/schema.rb tables
│   │   ├── model_association_parser.rb  # Parses Rails model associations
│   │   ├── diff_service.rb              # Detects undocumented changes since git ref
│   │   └── orphans_service.rb           # Finds undocumented, unreferenced files
│   ├── generator/
│   │   ├── template_helper.rb           # Shared read_template method (module)
│   │   ├── agents_md_generator.rb       # AGENTS.md per module root
│   │   ├── readme_generator.rb          # Project-level README.md
│   │   ├── index_generator.rb           # INDEX.md per directory (Phase 2a)
│   │   ├── summary_generator.rb         # SUMMARY.md per directory (Phase 2a)
│   │   ├── vector_generator.rb          # VECTORS.json project + per-dir (Phase 2a)
│   │   ├── diagram_generator.rb         # Dependency DAG diagrams
│   │   ├── class_diagram_generator.rb   # Class hierarchy diagram
│   │   ├── erd_generator.rb             # Entity-relationship diagram (Rails)
│   │   ├── c4_diagram_generator.rb      # C4 context + container diagrams
│   │   └── architecture_generator.rb    # architecture.md overview
│   ├── reporter/
│   │   ├── audit_reporter.rb            # Generates and formats audit reports
│   │   └── completeness_checker.rb      # Calculates per-symbol coverage
│   ├── utils/
│   │   ├── yaml_config_loader.rb        # YAML file reader with error handling
│   │   ├── file_tree_builder.rb         # Builds tree text from directory
│   │   ├── timestamp_tracker.rb         # Incremental tracking via manifest
│   │   └── output_formatter.rb          # Text/JSON/Agent output routing (Phase 2a)
│   └── tester/
│       └── e2e_runner.rb                # End-to-end self-test
```

## Module Summaries

### Core Modules

- **`AutoDoc::Config`** — Reads `.autodoc.yml` by walking up the directory tree, merges with defaults (`DEFAULTS` constant), applies CLI overrides. `output_dir` method handles `.autodoc`→`.docs` migration with backward-compat fallback. Uses `key?` checks for numeric config values to avoid masking zero.

- **`AutoDoc::CLI`** — Thor-based CLI. Class options `--json` and `--agent` (added Phase 2a). Subcommands: `init`, `generate`, `diff`, `audit`, `version`, `orphans`, `serve`, `e2e`, `verify`. Private `output_format_for` method routes agent→json→text. `orchestrator` method returns a memoized `Orchestrator` instance.

- **`AutoDoc::Orchestrator`** — Central pipeline coordinator. `generate` method: resolves module roots, analyzes files (via SourceParser, ImportExtractor, YardReader), generates AGENTS.md per root, walks subdirectories for INDEX/SUMMARY/vectors, generates README.md, diagrams (deps.mmd, class_diagram.mmd, ERD, C4), architecture.md, project-level INDEX/SUMMARY/VECTORS. `audit` method: analyzes files, generates report, writes report.json.

### Analyzers (`lib/auto_doc/analyzer/`)

| File | Class | Purpose |
|------|-------|---------|
| `source_parser.rb` | `SourceParser` | Parses Ruby source files for class/module/method definitions |
| `import_extractor.rb` | `ImportExtractor` | Extracts require/require_relative/include/prepend/extend statements |
| `yard_reader.rb` | `YardReader` | Extracts YARD doc comments and summaries |
| `schema_parser.rb` | `SchemaParser` | Parses Rails db/schema.rb to extract table definitions |
| `model_association_parser.rb` | `ModelAssociationParser` | Parses Rails model files for association declarations |
| `diff_service.rb` | `DiffService` | Compares Ruby files since a git ref, finds undocumented changes |
| `orphans_service.rb` | `OrphansService` | Finds Ruby files not documented, not imported, not referenced |

### Generators (`lib/auto_doc/generator/`)

| File | Class | Output |
|------|-------|--------|
| `template_helper.rb` | Module | Shared `read_template(path)` method — deduplicated across all generators |
| `agents_md_generator.rb` | `AgentsMdGenerator` | AGENTS.md per module root |
| `readme_generator.rb` | `ReadmeGenerator` | Project-level README.md |
| `index_generator.rb` | `IndexGenerator` | INDEX.md per directory |
| `summary_generator.rb` | `SummaryGenerator` | SUMMARY.md per directory |
| `vector_generator.rb` | `VectorGenerator` | VECTORS.json (project) + vectors.json (per dir) |
| `diagram_generator.rb` | `DiagramGenerator` | Dependency DAG (deps.mmd) |
| `class_diagram_generator.rb` | `ClassDiagramGenerator` | Class hierarchy diagram (class_diagram.mmd) |
| `erd_generator.rb` | `ERDGenerator` | Entity-relationship diagram (erd.mmd) |
| `c4_diagram_generator.rb` | `C4DiagramGenerator` | C4 context and container diagrams |
| `architecture_generator.rb` | `ArchitectureGenerator` | architecture.md |

### Reporters (`lib/auto_doc/reporter/`)

| File | Class | Purpose |
|------|-------|---------|
| `audit_reporter.rb` | `AuditReporter` | Generates audit report with coverage stats, formatted as text or JSON |
| `completeness_checker.rb` | `CompletenessChecker` | Calculates per-symbol documentation coverage percentage |

### Utilities (`lib/auto_doc/utils/`)

| File | Class | Purpose |
|------|-------|---------|
| `yaml_config_loader.rb` | `YamlConfigLoader` | Reads YAML config files with error handling |
| `file_tree_builder.rb` | `FileTreeBuilder` | Builds tree-text representation of a directory |
| `timestamp_tracker.rb` | `TimestampTracker` | Tracks file mtimes in `generation_manifest.json` for incremental generation |
| `output_formatter.rb` | `OutputFormatter` | Routes output to :text, :json, or :agent mode (Phase 2a) |

### Other

| File | Class | Purpose |
|------|-------|---------|
| `search_service.rb` | `SearchService` | Full-text search across documentation |
| `server.rb` | `Server` (Sinatra) | Sinatra web server serving generated docs via HTTP |
| `tester/e2e_runner.rb` | `E2ERunner` | Self-test that runs generate+audit on itself |