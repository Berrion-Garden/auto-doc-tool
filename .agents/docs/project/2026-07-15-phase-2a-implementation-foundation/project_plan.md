# Project Plan: 2026-07-15-phase-2a-implementation-foundation

## Hypotheses Considered

### Hypothesis 1: All-at-once
Build all new generators, templates, formatter, plus all config/CLI/orchestrator wiring in a single monolithic milestone. Risk: large diff footprint makes incremental testing hard and creates merge conflicts between overlapping file edits.

### Hypothesis 2: Bottom-up config-first interleaved
Config `.autodoc`→`.docs` migration first, then generators, then wiring. Risk: config change in M1 breaks orchestrator, e2e_runner, server until M3 wires correct consumers — leaves intermediate broken state.

### Hypothesis 3: Staggered by artifact type
INDEX+SUMMARY first (M1), VECTORS second (M2), formatting/CLI third (M3), config migration last (M4). Risk: config migration last means all new generators initially target wrong directory, requiring rework.

### Selected: Hypothesis 4 — Config migration in isolation, then generators in parallel, then CLI wiring

Config migration is the foundational change that every other milestone depends on. By doing it first and completely — `.autodoc` → `.docs` default, backward compat in all consumers, all hardcoded references updated — we establish a clean baseline. The generators then build on a stable output directory. OutputFormatter and CLI flags come last because they depend on generator output structure being defined.

---

## Milestone 1: Config Migration — `.autodoc` → `.docs` with Backward Compatibility

**Intent:** Change the default output directory from `.autodoc` to `.docs` across the entire codebase. Every file that hardcodes `.autodoc/` must use the config value or implement a backward-compatible fallback. This milestone establishes the foundation all new generators write into.

### Implementation

#### Backend Work Items
- [ ] `lib/auto_doc/config.rb`: Change `DEFAULTS[:output][:directory]` from `".autodoc"` to `".docs"`. Add backward-compat method `output_dir` that checks: `.docs/` config dir exists → use it, else `.autodoc/` exists → use it (print migration notice), else create `.docs/`. Update `generate_default_config_yml` in CLI to use `.docs`.
- [ ] `lib/auto_doc/utils/timestamp_tracker.rb`: Change `MANIFEST_PATH` from `".autodoc/generation_manifest.json"` to `".docs/generation_manifest.json"`. Also update the `".autodoc"` string in `save_manifest` `FileUtils.mkdir_p(dir)` call.
- [ ] `lib/auto_doc/server.rb`: Update `find_autodoc_dir` to try `.docs/` first, fall back to `.autodoc/` if `.docs/` doesn't exist but `.autodoc/` does. Update method name to `find_docs_dir`.
- [ ] `lib/auto_doc/tester/e2e_runner.rb`: Replace all hardcoded `.autodoc` references with a method or constant that reads from config. Update file existence checks for `README.md`, `diagrams/deps.mmd`, `report.json`, `AGENTS.md`.
- [ ] `lib/auto_doc/orchestrator.rb`: Update `audit` method — the `report.json` path at line 130 uses `.autodoc` hardcoded; change to use the resolved `output_dir` variable (already computed in `generate`, needs extraction or recomputation in `audit`).
- [ ] `lib/auto_doc/cli.rb`: Update `generate_default_config_yml` to emit `directory: .docs` in the default YAML. Update the `--format` option description: `"Output format: autodoc (.autodoc/) or docs (.docs/)"`. Ensure `--format docs` and `--format autodoc` both still work.
- [ ] `templates/agents_md_template.erb`, `templates/readme_template.erb`: Search for any `.autodoc` references in comments/default text and update to `.docs`.

#### Frontend Work Items
- N/A (backend-only milestone)

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | `Config#output_dir` returns `.docs` by default | `.docs` |
| Unit | `Config#output_dir` falls back to `.autodoc` when `.docs/` absent and `.autodoc/` present | `.autodoc` with migration notice |
| Unit | `Config#output_dir` creates `.docs/` when neither exists | `.docs` |
| Unit | `TimestampTracker` writes manifest to `.docs/generation_manifest.json` | Manifest in `.docs/` |
| Unit | `Server#find_docs_dir` finds `.docs/` first, then `.autodoc/` | Correct directory |
| Integration | `generate` writes output to `.docs/` by default | Files in `.docs/` |
| Integration | `generate --format autodoc` writes to `.autodoc/` for backward compat | Files in `.autodoc/` |
| E2E | `self_test_spec` passes with `.docs/` directory | All 55+ e2e checks pass |

### Verification Criteria
- [ ] `bundle exec rspec` — all 140+ existing specs pass
- [ ] New config spec tests `.docs` default and `.autodoc` backward compat
- [ ] Running `auto-doc generate` on fixtures creates `.docs/` not `.autodoc/`
- [ ] Running `auto-doc generate --format autodoc` still creates `.autodoc/`

---

## Milestone 2: INDEX.md + SUMMARY.md + VECTORS.json Generators

**Intent:** Create three new generators following the established pattern (AgentsMdGenerator, ReadmeGenerator). Each generator renders an ERB template with analysis data and supports per-directory output. Wire them into the orchestrator to generate artifacts for every directory within each module root.

### Implementation

#### Backend Work Items
- [ ] `templates/index_template.erb`: Create ERB template for INDEX.md. Schema: header (dir name, file count, symbol count, coverage pct), files table (numbered: name, classes, modules, methods, documented status), symbols table (alphabetical: symbol, type, file, line, doc checkbox), dependencies table (from → type → to), reverse dependencies, cross-references (parent INDEX.md link, sibling dirs).
- [ ] `templates/summary_template.erb`: Create ERB template for SUMMARY.md. Schema: one-line purpose, key components (top classes/modules with summaries), architecture pattern, dependencies overview, links to INDEX.md/AGENTS.md/diagrams.
- [ ] `lib/auto_doc/generator/index_generator.rb`: Create `IndexGenerator` class following existing generator pattern (`TEMPLATES_DIR`, `DEFAULT_TEMPLATE`, `.generate` class method, initialize+generate instance pattern). Accept `dir_name`, `dir_path`, `analyses` hash, `config`, optional `output_path`. Build files table, symbols table, dependencies table from analyses data.
- [ ] `lib/auto_doc/generator/summary_generator.rb`: Create `SummaryGenerator` class. Same pattern. Infers purpose from directory name + file names. Extracts key component summaries from YARD doc data. Infers architecture pattern from structure heuristics. Builds dependency overview from import data.
- [ ] `lib/auto_doc/generator/vector_generator.rb`: Create `VectorGenerator` class. Generates both project-level `VECTORS.json` (aggregate) and per-directory `vectors.json`. Each entry: id, symbol, type, scope, file, line, summary, signature, visibility, keywords (CamelCase/snake_case split, dedup, top 15), dependencies, consumed_by, parent_module. Uses `JSON.pretty_generate` for output.
- [ ] `lib/auto_doc/orchestrator.rb`: Wire new generators into the `generate` method. After generating AGENTS.md for each module root, walk EVERY directory within each module root recursively via `Dir.glob`. For each directory with Ruby files, generate `INDEX.md`, `SUMMARY.md`, `vectors.json`. At project level, generate `INDEX.md`, `SUMMARY.md`, `VECTORS.json`. Build aggregate symbol data for project-level VECTORS.json.
- [ ] `lib/auto_doc.rb`: Add `require_relative` lines for `index_generator`, `summary_generator`, `vector_generator`.

#### Frontend Work Items
- N/A (backend-only milestone)

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | `IndexGenerator.generate` returns markdown with dir name, files table, symbols table | Valid markdown with required sections |
| Unit | `IndexGenerator.generate` handles empty directory (no Ruby files) | Graceful empty state |
| Unit | `SummaryGenerator.generate` infers purpose from dir name | Purpose text present |
| Unit | `SummaryGenerator.generate` includes key components and architecture pattern | Sections populated |
| Unit | `VectorGenerator.generate` produces valid JSON with correct schema | Valid JSON, id/symbol/type/file/line fields |
| Unit | `VectorGenerator.generate` project-level aggregates all symbols | Symbols from all dirs |
| Unit | `VectorGenerator` keyword extraction splits CamelCase/snake_case | Keywords list without stop words |
| Integration | Full `generate` run creates INDEX.md in every module root subdirectory | INDEX.md files present |
| Integration | Full `generate` run creates VECTORS.json at project level | Project VECTORS.json present |
| Integration | Full `generate` run creates vectors.json per directory | Per-directory vectors.json present |

### Verification Criteria
- [ ] `bundle exec rspec` — all existing + new specs pass
- [ ] `auto-doc generate` on fixtures creates INDEX.md, SUMMARY.md, vectors.json in each directory
- [ ] Project-level `.docs/VECTORS.json` contains symbols from all analyzed files
- [ ] Per-directory `.docs/lib/vectors.json`, `.docs/app/vectors.json` contain only that dir's symbols

---

## Milestone 3: OutputFormatter + --json/--agent CLI Flags

**Intent:** Add `OutputFormatter` utility that routes human-readable, JSON, and agent-optimized JSON output. Add `--json` and `--agent` class options to the CLI, wired through all subcommands. This milestone depends on M2 because the formatter needs to know the output structure of generate/audit results.

### Implementation

#### Backend Work Items
- [ ] `lib/auto_doc/utils/output_formatter.rb`: Create `OutputFormatter` class with `.format(data, format:, say:)` class method. Three modes: `:text` (current `say.call` behavior — pass through), `:json` (`JSON.pretty_generate(data)` with all fields), `:agent` (compact JSON, only essential keys, stripped of timestamps/formatting noise). Uses `JSON.generate` for agent mode to avoid line noise.
- [ ] `lib/auto_doc/cli.rb`: Add at top (after `class_option :verbose`): `class_option :json, type: :boolean, default: false, desc: ...` and `class_option :agent, type: :boolean, default: false, desc: ...`. In each subcommand (`generate`, `audit`, `diff`, `orphans`), after getting results, route through `OutputFormatter.format`. Agent flag takes precedence over json flag. Text mode preserves current behavior exactly.
- [ ] `lib/auto_doc.rb`: Add `require_relative` for `output_formatter`.

#### Frontend Work Items
- N/A (backend-only milestone)

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | `OutputFormatter.format(data, format: :json)` produces valid pretty JSON | Valid JSON with all fields |
| Unit | `OutputFormatter.format(data, format: :agent)` produces compact JSON | Compact, no timestamps/noise |
| Unit | `OutputFormatter.format(data, format: :text)` passes through to `say` | Original text output |
| Integration | `auto-doc audit --json` outputs JSON to stdout | Valid JSON on stdout |
| Integration | `auto-doc audit --agent` outputs compact JSON | Compact JSON on stdout |
| Integration | `auto-doc generate --json` outputs structured JSON | JSON with file list/summary |
| Integration | `auto-doc diff --json HEAD~1` outputs JSON | JSON diff structure |
| Integration | `--agent` flag takes precedence over `--json` | Agent output when both set |

### Verification Criteria
- [ ] `bundle exec rspec` — all specs pass
- [ ] `auto-doc audit --json` on fixtures produces valid pretty JSON
- [ ] `auto-doc audit --agent` on fixtures produces compact JSON
- [ ] `auto-doc audit` (no flags) still produces human-readable text (no regression)
- [ ] `auto-doc generate --json` on fixtures produces structured JSON output
