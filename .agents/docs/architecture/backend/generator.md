# Auto-Doc — Generator Module

## Purpose

Generates documentation artifacts from analysis data. Each generator reads an ERB template and renders it with extracted data. All generators share the `TemplateHelper` mixin.

## Template System

Templates reside in `templates/` directory. Generators can override template paths via environment variables:

| Generator | Environment Variable | Default Template |
|-----------|---------------------|-------------------|
| `AgentsMdGenerator` | `AUTO_DOC_TEMPLATE` | `agents_md_template.erb` |
| `SummaryGenerator` | `AUTO_DOC_TEMPLATE_SUMMARY` | `summary_template.erb` |

## Generators

### `AgentsMdGenerator`

Generates per-module `AGENTS.md` files documenting the public API surface.

**Signature:** `self.generate(module_name, tree_text, files, config: nil, output_path: nil)`

**Template variables:**
- `module_name` — Directory name
- `tree_text` — Box-drawing directory tree
- `files` — Array of file analysis records with `:name`, `:path`, `:classes`, `:imports`
- `source_file_count` — Number of source files
- `public_symbols` — Extracted classes, modules, methods
- `public_symbol_count` — Number of public symbols
- `purpose_summary` — LLM-generated summary when configured; `nil` (placeholder) when LLM unavailable
- `dependencies` — Array of imports
- `generated_at` — ISO8601 timestamp

**LLM integration:** Uses `TemplateHelper` mixin for `llm_primary?` gate. When `config:` is provided and `llm_primary?` is true, `llm_purpose_summary` calls `Summarizer.summarize_module` via `Client.build_if_configured(@config)`. Falls back to placeholder text with `warn_llm_fallback` on any failure. In non-primary mode, `purpose_summary` is always the static placeholder "developer to fill in".

### `SummaryGenerator`

Generates per-module `SUMMARY.md` files with executive summaries. Uses LLM when configured, with graceful fallback to static inference.

**Signature:** `self.generate(dir_name, analyses, config, output_path: nil)`

**Template variables:**
- `dir_name` — Directory name
- `purpose` — LLM-generated via `llm_purpose` (calls `Summarizer.summarize_module`); falls back to `infer_purpose`
- `key_components` — LLM-generated via `llm_components` (calls `Summarizer.summarize_components`); falls back to `extract_key_components`
- `architecture_pattern` — LLM-generated via `llm_architecture` (calls `Summarizer.summarize_architecture`); falls back to `infer_architecture_pattern`
- `dependencies_overview` — Built from `build_dependencies_overview` (import data, always static)
- `generated_at` — Timestamp

**LLM integration:** Uses `TemplateHelper` mixin for `llm_primary?` gate. When `llm_primary?` is true, calls all three LLM methods with fallback to `warn_llm_fallback`. In non-primary mode, all LLM sections use static inference directly (zero LLM calls).

**LLM methods:**
- `llm_purpose` — Builds client via `Client.build_if_configured(@config)`, calls `Summarizer.summarize_module`. Returns `nil` on any failure.
- `llm_architecture` — Same pattern, calls `Summarizer.summarize_architecture`
- `llm_components` — Same pattern, calls `Summarizer.summarize_components`, wraps result as single component entry

**Static inference fallback methods:**
- `infer_purpose` — Case statement on directory name (lib, app, spec, bin, config, db, docs) with fallback to file count description
- `extract_key_components` — Filters definitions to classes/modules, looks up YARD summaries, limits to 20
- `infer_architecture_pattern` — Filename-based heuristics (controller/model/view → MVC, service/interactor → service-oriented, etc.)
- `build_dependencies_overview` — Categorizes imports as local/path/stdlib-gem

### `ReadmeGenerator`

Generates project-level `README.md` with project overview, module summary, and statistics.

**Signature:** `self.generate(project_name, structure, summary_stats, output_path: nil, config: nil, analyses: nil)`

**Template variables:**
- `project_name` — Project name
- `structure` — Hash of module root name → file tree text
- `summary_stats` — Stats hash (total_modules, total_classes, total_methods, coverage_pct)
- `generated_at` — Timestamp
- `files` — Derived from structure for template compatibility
- `overview_text` — LLM-generated via `llm_module_overview` when `llm_primary?`; always static placeholder "Developer to fill in" in non-primary mode

**LLM integration:** Uses `TemplateHelper` mixin. When `config:` and `analyses:` are provided and `llm_primary?` is true, `llm_module_overview` calls `Summarizer.summarize_module`. Falls back to placeholder text with `warn_llm_fallback` on any failure.

### `IndexGenerator`

Generates `INDEX.md` files at project and module levels with hierarchical file/symbol/dependency listings.

### `VectorGenerator`

Generates `VECTORS.json` with keyword vectors for all symbols (used by search).

### `DiagramGenerator`

Generic diagram generator using ERB templates. Produces dependency DAG diagrams.

**Template:** `diagram_dag_template.erb`

### `C4DiagramGenerator`

Generates C4 architecture diagrams (context and container levels).

**Templates:** `c4_context_template.erb`, `c4_container_template.erb`

### `ClassDiagramGenerator`

Generates class inheritance diagrams from `ClassHierarchyBuilder` data.

**Template:** `class_diagram_template.erb`

### `ErdGenerator`

Generates Entity-Relationship Diagrams from Rails schema data. Rails-only.

**Template:** `erd_template.erb`

### `ArchitectureGenerator`

Generates `architecture.md` using C4-informed data. LLM enhancement gated behind `llm_primary? && @auto_doc_config && @analyses`.

**Signature:** `self.generate(project_name, schema_tables, models, class_hierarchy, config = {}, output_path: nil, analyses: nil, auto_doc_config: nil)`

**Template:** `architecture_template.erb`

**LLM integration:** Uses `TemplateHelper` mixin (checking `@auto_doc_config` for `llm_primary?`). When primary mode is active:
1. Calls `Summarizer.summarize_architecture_full` (single LLM call returning structured hash with `:purpose`, `:style`, `:modules`, `:data_flow`)
2. Parses modules via `Summarizer.parse_architecture_modules(summary)`
3. Parses data flows via `Summarizer.parse_architecture_data_flows(summary)`
4. Uses LLM results for each section where available; falls through to model-based logic (Rails associations, static heuristics)
5. Entire LLM block wrapped in `begin/rescue StandardError` — any exception causes full fallback to static mode

**Note:** Uses `@auto_doc_config` (separate from `@config` used by other generators) to distinguish between internal config parameters and the AutoDoc::Config object.

### `MapGenerator`

Generates `.map.json` cross-reference manifest. No template — produces JSON directly.

### `TemplateHelper` (`generator/template_helper.rb`)

Mixin module shared by all generators. Now includes LLM primary driver support.

**Methods:**
- `read_template(path)` — Reads template file, handles missing files gracefully
- `llm_primary?` — Returns `true` when the config has `llm.primary: true`. Checks `@auto_doc_config` first (used by `ArchitectureGenerator`), then `@config` (used by other generators). Returns `false` if neither is set or neither responds to `llm_primary?`
- `warn_llm_fallback(description)` — Emits a consistent `$stderr` warning when LLM fails in primary mode: `"[AutoDoc] LLM unavailable for {name} {description} — using static inference."`
- Template path resolution via environment variable override

## Available Templates

```
templates/
├── agents_md_template.erb
├── architecture_template.erb
├── c4_container_template.erb
├── c4_context_template.erb
├── class_diagram_template.erb
├── diagram_dag_template.erb
├── erd_template.erb
├── index_template.erb
├── readme_template.erb
└── summary_template.erb
```