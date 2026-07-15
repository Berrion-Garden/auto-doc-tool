# Infrastructure

## Gem Dependencies

### Runtime

| Dependency | Version | Purpose |
|------------|---------|---------|
| `thor` | (gemspec default) | CLI framework |
| `sinatra` | ~> 4.0 | Web server for `serve` command |
| `yard` | ~> 0.9.44 | Optional — structured YARD doc parsing |

### Development

| Dependency | Version | Purpose |
|------------|---------|---------|
| `rspec` | ~> 3.0 | Test framework |
| `rack-test` | ~> 2.1 | HTTP test helper for Server specs |

## Boot Sequence

1. `require 'auto_doc'` loads `lib/auto_doc.rb`
2. `auto_doc.rb` requires submodules in layered order:
   a. `version.rb`
   b. Config & utilities: `config`, `yaml_config_loader`, `file_tree_builder`, `timestamp_tracker`, `output_formatter`
   c. Analyzers: `source_parser`, `schema_parser`, `model_association_parser`, `import_extractor`, `yard_reader`, `diff_service`, `orphans_service`
   d. Generators: `template_helper`, `agents_md_generator`, `readme_generator`, `diagram_generator`, `index_generator`, `summary_generator`, `vector_generator`, `c4_diagram_generator`, `class_diagram_generator`, `erd_generator`, `architecture_generator`
   e. Reporters: `completeness_checker`, `audit_reporter`
   f. `search_service`
   g. `orchestrator`
   h. `cli`
   i. `tester/e2e_runner`
   j. `server`
3. `AutoDoc::CLI.start(ARGV)` begins command processing

## CLI Entry Point

- Binary: `exe/auto-doc`
- Invocation: `auto-doc <subcommand> [options] [project_dir]`
- Subcommands: `init`, `generate`, `audit`, `diff`, `orphans`, `serve`, `e2e`, `verify`, `version`

## Configuration

- Config file: `.autodoc.yml` (YAML)
- Walks up directory tree from project dir to find config
- Supports: `module_roots`, `exclude_patterns`, `output` dir, `audit` thresholds, `diagrams` flags
- `.autodoc/` → `.docs/` migration with backward-compat fallback

## Output

- Default: `.docs/` directory
- Per module root: `AGENTS.md`, `INDEX.md`, `SUMMARY.md`, `vectors.json`
- Project level: `README.md`, `INDEX.md`, `SUMMARY.md`, `VECTORS.json`
- Diagrams: `.docs/diagrams/` — `deps.mmd`, `class_diagram.mmd`, `c4_context.mmd`, `c4_container.mmd`, `erd.mmd`
- Audit: `report.json` (or `.docs/report.json` when writing to `.docs/`)

## Templates

ERB templates live in `templates/` directory:

| Template | Used By |
|----------|---------|
| `agents_md_template.erb` | AgentsMdGenerator |
| `readme_template.erb` | ReadmeGenerator |
| `index_template.erb` | IndexGenerator |
| `summary_template.erb` | SummaryGenerator |
| `diagram_dag_template.erb` | DiagramGenerator |
| `class_diagram_template.erb` | ClassDiagramGenerator |
| `erd_template.erb` | ERDGenerator |
| `c4_context_template.erb` | C4DiagramGenerator |
| `c4_container_template.erb` | C4DiagramGenerator |
| `architecture_template.erb` | ArchitectureGenerator |

All generators use `TemplateHelper.read_template(path)` to load templates.

## Deployment

```bash
gem build auto-doc.gemspec
gem push auto-doc-<version>.gem
```

## Dev Setup

```bash
bundle install
rspec
```

Template regeneration (after template changes):

```bash
ruby -Ilib exe/auto-doc generate .
```