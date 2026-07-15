# Project Plan: 2026-07-15-auto-doc-polish-pass

## Hypotheses Considered

### Hypothesis 1: Single-Pass Fix-All
Fix all 9 issues in a single sequential pass: template fixes first, then logic fixes, then version/config bumps, with new tests for behavior-changing fixes (class diagram method format, cross-ref paths). Run full test suite once at the end.

### Hypothesis 2: Template-First, Logic-Second
Group fixes by type: tackle all template/rendering issues (Issues 1, 2, 3) in one milestone, then all logic/path/categorization issues (4-9) in a second milestone. Test after each group.

### Hypothesis 3: Test-Driven for Each Issue
Write a failing spec for each of the 9 issues before fixing, then fix one at a time, running the relevant spec between each. Most disciplined but overly heavy for 9 small fixes.

### Selected: Hypothesis 1
All 9 issues are small, well-scoped, and touch different concerns with no cascading dependencies. Fixing them in a single pass with new tests for the two behavior-changing fixes (Issues 1 and 4) is efficient and safe. The rest are straightforward template/configuration fixes that existing specs will cover. Risk is low since all 376 existing tests act as a regression net.

---

## Milestone 1: Fix All 9 Issues

**Intent:** Apply all 9 fixes across templates, generators, CLI, version, and orchestrator in one coordinated pass. Add new specs for behavior-changing fixes to prevent regression.

### Implementation

#### Issues 1-3: Template Fixes

##### Issue 1: Class diagram method syntax
- [ ] `templates/class_diagram_template.erb`: Change method rendering from raw hash dump `<%= m %>` to proper Mermaid syntax `+<%= m[:name] %>()`. Methods in `class_hierarchy` are hashes like `{name: "find_active", type: :method, line: 0}`, so access `m[:name]` to render `+find_active()`.
- [ ] `lib/auto_doc/generator/class_diagram_generator.rb`: No changes needed — the generator passes through whatever is in the hierarchy. The fix is template-only.

##### Issue 2: Architecture diagram link text
- [ ] `templates/architecture_template.erb` line 53: Change `link[:title]` to `link[:name]` — the orchestrator populates diagram_links with `{name:, path:}` hashes, not `{title:, path:}`.
- [ ] `spec/auto_doc/generator/architecture_generator_spec.rb` line 43: Update test fixture `{ title: "Class Diagram", ... }` to `{ name: "Class Diagram", ... }` to match real data shape. Tests on lines 75-83 that check diagram rendering remain as-is (they test structure, not link text).

##### Issue 3: Index blank table rows
- [ ] `templates/index_template.erb`: No structural change needed — the `if files.any?` / `if symbols.any?` guards already prevent blank rows for empty data. The issue is likely from nil values in individual fields. Add safety: use `f[:name].to_s`, `sym[:name].to_s`, `sym[:type].to_s`, `sym[:file].to_s` to prevent bare `|` cells when optional fields are nil.
- [ ] Alternatively (and more likely the root cause): ensure the template has NO blank lines between ERB tags in table sections. ERB `<% %>` tags that sit on their own line may produce empty markdown lines that render as blank table rows. Review all table sections and ensure ERB tags are tightly coupled to their content lines.

#### Issues 4-6: Logic Fixes

##### Issue 4: Cross-reference path "../" prefix
- [ ] `lib/auto_doc/generator/index_generator.rb` `build_cross_references` method (line 140-169): Add a `root_level` parameter (default `false`). When `root_level: true`, build parent/sibling paths WITHOUT the `../` prefix (e.g., `"models/INDEX.md"` instead of `"../models/INDEX.md"`). When `root_level: false` (subdirectory generation via walk), keep the `../` prefix.
- [ ] `lib/auto_doc/generator/index_generator.rb` `.generate` class method: Accept `root_level: false` parameter and pass it through to `build_cross_references`.
- [ ] `lib/auto_doc/orchestrator.rb` line 204: Pass `root_level: true` when generating the project-level INDEX.md.

##### Issue 5: Duplicate vectors.json at project root
- [ ] `lib/auto_doc/orchestrator.rb` `walk_subdirectories` method (line 491-527): When `output_rel == "."` (i.e., the directory is the module root itself), skip generating `vectors.json`. The project-level `VECTORS.json` is already generated separately at lines 213-216. Only generate per-directory `vectors.json` for actual subdirectories.
- [ ] Implementation: wrap the vectors generation block (lines 522-525) in `unless output_rel == "."`.

##### Issue 6: Agent command PATH support
- [ ] `lib/auto_doc/cli.rb` `agent` method (lines 261-279): Add `method_option :path, type: :string, default: ".", desc: "Project path"` before the `def agent` method. Use `project_dir = File.expand_path(options[:path])` instead of `File.expand_path(".")`. Add a blank line between the `long_desc` block and the `method_option` / `def agent` declaration so Thor parses the option correctly.

#### Issues 7-9: Version, Map, Output

##### Issue 7: Bump version to 1.0.0
- [ ] `lib/auto_doc/version.rb`: Change `VERSION = "0.2.0"` to `VERSION = "1.0.0"`.

##### Issue 8: README.md in map artifacts
- [ ] `lib/auto_doc/generator/map_generator.rb` `classify_file` method (line 110-114): Add explicit early return `return :readme if rel_path.end_with?("README.md")` before the CATEGORIES hash iteration. This ensures README.md is always classified regardless of hash enumeration quirks.
- [ ] NOTE: The existing CATEGORIES hash line 23 already has `readme:` — this change makes the check explicit and ordered-first as the user requests. The spec at `map_generator_spec.rb:67-69` already tests readme categorization and should continue to pass.

##### Issue 9: "./" prefix in walk output messages
- [ ] `lib/auto_doc/orchestrator.rb` `walk_subdirectories` method (line 507): Replace:
  ```ruby
  output_rel = Pathname.new(dir).relative_path_from(Pathname.new(root)).to_s
  ```
  with:
  ```ruby
  raw_rel = Pathname.new(dir).relative_path_from(Pathname.new(root)).to_s
  output_rel = (raw_rel == ".") ? display_name : raw_rel
  ```
  This ensures output messages show `Created .../.docs/lib/INDEX.md` instead of `Created .../.docs/./INDEX.md`.

### Testing

| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit (new) | Class diagram renders methods as `+methodName()` syntax | Template outputs `+find_active()` not raw hash |
| Unit (new) | Class diagram does not include `type:` or `line:` metadata | No `{:name=>` or `:type=>` in output |
| Unit (new) | Architecture diagram links use `:name` key for visible text | Link renders as `[C4 Context Diagram](...)` not `[](...)` |
| Unit (new) | Index template produces no blank `| |` table rows with nil-safe values | All table rows have populated cells or explicit "—" placeholders |
| Unit (new) | Root-level INDEX.md cross-ref paths omit `../` | Parent link is `models/INDEX.md` not `../models/INDEX.md` |
| Unit (new) | Subdirectory INDEX.md cross-ref paths keep `../` | Parent link is `../models/INDEX.md` |
| Unit (new) | Agent CLI accepts `--path` flag | `auto-doc agent --path /tmp/foo "query"` resolves project_dir correctly |
| Unit (existing) | Map generator categorizes README.md | `artifacts[:readme]` includes "README.md" |
| Unit (existing) | All 376 existing specs still pass | `bundle exec rspec` exits 0 |

### Verification Criteria
- [ ] `bundle exec rspec` — all 376+ tests pass (including any new ones added)
- [ ] Class diagram output contains `+methodName()` syntax for methods (verified in new spec)
- [ ] Architecture markdown diagram links have visible text (verified in new spec)
- [ ] INDEX.md tables have no blank `| | |` rows (verified in new spec)
- [ ] Cross-reference paths are correct for both root-level and subdirectory INDEX.md (verified in new specs)
- [ ] `bundle exec ruby -e "require 'auto_doc'; puts AutoDoc::VERSION"` outputs `1.0.0`
- [ ] CLI `agent` subcommand accepts `--path` flag without error
- [ ] Walk output messages do not contain `./` prefix (manual grep of orchestrator output)
- [ ] README.md appears in the `.map.json` `artifacts.readme` array
