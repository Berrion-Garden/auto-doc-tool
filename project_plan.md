# Project Plan: auto-doc-ruby-gem

## Hypotheses Considered

### Hypothesis 1: Bugfix-First, Then Spec Coverage
Fix the 3 known blocking bugs (source_parser `:program` handler, audit reporter format mismatch, missing thor dependency) before adding any new code. Then add 9 missing spec files layer-by-layer, then run E2E verification. Safest: ensures the foundation is sound before building on it.

### Hypothesis 2: Spec-First, Fix What Breaks
Write all 9 missing spec files immediately. The failing specs will surface exactly which runtime bugs remain. More aggressive but risks cascading failures from the same root bug making test output noisy.

### Hypothesis 3: Full Vertical Slice (end-to-end path first)
Write an E2E smoke test first, then trace failures back to their source. Good for integration-level confidence but wastes time on red-green cycles that unit-level debugging would solve faster.

### Selected: Hypothesis 1
The codebase already runs end-to-end (`orphans`, `diff`, `serve` all exist and function). The 3 known bugs (source_parser, audit_reporter, thor dependency) are isolated and each has a concrete 1-3 line fix. Fixing them first eliminates false-negatives that would poison any spec-writing effort. After fixes, the layer-by-layer spec approach produces clean green output at each milestone boundary.

**Key assumption:** The 3 bugs documented in COMPLETION_PLAN.md are the only blocking bugs. No hidden runtime issues exist in the untested generator/reporter/util modules.

---

## Milestone 1: Fix Blocking Bugs

**Intent:** Fix the 3 known runtime bugs that would cause spec failures regardless of test quality. This unlocks clean spec development in later milestones.

### Implementation

#### Backend Work Items
- [ ] `auto-doc.gemspec`: Add `spec.add_dependency "thor", "~> 1.0"` (currently missing from gemspec; thor is listed in Gemfile but not gemspec, causing potential load failures)
- [ ] `lib/auto_doc/analyzer/source_parser.rb` line 66-68: Fix `:program` handler — change `Array(sexp[1..-1] || [])` to `Array(sexp[1])`. The `[1..-1]` slice on `[:program, [stmt1, stmt2]]` yields `[[stmt1, stmt2]]`, wrapping the statements array inside another array. The loop iterates once with a single `[[stmt1, stmt2]]` child that fails the `sexp.length >= 2` guard in `walk_sexp` and is silently skipped, causing class/module definitions to be missed.
- [ ] `lib/auto_doc/analyzer/source_parser.rb`: Verify `:const_ref` case in `extract_name` already works (line 145-147). Ripper emits `[:const_ref, [:@const, "Name", [line, col]]]` for simple class/module names at certain nesting levels. This handler unwraps to the inner `:@const` node — confirm it resolves correctly against fixture files.
- [ ] `lib/auto_doc/reporter/audit_reporter.rb`: Verify `generate` method already accepts Hash format from CLI (lines 38-50 show both `Hash<String,Hash>` and `Array<Hash>` are handled). Confirm the `TypeError: no implicit conversion of Symbol into Integer` documented in COMPLETION_PLAN.md no longer repros by running audit against fixtures.

#### Frontend Work Items
- N/A (backend-only gem)

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | SourceParser.parse_file on user.rb fixture | Returns User class definition with type: :class, positive :line |
| Unit | SourceParser.parse_file on math_utils.rb fixture | Returns MathUtils module definition |
| Integration | auto-doc audit --threshold 0 on sample_ruby_project | Completes without TypeError, exits 0 |
| Integration | auto-doc generate on sample_ruby_project | Creates .autodoc/ without crash |

### Verification Criteria
- [ ] `bundle exec rspec` passes all 18+ existing examples with 0 failures
- [ ] `ruby -I lib exe/auto-doc generate fixtures/sample_ruby_project` creates `.autodoc/` with AGENTS.md, README.md, diagrams/deps.mmd
- [ ] `ruby -I lib exe/auto-doc audit --threshold 0 fixtures/sample_ruby_project` exits 0 and produces report.json

---

## Milestone 2: Utility and Config Specs

**Intent:** Add unit tests for the shared infrastructure layer — Config loading, YAML parsing, and file tree building. These have zero runtime dependencies on other modules and can be tested in complete isolation.

### Implementation

#### Backend Work Items
- [ ] `spec/auto_doc/config_spec.rb`: Create — test YAML loading from `.autodoc.yml`, default values, deep-merge with CLI overrides, directory-walk config discovery, missing file fallback
- [ ] `spec/auto_doc/utils/yaml_config_loader_spec.rb`: Create — test load of valid YAML, missing file returns empty hash, empty file, invalid YAML raises, symbol key conversion
- [ ] `spec/auto_doc/utils/file_tree_builder_spec.rb`: Create — test builds tree output for a directory, handles exclude patterns, empty directory, deeply nested structure

#### Frontend Work Items
- N/A

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | Config.load returns defaults when no .autodoc.yml exists | Hash matching DEFAULTS |
| Unit | Config.load deep-merges YAML file values over defaults | File values override, missing keys fall back |
| Unit | Config.load applies CLI overrides on top of file config | CLI values win |
| Unit | YamlConfigLoader.load with valid YAML | Parsed Hash |
| Unit | YamlConfigLoader.load with missing file | Empty Hash |
| Unit | YamlConfigLoader.load with invalid YAML | Raises Psych::SyntaxError |
| Unit | FileTreeBuilder.build with nested dirs | Correct indented tree text |
| Unit | FileTreeBuilder.build excludes patterns | Excluded dirs not in output |

### Verification Criteria
- [ ] `bundle exec rspec spec/auto_doc/config_spec.rb spec/auto_doc/utils/` passes green
- [ ] At least 10 new examples added to the suite

---

## Milestone 3: Reporter and Generator Specs

**Intent:** Add unit tests for the auditing layer (CompletenessChecker, AuditReporter) and the two untested generators (AgentsMdGenerator, DiagramGenerator). ReadmeGenerator already has passing specs (9 examples).

### Implementation

#### Backend Work Items
- [ ] `spec/auto_doc/reporter/completeness_checker_spec.rb`: Create — test coverage calculation with all-documented, all-undocumented, mixed, empty analyses; threshold logic; handling of both Hash and Array analysis formats
- [ ] `spec/auto_doc/reporter/audit_reporter_spec.rb`: Create — test generate() with Hash-format analyses from CLI and Array-format; test format_text output contains coverage percentage and PASS/FAIL; test format_json produces valid JSON with expected keys; test pass/fail threshold logic
- [ ] `spec/auto_doc/generator/agents_md_generator_spec.rb`: Create — test generated AGENTS.md includes module name, file tree, dependencies table, public API surface table; test output with empty data produces valid skeleton with "No external dependencies" and "No public symbols" rows; test file writing to output path
- [ ] `spec/auto_doc/generator/diagram_generator_spec.rb`: Create — test generated Mermaid output contains `graph TB`, node declarations, edge declarations with `-->|type|` syntax; test empty graph produces valid skeleton; test file writing to output path

#### Frontend Work Items
- N/A

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | CompletenessChecker.check with all symbols documented | coverage_pct: 100.0, undocumented: [] |
| Unit | CompletenessChecker.check with no symbols | coverage_pct: 100.0, total: 0 |
| Unit | CompletenessChecker.check with mixed docs | Correct documented/undocumented counts |
| Unit | AuditReporter.generate with CLI Hash format | Returns report Hash with :overall_coverage, :total_symbols, :documented_symbols, :passed keys |
| Unit | AuditReporter.generate respects min_coverage threshold | :passed is false when coverage < threshold |
| Unit | AuditReporter.format_text produces correct output | String containing coverage % and PASS/FAIL |
| Unit | AuditReporter.format_json produces valid JSON | Parseable JSON with correct keys |
| Unit | AgentsMdGenerator.generate produces valid Markdown | Content contains module name and table headers |
| Unit | AgentsMdGenerator.generate with empty data | "No external dependencies detected" and "No public symbols found" rows present |
| Unit | DiagramGenerator.generate produces Mermaid graph TB | Output starts with `graph TB` |
| Unit | DiagramGenerator.generate produces nodes and edges | Node IDs, labels, and `-->|type|` syntax present |

### Verification Criteria
- [ ] `bundle exec rspec spec/auto_doc/reporter/ spec/auto_doc/generator/` passes green
- [ ] At least 12 new examples added to the suite

---

## Milestone 4: CLI and Server Specs + Final Verification

**Intent:** Add integration tests for the Thor-based CLI subcommands and the Sinatra server routes. Run complete E2E pipeline against the gem's own source. Top layer — exercises all modules below.

### Implementation

#### Backend Work Items
- [ ] `spec/auto_doc/cli_spec.rb`: Create — test `init` creates `.autodoc.yml`; test `generate` on sample project creates `.autodoc/` output; test `audit --threshold 0` passes; test `version` prints version string; test `diff` requires SINCE argument; test `orphans` lists orphan files; test `serve` starts and responds on configured port
- [ ] `spec/auto_doc/server_spec.rb`: Create — test GET `/` returns HTML with module list; test GET `/:module` returns AGENTS.md content; test GET `/api/stats` returns JSON; test GET `/api/search?q=term` returns JSON results; test 404 for nonexistent module
- [ ] Verify full pipeline: `bundle exec rspec` passes all specs green

#### Frontend Work Items
- N/A

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Integration | CLI `init` creates config file on temp dir | `.autodoc.yml` exists with correct content |
| Integration | CLI `generate` on sample_ruby_project | `.autodoc/` created with README.md, AGENTS.md files |
| Integration | CLI `audit --threshold 0` passes | Exit 0, report.json created |
| Integration | CLI `version` prints version | STDOUT contains "auto-doc 0.1.0" |
| Integration | CLI `diff` without SINCE arg | Prints error and exits 1 |
| Integration | CLI `orphans` on sample project | Lists files with no imports and no doc references |
| Integration | Server GET `/` returns 200 | HTML with module list |
| Integration | Server GET `/api/stats` returns JSON | Parseable JSON |
| Integration | Server GET `/api/search?q=term` returns results | JSON with results array |
| E2E | `ruby -I lib exe/auto-doc e2e .` | All steps pass, exit 0 |

### Verification Criteria
- [ ] `bundle exec rspec --format progress` shows zero failures
- [ ] Total example count >= 55
- [ ] `ruby -I lib exe/auto-doc e2e .` exits 0
- [ ] `.autodoc/` contains README.md, AGENTS.md per module root, diagrams/deps.mmd, report.json
