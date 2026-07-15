# Config Module

## Class: `AutoDoc::Config`

**File:** `lib/auto_doc/config.rb`

### Purpose

Configuration loader that reads `.autodoc.yml` with fallback defaults. CLI flags are merged on top and take precedence.

### Default Configuration

```ruby
DEFAULTS = {
  module_roots: %w[app lib bin],
  exclude_patterns: %w[vendor/**/* node_modules/**/* spec/**/*],
  output: {
    directory: ".docs",
    format: "markdown"
  },
  audit: {
    min_doc_coverage: 80,
    max_module_size: 50
  },
  diagrams: {
    generate_dag: true,
    diagram_directory: "diagrams"
  }
}.freeze
```

### Key Methods

- **`Config.load(path, overrides = {})`** — Class method that instantiates Config with path and CLI overrides.
- **`initialize(path, overrides = {})`** — Loads file config by walking up from `path`, merges defaults, then file config, then overrides.
- **`output_dir`** — **Phase 2a change.** Returns the resolved output directory path. Checks: (1) configured directory exists on disk → use it, (2) configured dir doesn't exist but `.autodoc/` does → fall back with migration notice, (3) neither exists → return configured (defaults to `.docs`).
- **`module_roots`**, **`exclude_patterns`**, **`min_doc_coverage`**, **`max_module_size`**, **`generate_dag?`**, **`diagram_directory`** — Convenience accessors with fallback to `DEFAULTS`.
- **`read_file_config`** (private) — Walks up from `@path` looking for `.autodoc.yml`, returns parsed YAML or `{}`.
- **`deep_merge`** (private) — Recursive hash merge; preserves existing keys when both hashes have the same key.

### Config Key Convention

Config keys use symbols (`:output`, `:directory`) internally. YAML files use kebab-case or snake-case (e.g., `module_roots`, `generate_dag`).

### Phase 2a Changes

- **`DEFAULTS[:output][:directory]`** changed from `".autodoc"` to `".docs"`.
- **`output_dir`** method added with backward-compat fallback logic (`.autodoc/` → `.docs/` migration notice).
- **Numeric fallbacks** fixed: `min_doc_coverage` and `max_module_size` use `audit_config.key?(:key)` instead of `||` to avoid masking zero values.
- **`CLI.generate_default_config_yml`** emits `directory: .docs` in generated YAML.