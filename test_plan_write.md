# Project Plan: 2026-07-14-auto-doc-ruby-gem

## Hypotheses Considered

### Hypothesis 1: Minimal Fixes — Fix Only What Breaks
Run specs, identify failures one at a time, and fix them surgically. Risk: reactive approach may miss deeply interconnected issues (e.g., fixture accessibility + missing module definitions that cascade).

### Hypothesis 2: Structural Audit + Incremental Fix
Audit all 13 spec files for correctness issues upfront (missing requires, wrong module references, nonexistent fixtures, syntax errors). Fix the structural problems first, then run. Fix any remaining source-code bugs that surface. This is the most efficient path: catch the obvious issues before runtime.

### Hypothesis 3: Fixture Infrastructure First
Rewrite the E2E spec to avoid `Fixtures.config` by using direct file path resolution, ensure all fixture files are accessible, then fix spec bugs. Risk: over-engineers the fix for what might be a single typo.

### Selected: Hypothesis 2
The structural audit catches the obvious pre-runtime issues (Rakefile missing require, E2E spec referencing nonexistent `Fixtures` module). Then running specs reveals any deeper bugs in source code or spec logic that need fixing. This is the highest-leverage approach -- fix what is known-broken before discovering what else is broken.

---

## Milestone 1: Fix Infrastructure and Compilation Errors

**Intent:** Fix all issues that prevent specs from even loading: missing requires, nonexistent module references, and the Rakefile. After this milestone, `bundle exec rspec` should at least attempt to run all specs.

### Implementation

#### Backend Work Items
- [ ] **Rakefile**: Add `require "rspec/core/rake_task"` before line 5 that uses `RSpec::Core::RakeTask.new(:test)`
- [ ] **spec/e2e/self_test_spec.rb**: Replace `Fixtures.config["sample_ruby_project"]` with `File.expand_path("../../fixtures/sample_ruby_project", __dir__)` -- the `Fixtures` module does not exist
- [ ] **spec/e2e/self_test_spec.rb**: Fix the `let(:project_dir)` block to use the same path resolution as `before(:all)` variables instead of referencing `Fixtures.config`

#### Frontend Work Items
- N/A

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | `bundle exec rspec spec/e2e/self_test_spec.rb` | Spec loads without NameError |
| Integration | `bundle exec rspec` | All spec files are discovered and loaded; zero load-time errors |

### Verification Criteria
- [ ] `bundle exec rspec --dry-run` shows all 70+ examples are discovered
- [ ] No `NameError` or `LoadError` at spec load time
- [ ] `bundle exec rake test` works without errors (Rakefile RSpec require fixed)

---

## Milestone 2: Fix Failing Spec Logic and Source Bugs

**Intent:** Run the full test suite after Milestone 1 and fix any remaining failures. This could include: spec assertions that don't match actual source behavior, fixture file parsing bugs in analyzers, or configuration logic mismatches. Each failure gets diagnosed and fixed.

### Implementation

#### Backend Work Items
- [ ] **lib/auto_doc/reporter/audit_reporter.rb** or **lib/auto_doc/utils/yaml_config_loader.rb** or **lib/auto_doc/config.rb**: Fix any logic bugs that cause spec failures -- determined after running specs from Milestone 1
- [ ] **spec/auto_doc/config_spec.rb** or **spec/auto_doc/reporter/audit_reporter_spec.rb** or **spec/auto_doc/reporter/completeness_checker_spec.rb**: Fix any spec bugs (wrong expected values, missing mocks, assumption mismatches)
- [ ] **spec/auto_doc/analyzer/source_parser_spec.rb** or **spec/auto_doc/analyzer/yard_reader_spec.rb**: Fix any spec bugs related to fixture file parsing
- [ ] **spec/auto_doc/generator/readme_generator_spec.rb** or **spec/auto-doc/generator/agents_md_generator_spec.rb** or **spec/auto_doc/generator/diagram_generator_spec.rb**: Fix spec bugs in generator specs
- [ ] **spec/auto_doc/cli_spec.rb**: Fix CLI spec failures (output matching, SystemExit handling)
- [ ] **spec/auto_doc/utils/file_tree_builder_spec.rb** or **spec/auto_doc/utils/yaml_config_loader_spec.rb**: Fix util spec failures

#### Frontend Work Items
- N/A

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | Each fixed spec file individually | All examples in the file pass |
| Integration | `bundle exec rspec` (full suite) | All 70+ examples pass (0 failures) |

### Verification Criteria
- [ ] `bundle exec rspec` output shows `0 failures`
- [ ] All 70+ examples are green
- [ ] `ruby -I lib exe/auto-doc audit --threshold 0 fixtures/sample_ruby_project` completes and outputs "AUDIT REPORT"
- [ ] `ruby -I lib exe/auto-doc generate fixtures/sample_ruby_project` creates `.autodoc/` directory with README.md, diagrams/deps.mmd, and per-module AGENTS.md files
