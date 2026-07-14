# Auto-Documentation Tool — Completion Plan
## Ruby Gem: `auto-doc` (v0.1.0)

**Status:** Pre-alpha — 4 of 13 spec files exist, 3 specs fail, 2 runtime bugs, 1 CLI subcommand missing, 0 runtime dependencies declared.

---

## Gap Analysis: Current vs Target

### What Works Today
| Area | Status | Details |
|------|--------|---------|
| Gem skeleton | ✅ | `auto-doc.gemspec`, `exe/auto-doc`, `Rakefile` |
| CLI `init` | ✅ | Creates `.autodoc.yml` with default config |
| CLI `generate` | ✅ | Runs analyzers + generators, writes `.autodoc/` output |
| CLI `audit` | ❌ **Runtime error** | `AuditReporter#generate` expects array of hashes; CLI passes hash-of-hashes → `TypeError` |
| CLI `diff` | ✅ | Git-based drift detection |
| CLI `version` | ✅ | Prints version |
| CLI `orphans` | ❌ **Missing** | Stubbed in PLAN.md but not implemented |
| Config loading | ✅ | Deep-merge from `.autodoc.yml` + CLI overrides |
| SourceParser | ❌ **2 bugs** | (1) `:program` handler wraps statements in extra array; (2) `extract_name` doesn't handle `[:const_ref, ...]` |
| ImportExtractor | ✅ | Regex-based require/include/prepend/extract extraction |
| YardReader | ❌ **No specs** | Exists, no unit tests |
| AgentsMdGenerator | ❌ **No specs** | Exists, no unit tests |
| ReadmeGenerator | ✅ | Has specs (passing) |
| DiagramGenerator | ❌ **No specs** | Exists, no unit tests |
| AuditReporter | ❌ **Runtime bug** | Analyses format mismatch between CLI and reporter |
| CompletenessChecker | ❌ **No specs** | Exists, no unit tests |
| FileTreeBuilder | ❌ **No specs** | Exists, no unit tests |
| YamlConfigLoader | ❌ **No specs** | Exists, no unit tests |
| CLI specs | ❌ **Missing** | No CLI tests at all |
| Specs pass? | ❌ **3 failures** | SourceParser spec fails due to parser bugs |
| Thor dependency | ❌ **Not declared** | Used in CLI but not in gemspec or Gemfile |

### Spec Coverage Gap
```
Current:  3 spec files (source_parser, import_extractor, readme_generator)
Target:  13 spec files (all modules + CLI)

Missing (10 files):
  cli_spec.rb              config_spec.rb           yard_reader_spec.rb
  agents_md_generator_spec.rb  diagram_generator_spec.rb  audit_reporter_spec.rb
  completeness_checker_spec.rb  file_tree_builder_spec.rb  yaml_config_loader_spec.rb
  auto_doc_spec.rb
```

### Runtime Bug: AuditReporter Analysis Format Mismatch

**`lib/auto_doc/reporter/audit_reporter.rb:38`** — `generate` method iterates `analyses` as an array of hashes expecting `:file`, `:symbols`, `:documented` keys. But CLI `audit` passes `analyze_project` output, which is a `Hash<String, Hash>` keyed by file path. The reporter gets a mismatched structure and throws `TypeError: no implicit conversion of Symbol into Integer`.

**Fix needed:** Either (a) transform CLI analysis data before passing to reporter, or (b) update `AuditReporter#generate` to accept the hash-of-hashes format.

### Runtime Bug: SourceParser Ripper Handling

**`lib/auto_doc/analyzer/source_parser.rb:67-68`** — `:program` handler does `sexp[1..-1]` which wraps the statements array inside another array. Ripper produces `[:program, [stmt1, stmt2]]` — `sexp[1..-1]` yields `[[stmt1, stmt2]]`, so the loop iterates once with the whole array as a single "child". This child (length 2) fails the `sexp.length >= 3` guard and is silently skipped.

**Fix needed:** Change `(sexp[1..-1] || []).each` to iterate over `sexp[1]` directly: `(sexp[1] || []).each`.

**`lib/auto_doc/analyzer/source_parser.rb:139-152`** — `extract_name` doesn't handle `[:const_ref, [:@const, "Name", [line, col]]]` which is what Ripper emits for simple class/module names at certain nesting levels. The method only checks for `:@const`, `:@ident`, and `:const_path_ref` node types, but `:const_ref` wraps the actual constant reference.

**Fix needed:** Add `when :const_ref` case in `extract_name` that unwraps to the inner `:@const` node.

---

## Implementation Plan

### Phase 1.0 — Fix Existing Bugs (blocking)

| Step | File(s) | Change |
|------|---------|--------|
| 1.0.1 | `auto-doc.gemspec` | Add `spec.add_dependency "thor", "~> 1.0"` |
| 1.0.2 | `lib/auto_doc/analyzer/source_parser.rb` | Fix `:program` handler: `sexp[1..-1]` → `Array(sexp[1])` |
| 1.0.3 | `lib/auto_doc/analyzer/source_parser.rb` | Add `:const_ref` case in `extract_name` |
| 1.0.4 | `lib/auto_doc/reporter/audit_reporter.rb` | Fix `generate` to accept `Hash<String, Hash>` format from CLI |
| 1.0.5 | `lib/auto_doc/cli.rb` | Add `require "fileutils"` at top (instead of lazy `ensure_dependencies_loaded`) |
| — | — | **Verify:** `bundle exec rspec` passes all 18+ examples |

### Phase 1.1 — Add Missing Specs

| Step | File(s) | Description |
|------|---------|-------------|
| 1.1.1 | `spec/auto_doc_spec.rb` | Test that `AutoDoc::VERSION` is defined, all submodules load |
| 1.1.2 | `spec/auto_doc/config_spec.rb` | Test YAML loading, defaults, deep merge, CLI overrides, directory walk |
| 1.1.3 | `spec/auto_doc/analyzer/yard_reader_spec.rb` | Test doc comment extraction: class/module/method, multi-line comments, no-comment edge case |
| 1.1.4 | `spec/auto_doc/generator/agents_md_generator_spec.rb` | Test AGENTS.md output: header, table formats, empty data, write-to-file |
| 1.1.5 | `spec/auto_doc/generator/diagram_generator_spec.rb` | Test Mermaid output: nodes, edges, empty graph, write-to-file |
| 1.1.6 | `spec/auto_doc/reporter/audit_reporter_spec.rb` | Test generate, format_text, format_json, threshold logic |
| 1.1.7 | `spec/auto_doc/reporter/completeness_checker_spec.rb` | Test coverage calculation, documented/undocumented counting |
| 1.1.8 | `spec/auto_doc/utils/file_tree_builder_spec.rb` | Test tree output formatting, exclude patterns, empty dir, nested dirs |
| 1.1.9 | `spec/auto_doc/utils/yaml_config_loader_spec.rb` | Test load, missing file, empty file, invalid YAML, symbol key conversion |
| 1.1.10 | `spec/auto_doc/cli_spec.rb` | Test `init`, `generate`, `audit`, `diff`, `version`, `orphans` subcommands |
| — | — | **Verify:** `bundle exec rspec` shows ≥70 examples, all green |

### Phase 1.2 — Add Missing CLI Subcommand

| Step | File(s) | Description |
|------|---------|-------------|
| 1.2.1 | `lib/auto_doc/cli.rb` | Implement `orphans` subcommand: find `.rb` files with zero import edges and zero doc references |
| 1.2.2 | `spec/auto_doc/cli_spec.rb` | Add `orphans` test cases |
| — | — | **Verify:** `auto-doc orphans test_fixtures/sample_ruby_project` lists orphan files |

### Phase 1.3 — E2E Self-Test Pipeline

| Step | File(s) | Description |
|------|---------|-------------|
| 1.3.1 | `spec/e2e/self_test_spec.rb` | Run full pipeline against self: `generate`, `audit`, `orphans`, `diff` |
| 1.3.2 | `spec/e2e/self_test_spec.rb` | Assert `.autodoc/` directory created with expected files |
| 1.3.3 | `spec/e2e/self_test_spec.rb` | Assert `audit` returns non-zero when coverage < 100% |
| 1.3.4 | `Rakefile` | Add `rake e2e` task |
| — | — | **Verify:** `rake e2e` passes end-to-end |

---

## Verification Checklist

### After Phase 1.0 (Bug Fixes)

```bash
# 1. Confirm thor is declared
grep -q "thor" auto-doc.gemspec && echo "thor declared" || echo "MISSING"

# 2. Specs pass fully
bundle exec rspec && echo "ALL SPECS PASS" || echo "SPEC FAILURES"

# 3. Audit runs without crash
ruby -I lib exe/auto-doc audit fixtures/sample_ruby_project && echo "AUDIT OK" || echo "AUDIT FAILED"

# 4. Generate runs without crash
ruby -I lib exe/auto-doc generate fixtures/sample_ruby_project && echo "GENERATE OK" || echo "GENERATE FAILED"

# 5. Init creates config
ruby -I lib exe/auto-doc init /tmp/autodoc-test && echo "INIT OK" || echo "INIT FAILED"
```

### After Phase 1.1 (Spec Coverage)

```bash
# All 13 spec modules present
for f in cli config analyzer/source_parser analyzer/import_extractor analyzer/yard_reader \
         generator/agents_md_generator generator/readme_generator generator/diagram_generator \
         reporter/audit_reporter reporter/completeness_checker \
         utils/file_tree_builder utils/yaml_config_loader auto_doc; do
  [ -f "spec/auto_doc/${f}_spec.rb" ] && echo "✅ $f" || echo "❌ $f"
done

# All specs pass
bundle exec rspec --format progress && echo "ALL PASS" || echo "FAILURES"
```

### After Phase 1.2 (Orphans Command)

```bash
# Orphans command works
ruby -I lib exe/auto-doc orphans test_fixtures/sample_ruby_project

# Should show files with no imports and no doc references
```

### After Phase 1.3 (E2E Self-Test)

```bash
# Full pipeline validates itself
bundle exec rake e2e

# Manual: generate docs, audit, check pass/fail
ruby -I lib exe/auto-doc generate . && \
ruby -I lib exe/auto-doc audit . && \
echo "E2E OK" || echo "E2E FAILED"
```

---

## Phase 2 — New Features (Post-MVP)

### 2.1 `.docs` Output Directory Convention

Allow `.docs/` as an alternative to `.autodoc/` for repos that prefer a more visible output dir.

**Files to change:**
| File | Change |
|------|--------|
| `auto-doc.gemspec` | No change needed |
| `lib/auto_doc/config.rb` | Add `output_directory` option defaulting to `.autodoc`; allow override via `output.directory` config key (already partially supported) |
| `lib/auto_doc/cli.rb` | Add `--output-dir` CLI flag |
| `spec/auto_doc/cli_spec.rb` | Test `--output-dir flag` |
| `spec/auto_doc/config_spec.rb` | Test `output.directory` config reading |

**Test:**
```bash
ruby -I lib exe/auto-doc generate --output-dir .docs fixtures/sample_ruby_project
[ -d "fixtures/sample_ruby_project/.docs" ] && echo "✅" || echo "❌"
```

### 2.2 Web Server / API Endpoints (Sinatra or Rack)

Add a lightweight web server that serves generated docs locally.

**New files:**
| File | Purpose |
|------|---------|
| `lib/auto_doc/server.rb` | Sinatra/Rack app: GET `/modules`, GET `/modules/:name`, GET `/report.json` |
| `templates/server_index.erb` | HTML index page listing documented modules |
| `spec/auto_doc/server_spec.rb` | Tests for server endpoints |

**Files to change:**
| File | Change |
|------|--------|
| `auto-doc.gemspec` | Add `spec.add_dependency "sinatra", "~> 4.0"` |
| `lib/auto_doc/cli.rb` | Add `serve [PATH]` subcommand (starts Sinatra on port 4567) |
| `lib/auto_doc.rb` | Add `require_relative "auto_doc/server"` |

**Test:**
```bash
ruby -I lib exe/auto-doc serve fixtures/sample_ruby_project &
curl http://localhost:4567/modules/app
curl http://localhost:4567/report.json
kill %1
```

### 2.3 Plan-Driven Self-Verification

Add a `verify` command that: generates docs → runs audit → reports pass/fail in a single step.

**Files to change:**
| File | Change |
|------|--------|
| `lib/auto_doc/cli.rb` | Add `verify [PATH]` subcommand that chains generate + audit |
| `lib/auto_doc/cli.rb` | Add `--ci` flag: exit 0 on pass, exit 1 on fail |
| `spec/auto_doc/cli_spec.rb` | Test `verify` subcommand |
| `spec/e2e/self_test_spec.rb` | Add `verify` to the self-test pipeline |

**Test:**
```bash
ruby -I lib exe/auto-doc verify fixtures/sample_ruby_project --threshold 50
echo $?  # Should be 0 if coverage >= 50%
```

---

## File-by-File Change Summary (All Phases)

```
lib/
├── auto_doc.rb                                    # Add server require (P2)
├── auto_doc/
│   ├── cli.rb                                     # FIX audit analyses format, ADD orphans, ADD serve, ADD verify
│   ├── config.rb                                  # Add :output_directory support (P2, partial now)
│   ├── server.rb                                  # NEW (P2)
│   ├── analyzer/
│   │   ├── source_parser.rb                       # FIX program handler, FIX extract_name :const_ref
│   │   ├── import_extractor.rb                    # No changes needed
│   │   └── yard_reader.rb                         # No changes needed
│   ├── generator/
│   │   ├── agents_md_generator.rb                 # No changes needed
│   │   ├── readme_generator.rb                    # No changes needed
│   │   └── diagram_generator.rb                   # No changes needed
│   ├── reporter/
│   │   ├── audit_reporter.rb                      # FIX generate to accept CLI analyses hash format
│   │   └── completeness_checker.rb                # No changes needed
│   └── utils/
│       ├── file_tree_builder.rb                   # No changes needed
│       └── yaml_config_loader.rb                  # No changes needed

spec/
├── spec_helper.rb                                 # No changes needed
├── auto_doc_spec.rb                               # NEW
├── auto_doc/
│   ├── cli_spec.rb                                # NEW
│   ├── config_spec.rb                             # NEW
│   ├── analyzer/
│   │   ├── source_parser_spec.rb                  # Has tests, may need additions
│   │   ├── import_extractor_spec.rb               # Has tests, may need additions
│   │   └── yard_reader_spec.rb                    # NEW
│   ├── generator/
│   │   ├── agents_md_generator_spec.rb            # NEW
│   │   ├── readme_generator_spec.rb               # Has tests
│   │   └── diagram_generator_spec.rb              # NEW
│   ├── reporter/
│   │   ├── audit_reporter_spec.rb                 # NEW
│   │   └── completeness_checker_spec.rb           # NEW
│   └── utils/
│       ├── file_tree_builder_spec.rb              # NEW
│       └── yaml_config_loader_spec.rb             # NEW
├── e2e/self_test_spec.rb                          # NEW

templates/
└── server_index.erb                               # NEW (P2)

auto-doc.gemspec                                   # ADD thor dependency, ADD sinatra (P2)
```

---

## Dependency Checklist

| Gem | Phase | Status | Notes |
|-----|-------|--------|-------|
| `thor` | 1.0 | ❌ Missing | Must be added to gemspec; used by CLI |
| `rspec` | 1.0 | ✅ Present | Already in Gemfile group :development |
| `sinatra` | 2.0 | ❌ Missing | Web server feature; optional dependency |
| `rack` | 2.0 | ❌ Missing | For Sinatra or bare Rack app |
| `yard` | Deferred | ❌ Missing | Full YARD parsing (Phase 3) |

---

## Output Files Generated (Current)

```
.autodoc/
├── <module_name>/
│   └── AGENTS.md            # ✅ Generated per module root
├── README.md                # ✅ Generated at project level
├── diagrams/
│   └── deps.mmd             # ✅ Generated DAG
└── report.json              # ✅ Written by audit command
```

**Note:** Output depends on `config.output.directory` (default: `.autodoc`). Currently hardcoded in CLI — should use `config.output_dir` throughout.

---

## Commands to Run After Each Phase

### After Phase 1.0 (Bug Fixes)
```bash
bundle install                          # Now pulls in thor
bundle exec rspec                       # 18+ examples, 0 failures
ruby -I lib exe/auto-doc version        # auto-doc 0.1.0
ruby -I lib exe/auto-doc audit fixtures/sample_ruby_project   # No crash
ruby -I lib exe/auto-doc generate fixtures/sample_ruby_project # Creates .autodoc/
```

### After Phase 1.1 (Spec Coverage)
```bash
bundle exec rspec --format progress     # 70+ examples, 0 failures
```

### After Phase 1.2 (Orphans Command)
```bash
ruby -I lib exe/auto-doc orphans fixtures/sample_ruby_project
```

### After Phase 1.3 (E2E Self-Test)
```bash
bundle exec rake e2e                    # Full pipeline self-validation
```

### After Phase 2 (New Features)
```bash
ruby -I lib exe/auto-doc serve fixtures/sample_ruby_project  # Starts server
ruby -I lib exe/auto-doc verify fixtures/sample_ruby_project  # generate + audit in one
ruby -I lib exe/auto-doc generate --output-dir .docs fixtures/sample_ruby_project
```
