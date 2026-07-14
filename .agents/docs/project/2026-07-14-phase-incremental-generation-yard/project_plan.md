# Project Plan: 2026-07-14-phase-incremental-generation-yard

## Hypotheses Considered

### Hypothesis 1: TimestampTracker + analyze_project filtering
Create a `TimestampTracker` utility that reads/writes `.autodoc/generation_manifest.json` storing per-file mtimes. In `perform_generate`, when `--incremental` is passed, filter `analyze_project`'s file list to only changed files. Generators process only the analyzed subset, producing outputs only for changed module roots. Save the manifest at the end. This keeps the change surface minimal — the analysis pipeline is unchanged, only its input list is filtered.

### Hypothesis 2: Directory-level staleness (coarser grain)
Track staleness at the module-root directory level. If no files in a module root changed, skip the entire root's generation entirely.

### Hypothesis 3: Selective analysis with full regeneration
Cache analysis results from the previous run. When `--incremental`, only re-analyze changed files but merge cached results for unchanged files to produce a complete output.

### Selected: Hypothesis 1
Hypothesis 1 is the strongest because it is the simplest implementation that meets all requirements. The `TimestampTracker` is a focused, testable, single-responsibility unit. The `analyze_project` method already iterates over a file list — filtering that list before the loop requires zero changes to the analysis logic itself. The manifest file lives in `.autodoc/` (the same output directory already in use), keeping related artifacts together. It is also the approach most consistent with the existing codebase conventions (utility classes in `utils/`, file-level i/o patterns matching `YamlConfigLoader`).

---

## Milestone 1: Timestamp Tracker (staleness detection utility)

**Intent:** Create the core utility that detects which files have changed since the last generation run. This is the foundation for incremental generation — without it, the `--incremental` flag cannot function.

### Implementation

#### Backend Work Items
- [ ] `lib/auto_doc/utils/timestamp_tracker.rb` — NEW: Create `AutoDoc::Utils::TimestampTracker` class with:
  - `MANIFEST_PATH = ".autodoc/generation_manifest.json"` constant
  - `self.stale_files(project_dir)` — returns array of file paths that have changed (or are new) since last manifest. Returns ALL files if no manifest exists (first run falls back to full generation).
  - `self.save_manifest(project_dir, file_list)` — writes manifest JSON with current mtimes for each file. Creates `.autodoc/` if it doesn't exist. Handles file permission errors gracefully (returns false, doesn't crash generation).
  - Manifest format: `{ "generated_at": "ISO8601", "files": { "relative/path.rb": "mtime_epoch_int", ... } }`
- [ ] `lib/auto_doc.rb` — Add `require_relative "auto_doc/utils/timestamp_tracker"` in the utils section (after file_tree_builder)

#### Frontend Work Items
- [ ] N/A

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | `spec/auto_doc/utils/timestamp_tracker_spec.rb` — NEW: Test stale_files returns all files when no manifest exists | Returns full file list |
| Unit | stale_files with manifest where one file's mtime changed | Returns only the changed file |
| Unit | stale_files with manifest where no files changed | Returns empty array |
| Unit | stale_files with new file not in manifest | Returns the new file |
| Unit | save_manifest creates .autodoc/ and writes correct JSON | Manifest file exists with correct structure |
| Unit | save_manifest updates existing manifest | Timestamp and file entries are updated |

### Verification Criteria
- [ ] `bundle exec rspec spec/auto_doc/utils/timestamp_tracker_spec.rb` — all tests pass
- [ ] Manual: delete `.autodoc/generation_manifest.json`, call `TimestampTracker.stale_files(dir)` — returns all Ruby files
- [ ] Manual: call `TimestampTracker.save_manifest(dir, files)`, then immediately call `stale_files(dir)` — returns empty array

---

## Milestone 2: Wire Incremental Flag into CLI

**Intent:** Replace the `? true : true` no-op on line 414 with actual incremental logic. When `--incremental` is passed, only analyze changed files. When not passed (default), do full regeneration (current behavior). Update the manifest at the end of each generation run.

### Implementation

#### Backend Work Items
- [ ] `lib/auto_doc/cli.rb` — Modify `perform_generate` method:
  - Before `analyze_project`, check `options[:incremental]`. If true, call `TimestampTracker.stale_files(target_dir)` and pass the filtered list to a modified `analyze_project` (or pass it as an optional parameter).
  - After all generation completes, call `TimestampTracker.save_manifest(target_dir, ruby_files_list)` where `ruby_files_list` is the full file list (not just stale ones — we want the manifest to track everything so next run's staleness check is accurate).
  - Replace line 414's `generate_dag = options[:incremental] ? true : true` with `generate_dag = config.generate_dag?` (use the config value, which defaults to true). DAG generation should still happen in incremental mode since it operates on whatever analyses are available.
  - Remove `require "shellwords"` on line 6 — it is used in `diff` method on line 58 (`Shellwords.escape`) so it must STAY. (Verify: it IS used, do not remove.)
  - Add `require "auto_doc/utils/timestamp_tracker"` is already covered by `lib/auto_doc.rb` — no additional require needed in CLI.

- [ ] `lib/auto_doc/cli.rb` — Modify `analyze_project` to accept an optional `file_list` parameter:
  - Signature: `def analyze_project(base_dir, config, file_list = nil)`
  - When `file_list` is provided, use it instead of `Dir.glob(...)`. Otherwise, use current glob behavior.
  - This keeps the method backward-compatible (audit, orphans, verify all use the default behavior).

#### Frontend Work Items
- [ ] N/A

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Integration | `auto-doc generate --incremental fixtures/sample_ruby_project` — first run | Full generation occurs, manifest created |
| Integration | Same command — second run immediately after | No files changed, output says "up to date" or generation is skipped/significantly faster |
| Integration | Touch one file, run `--incremental` again | Only the changed directory's output is regenerated |
| Integration | `auto-doc generate fixtures/sample_ruby_project` (no --incremental) | Always full generation regardless of manifest |
| Unit | `analyze_project` with explicit file_list | Only given files are analyzed |

### Verification Criteria
- [ ] `ruby -I lib exe/auto-doc help generate` — shows `--incremental` flag with description
- [ ] `ruby -I lib exe/auto-doc generate --incremental fixtures/sample_ruby_project` — runs successfully, creates manifest
- [ ] Second identical run — completes faster (no re-analysis of unchanged files), no errors
- [ ] `ruby -I lib exe/auto-doc generate fixtures/sample_ruby_project` (no flag) — still does full generation
- [ ] `bundle exec rspec` — all existing 121+ tests still pass

---

## Milestone 3: YARD Gem Integration

**Intent:** Add optional YARD structured parsing to `YardReader`, falling back to regex when YARD is not available. Add new fields to the Comment struct for structured tag data. This enriches the documentation extraction without breaking existing behavior.

### Implementation

#### Backend Work Items
- [ ] `auto-doc.gemspec` — Add `spec.add_dependency "yard", "~> 0.9"` as a runtime dependency (not optional — the gem is lightweight and widely available)
- [ ] `lib/auto_doc/analyzer/yard_reader.rb` — Modify Comment struct to add new fields:
  - `params` (Array of `{ name:, types:, description: }` hashes)
  - `return_type` (String or nil)
  - `yield_type` (String or nil)
  - `tags` (Array of `{ tag_name:, text: }` hashes for all unrecognized @tags)
  - Update `to_h` to include these new fields
  - Add `YARD_AVAILABLE = defined?(YARD)` constant
- [ ] `lib/auto_doc/analyzer/yard_reader.rb` — Add YARD parsing path in `extract_doc_comments`:
  - After collecting comment block and identifying target, if `YARD_AVAILABLE`, parse the raw comment text with YARD
  - Extract `@param`, `@return`, `@yield`, and other `@tag` entries
  - If YARD is not available, populate new fields with defaults (`params: [], return_type: nil, yield_type: nil, tags: []`)
  - Keep existing regex-based extraction as the primary path for `target_name`, `target_type`, `text`, `line`, `has_summary?`
  - The YARD path is additive — it enriches the Comment struct with tag data without replacing the regex approach

#### Frontend Work Items
- [ ] N/A

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | Existing regex extraction tests still pass | All 7 existing tests pass |
| Unit | New test: Comment struct includes params/return_type/yield_type/tags fields | Fields present with correct defaults when YARD unavailable |
| Unit | New test: YARD-style `@param` tag extraction from a fixture file with full YARD doc blocks | params array populated correctly |
| Unit | New test: YARD-style `@return` tag extraction | return_type string populated |
| Unit | New test: Comment with no @tags | params is empty array, return_type is nil |
| Unit | Edge case: file with only `#` comments (no @tags) | Works same as before, new fields have defaults |

### Verification Criteria
- [ ] `bundle exec rspec spec/auto_doc/analyzer/yard_reader_spec.rb` — all tests pass, including new YARD tests
- [ ] `bundle exec rspec` — all existing 121+ tests still pass (Comment struct change doesn't break CLI, audit, etc.)
- [ ] Manual: `ruby -e "require 'auto_doc'; puts AutoDoc::Analyzer::YardReader.extract('fixtures/sample_ruby_project/app/models/user.rb').inspect"` — new fields visible in output

---

## Milestone 4: Version Bump, Gemspec Polish, and Edge Case Cleanup

**Intent:** Bump to 0.2.0, add gemspec metadata for rubygems.org compatibility, and clean up accidental artifacts from development.

### Implementation

#### Backend Work Items
- [ ] `lib/auto_doc/version.rb` — Change `VERSION = "0.1.0"` to `VERSION = "0.2.0"`
- [ ] `auto-doc.gemspec` — Update/add metadata fields:
  - `spec.homepage = "https://github.com/pik-ai/auto-doc"`
  - `spec.metadata["source_code_uri"] = "https://github.com/pik-ai/auto-doc"`
  - `spec.metadata["changelog_uri"] = "https://github.com/pik-ai/auto-doc/blob/main/CHANGELOG.md"`
  - Remove `spec.metadata["allowed_push_host"] = ""` (empty string blocks `gem push`; remove the line)
- [ ] Clean up `--help/` directory — `rm -rf --help/` (accidentally created by `auto-doc generate --help` interpreting `--help` as a path)
- [ ] Clean up `test_fixtures/sample_ruby_project/{app` — `rm -rf test_fixtures/sample_ruby_project/{app` (brace expansion artifact)
- [ ] Gitignore the `--help/` pattern to prevent recurrence — add `--help/` to `.gitignore`

#### Frontend Work Items
- [ ] N/A

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | `ruby -I lib exe/auto-doc version` | Outputs `auto-doc 0.2.0` |
| Unit | `ruby -e "require 'auto-doc'; puts AutoDoc::VERSION"` | Outputs `0.2.0` |
| Integration | `bundle exec rspec` | All tests pass, version-dependent tests updated |

### Verification Criteria
- [ ] `ruby -I lib exe/auto-doc version` shows `0.2.0`
- [ ] `--help/` directory no longer exists
- [ ] `test_fixtures/sample_ruby_project/{app` directory no longer exists
- [ ] `bundle exec rspec` — all tests pass (135+ examples expected after all milestones)
- [ ] `gem build auto-doc.gemspec` — builds without warnings about missing metadata
