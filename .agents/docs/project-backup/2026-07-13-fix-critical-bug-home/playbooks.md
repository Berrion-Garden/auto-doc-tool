# Manual Test Playbook: Fix FileTreeBuilder Exclusion Crash

## Prerequisites
- [ ] Ruby is installed and `ruby -v` succeeds
- [ ] The gem can be loaded (`ruby -I lib -r auto_doc -e "puts AutoDoc::VERSION"`)
- [ ] Both fixture directories exist and contain source files:
  - `fixtures/sample_ruby_project/` (nested directory structure with .rb files)
  - `fixtures/minimal_gem/` (minimal depth project structure)

---

## Section 0: Smoke Test — Infrastructure Health
**Level:** 0 | **Depends on:** nothing

### Play 0.1: Gem loads without errors
**Action:** Run `ruby -I lib -r auto_doc -e "puts 'loaded'"` in the project root.
**Expected Result:** Outputs `loaded` with exit code 0, no error output to stderr.

**Pass/Fail Criteria:**
- [ ] Command exits with code 0
- [ ] No stderr output
- [ ] Output contains `loaded`

### Play 0.2: FileTreeBuilder module is loadable
**Action:** Run `ruby -I lib -r auto_doc/utils/file_tree_builder -e "puts 'builder loaded'"`.
**Expected Result:** Outputs `builder loaded` with exit code 0, no error output to stderr.

**Pass/Fail Criteria:**
- [ ] Command exits with code 0
- [ ] No stderr output
- [ ] Output contains `builder loaded`

---

## Section 1: Core Fix — Exclusion Logic (FR-1)
**Level:** 1 | **Depends on:** Section 0 all pass

### Play 1.1: should_exclude? accepts array-wrapped patterns without crash
**Action:** Run the following Ruby inline test in project root:
```
ruby -I lib -r auto_doc/utils/file_tree_builder -e "
  b = AutoDoc::Utils::FileTreeBuilder.new('.', ['/lib', '/app'])
  puts b.send(:should_exclude?, Dir.pwd + '/some_file.rb')
"
```
**Expected Result:** No TypeError raised; method returns a boolean (true or false) without crashing on pattern coercion.

**Pass/Fail Criteria:**
- [ ] No TypeError raised
- [ ] No ArgumentError raised
- [ ] Exit code is 0
- [ ] Output is a valid Ruby value (`true`, `false`, or empty line — not an exception trace)

### Play 1.2: should_exclude? returns correct results for excluded vs non-excluded paths
**Action:** Run inline test (from project root):
```
ruby -I lib -r auto_doc/utils/file_tree_builder -e "
  b = AutoDoc::Utils::FileTreeBuilder.new('.', ['/lib'])
  puts b.send(:should_exclude?, Dir.pwd + '/lib/test.rb')
  puts b.send(:should_exclude?, Dir.pwd + '/app/models/user.rb')
"
```
**Expected Result:** First path matches exclusion pattern `/lib` → `true`. Second path does not match → `false`.

**Pass/Fail Criteria:**
- [ ] No TypeError raised
- [ ] Output first line is `true`
- [ ] Output second line is `false`

---

## Section 2: Generate Command on Fixtures (FR-2)
**Level:** 1 | **Depends on:** Section 1 all pass

### Play 2.1: Generate documentation from sample_ruby_project fixture
**Action:** In project root, run:
```bash
mkdir -p /tmp/test-fix-sample && ruby -I lib exe/auto-doc generate fixtures/sample_ruby_project --output-dir /tmp/test-fix-sample/.autodoc
```

**Pass/Fail Criteria:**
- [ ] Command exits with code 0
- [ ] No TypeError or ArgumentError in stderr
- [ ] `.autodoc/AGENTS.md` file created
- [ ] `.autodoc/README.md` file created
- [ ] `.autodoc/diagrams/deps.mmd` file created
- [ ] All three files are non-empty (> 0 bytes)

---

## Section 3: Generate Command on Minimal Gem Fixture (FR-2 cont.)
**Level:** 1 | **Depends on:** Section 2 all pass

### Play 3.1: Generate documentation from minimal_gem fixture
**Action:** In project root, run:
```bash
mkdir -p /tmp/test-fix-minimal && ruby -I lib exe/auto-doc generate fixtures/minimal_gem --output-dir /tmp/test-fix-minimal/.autodoc
```

**Pass/Fail Criteria:**
- [ ] Command exits with code 0
- [ ] No TypeError or ArgumentError in stderr
- [ ] `.autodoc/AGENTS.md` file created
- [ ] `.autodoc/README.md` file created
- [ ] `.autodoc/diagrams/deps.mmd` file created
- [ ] All three files are non-empty (> 0 bytes)

---

## Section 4: Regression Checks (FR-3)
**Level:** 2 | **Depends on:** Sections 1-3 all pass

### Play 4.1: auto-doc version still works
**Action:** Run `ruby -I lib exe/auto-doc version`.
**Expected Result:** Outputs a version string to stdout, exits with code 0.

**Pass/Fail Criteria:**
- [ ] Command exits with code 0
- [ ] Output is a readable version string (e.g., contains digits and dots like "0.x.y")
- [ ] No error output to stderr

### Play 4.2: auto-doc init still works on an empty directory
**Action:** 
1. Create temp dir: `mkdir -p /tmp/test-init-dir`
2. Run `ruby -I lib exe/auto-doc init /tmp/test-init-dir`
3. Verify the initialization output was created

**Pass/Fail Criteria:**
- [ ] Command exits with code 0
- [ ] No error output to stderr
- [ ] Target directory contains expected initialized structure (at minimum, no crash)
