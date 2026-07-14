# Manual Test Playbooks: Auto-Documentation Tool (Production Readiness)

## Prerequisites
- [ ] Gem root at `/home/kyle/Projects/auto-doc-tool`
- [ ] `ruby -Ilib exe/auto-doc version` prints version string, exits 0 (baseline health check)
- [ ] No pre-existing TypeError, NoMethodError, or NameError in any CLI command output
- [ ] `test_fixtures/sample_ruby_project/` contains sample Ruby files for testing

---

## Section 1: Smoke Test — Baseline Health
**Level:** 0  
**Depends on:** prerequisites only

### Play 1.1: Version subcommand works
**Action:** Run `ruby -Ilib exe/auto-doc version` from gem root.
**Expected Result:** Prints version string, exits code 0, no stderr.

**Pass/Fail Criteria:**
- [ ] Output contains a semver-style version (format: `auto-doc <major>.<minor>.<patch>`)
- [ ] Exit code is exactly 0
- [ ] No error text on stderr

---

### Play 1.2: Init subcommand creates config
**Action:** Run `mkdir -p /tmp/autodoc-test-init && ruby -Ilib exe/auto-doc init /tmp/autodoc-test-init`.
**Expected Result:** Creates `.autodoc.yml` with default configuration in the target directory.

**Pass/Fail Criteria:**
- [ ] No TypeError or crash during execution
- [ ] File `/tmp/autodoc-test-init/.autodoc.yml` exists after command completes
- [ ] Generated file is valid YAML (parseable without errors)

---

## Section 2: Core Generation — FR-1 + FR-4
**Level:** 1  
**Depends on:** Section 1 all pass

### Play 2.1: Generate does not crash in exclusion logic
**Action:** Run `ruby -Ilib exe/auto-doc generate test_fixtures/sample_ruby_project` from gem root.
**Expected Result:** Command completes without any TypeError or unhandled exception. `.autodoc/` directory created with output files.

**Pass/Fail Criteria:**
- [ ] No "no implicit conversion of Array into String" or similar TypeError in stdout or stderr
- [ ] No stack trace visible anywhere in command output
- [ ] Exit code is 0 (or non-zero only for audit threshold, not a crash)
- [ ] `.autodoc/` directory was created under `test_fixtures/sample_ruby_project/`

---

### Play 2.2: File tree exclusion patterns applied correctly
**Action:** After a successful generate run from Play 2.1, inspect the generated AGENTS.md file trees inside `.autodoc/`.
**Expected Result:** Excluded directories (`spec`, `test`, `vendor`, `node_modules`, `.git`) do not appear in any file tree text.

**Pass/Fail Criteria:**
- [ ] None of: `spec/`, `test/`, `vendor/`, `node_modules/`, `.git/` appear as directory entries in any generated file tree
- [ ] Non-excluded Ruby files ARE visible in the tree (at least the sample project's `.rb` files)
- [ ] Tree indentation characters render correctly (`├──`, `│`, `└──`) without encoding issues

---

### Play 2.3: Diagram output is valid Mermaid syntax
**Action:** Open `.autodoc/diagrams/deps.mmd` inside the generated directory. Inspect contents.
**Expected Result:** File starts with a valid Mermaid graph declaration and contains proper subgraph/edge syntax. No undefined variable names or incomplete blocks visible in text.

**Pass/Fail Criteria:**
- [ ] First line of file content is `graph TB` (or equivalent Mermaid direction declaration)
- [ ] Every subgraph opening (`subgraph "..."`) has a corresponding closing end within the file
- [ ] Edge arrows (`-->`) connect node IDs that are declared as nodes earlier in the file
- [ ] No visible nil, undefined, or bare variable names where a literal string should appear

---

## Section 3: E2E Self-Test — FR-5
**Level:** 1  
**Depends on:** Section 2 all pass

### Play 3.1: E2E subcommand runs all 6 checks
**Action:** Run `ruby -Ilib exe/auto-doc e2e test_fixtures/sample_ruby_project` from gem root (clean `.autodoc/` first).
**Expected Result:** All 6 sequential checks execute and report pass/fail. Final summary shows total count of passes vs failures.

**Pass/Fail Criteria:**
- [ ] Check 1: `.autodoc/` directory created — PASS or FAIL reported clearly
- [ ] Check 2: AGENTS.md files written — PASS or FAIL reported clearly
- [ ] Check 3: README.md written — PASS or FAIL reported clearly
- [ ] Check 4: `deps.mmd` diagram file written — PASS or FAIL reported clearly
- [ ] Check 5: `report.json` exists — PASS or FAIL reported clearly
- [ ] Check 6: Audit exit code reflects threshold compliance — PASS or FAIL reported clearly

---

### Play 3.2: E2E works without manual `.autodoc/` cleanup
**Action:** Run `ruby -Ilib exe/auto-doc e2e test_fixtures/sample_ruby_project` a SECOND time immediately after the first run (without deleting `.autodoc/`).
**Expected Result:** Second execution still passes all 6 checks. Existing output does not cause false failures.

**Pass/Fail Criteria:**
- [ ] No error about pre-existing `.autodoc/` directory or files
- [ ] All 6 checks report PASS on second run
- [ ] Final summary shows all pass (or clearly documented failure reasons)

---

## Section 4: Audit Command — FR-3 Regression + Verification
**Level:** 1  
**Depends on:** Section 2 all pass

### Play 4.1: Audit completes without crash and reports coverage
**Action:** Run `ruby -Ilib exe/auto-doc audit test_fixtures/sample_ruby_project` from gem root.
**Expected Result:** Outputs a human-readable coverage table to stdout. Optionally writes JSON report. Exit code reflects threshold compliance, not crashes.

**Pass/Fail Criteria:**
- [ ] No TypeError or NoMethodError in any output (stdout or stderr)
- [ ] Coverage table shows total symbol count and documented count
- [ ] Coverage percentage is displayed as a number with % sign
- [ ] Exit code is 0 if coverage >= default threshold, non-zero only for low coverage

---

### Play 4.2: Generate then audit in sequence (full developer workflow)
**Action:** 
1. `rm -rf test_fixtures/sample_ruby_project/.autodoc/`
2. `ruby -Ilib exe/auto-doc generate test_fixtures/sample_ruby_project`
3. `ruby -Ilib exe/auto-doc audit test_fixtures/sample_ruby_project`

**Expected Result:** Both commands complete successfully. Audit report references the same analysis as generation produced.

**Pass/Fail Criteria:**
- [ ] Step 2 exits without crash and `.autodoc/` directory populated
- [ ] Step 3 exits without crash and outputs coverage table
- [ ] Total symbols in audit output matches count of public methods/classes in fixture source files
- [ ] No new console errors on either command (check stderr for both)

---

## Section 5: Orphans Subcommand — FR-7
**Level:** 1  
**Depends on:** Section 2 all pass

### Play 5.1: Orphans subcommand lists undocumented files
**Action:** Run `ruby -Ilib exe/auto-doc orphans test_fixtures/sample_ruby_project` from gem root.
**Expected Result:** Lists Ruby source files that have no import edges and no doc references. No crashes.

**Pass/Fail Criteria:**
- [ ] Command completes without TypeError or unhandled exception
- [ ] Output lists file paths (relative to scanned directory) of potentially orphaned files
- [ ] Files with zero `require`/`include` statements AND no YARD/doc comments are included in output

---

## Section 6: Serve Subcommand — FR-8 + FR-9
**Level:** 2  
**Depends on:** Section 3 all pass (docs generated first)

### Play 6.1: Serve starts web server and serves docs
**Action:** 
1. Ensure `.autodoc/` exists from a previous generate run
2. Run `ruby -Ilib exe/auto-doc serve test_fixtures/sample_ruby_project` in background
3. Wait for server to become ready (poll with curl or wait ~2 seconds)

**Expected Result:** Server starts listening on port 4567 and serves content from `.autodoc/`.

**Pass/Fail Criteria:**
- [ ] No crash during startup — no stack trace visible
- [ ] Gem boots cleanly even if server dependency is not installed (error only on first request, or clear message)
- [ ] Server process is running and accepting connections

---

### Play 6.2: Serve serves AGENTS.md content via browser endpoint
**Action:** After the server from Play 6.1 is running, curl a generated doc file URL: `curl http://localhost:4567/app/AGENTS.md` (adjust path to match actual `.autodoc/` structure).
**Expected Result:** Returns the content of the AGENTS.md file with appropriate HTTP status code and content type.

**Pass/Fail Criteria:**
- [ ] HTTP response status is 200 OK
- [ ] Response body contains the same text that was generated to `.autodoc/app/AGENTS.md`
- [ ] Content-Type header indicates text or markdown (not binary)

---

### Play 6.3: Query endpoint returns matching results
**Action:** After the server from Play 6.1 is running, send a POST request with JSON body to `/query`: `curl -X POST http://localhost:4567/query -H 'Content-Type: application/json' -d '{"term":"User"}'`.
**Expected Result:** Returns JSON array of matching modules, classes, methods, or descriptions containing the search term.

**Pass/Fail Criteria:**
- [ ] HTTP response status is 200 OK
- [ ] Response body is valid JSON (parseable)
- [ ] Results include entries that match the query term in name, class name, method name, or description text
- [ ] If `term` field is missing from request body → returns list of top-level modules instead of error

---

### Play 6.4: Query with empty results returns empty array
**Action:** Send a POST to `/query` with term that matches nothing: `curl -X POST http://localhost:4567/query -H 'Content-Type: application/json' -d '{"term":"zzznonexistent"}'`.
**Expected Result:** Returns JSON response with an empty array (not null, not error).

**Pass/Fail Criteria:**
- [ ] HTTP status is 200 OK (not 404 or 500)
- [ ] Response body parses to a valid JSON empty array `[]`
- [ ] No error message in the response

---

### Play 6.5: Serve fails gracefully if port already in use
**Action:** Start two serve commands back-to-back: first one on default port, then attempt second without stopping the first.
**Expected Result:** Second invocation prints a clear error about port conflict and exits non-zero with no stack trace.

**Pass/Fail Criteria:**
- [ ] Second invocation does not crash — no Ruby exception trace visible
- [ ] Error message mentions port conflict or address already in use
- [ ] Exit code is non-zero for the second invocation only; first server still running

---

## Section 7: Alternative Output Directory — FR-11
**Level:** 2  
**Depends on:** Section 2 all pass

### Play 7.1: Generate with --format docs writes to .docs/
**Action:** Run `ruby -Ilib exe/auto-doc generate test_fixtures/sample_ruby_project --format docs` from gem root (ensure `.autodoc/` is clean or irrelevant).
**Expected Result:** All generated artifacts appear under `<project_dir>/.docs/` instead of `.autodoc/`.

**Pass/Fail Criteria:**
- [ ] Directory `test_fixtures/sample_ruby_project/.docs/` exists after command completes
- [ ] AGENTS.md files are inside `.docs/` tree (not in `.autodoc/`)
- [ ] README.md is inside `.docs/` tree
- [ ] `diagrams/deps.mmd` is inside `.docs/diagrams/deps.mmd`
- [ ] No artifacts appear under `.autodoc/` for this run

---

### Play 7.2: Audit reads from same alternate directory as generate wrote to
**Action:** After the generate with `--format docs` from Play 7.1, run `ruby -Ilib exe/auto-doc audit test_fixtures/sample_ruby_project`.
**Expected Result:** Audit operates on `.docs/` content (same location where generate wrote), not stale `.autodoc/` content.

**Pass/Fail Criteria:**
- [ ] Audit completes without TypeError or mismatch errors about file paths
- [ ] Coverage report reflects the same analysis that generation used — symbol counts match between generate and audit runs on the alternate directory
- [ ] Exit code is 0 for normal coverage, non-zero only if below threshold (not a crash)

---

## Section 9: Automated Test Verification — FR-10
**Level:** 1  
**Depends on:** prerequisites only

### Play 9.1: Full spec suite executes without failures
**Action:** Run `bundle exec rspec` from gem root.
**Expected Result:** All tests pass with zero failures and zero errors. Exit code is 0.

**Pass/Fail Criteria:**
- [ ] All test examples report green/pass (no red or pending)
- [ ] No TypeError, NoMethodError, or runtime exceptions in test output
- [ ] Test execution completes within 30 seconds
- [ ] Coverage of analyzer modules confirmed — every file under `analyzer/` has a corresponding `_spec.rb`

---

### Play 9.2: Generator specs verify output format correctness
**Action:** Run `bundle exec rspec spec/auto_doc/generator/` to run only generator tests.
**Expected Result:** Tests pass and include assertions about output content structure (not just "does not crash").

**Pass/Fail Criteria:**
- [ ] AGENTS.md generator test verifies table format and section headers exist in output text
- [ ] Diagram generator test validates Mermaid syntax elements (`graph`, `subgraph`, `-->`) are present
- [ ] Readme generator test passes with correct file table content
- [ ] Zero failures across all generator tests

---

### Play 9.3: Reporter specs cover pass and fail threshold paths
**Action:** Run `bundle exec rspec spec/auto_doc/reporter/` to run only reporter tests.
**Expected Result:** Tests include both threshold-pass and threshold-fail scenarios, each asserting the correct exit code or boolean flag.

**Pass/Fail Criteria:**
- [ ] Coverage calculation test: verify documented count, undocumented count, percentage math
- [ ] Threshold pass test: assertion confirms `passed?` is true when coverage >= threshold
- [ ] Threshold fail test: assertion confirms `passed?` is false when coverage < threshold
- [ ] JSON formatting test verifies output parses as valid JSON

---

### Play 9.4: CLI spec tests cover each subcommand's argument parsing
**Action:** Run `bundle exec rspec spec/auto_doc/cli_spec.rb`.
**Expected Result:** Tests pass for every registered subcommand — `generate`, `audit`, `init`, `orphans`, `e2e`, `serve`, `version` — confirming argument parsing and delegation work correctly.

**Pass/Fail Criteria:**
- [ ] Each subcommand has at least one passing test case verifying correct argument routing
- [ ] Invalid arguments produce appropriate error output (not crashes)
- [ ] All tests pass with zero failures

---

## Section 10: Cross-Feature Integration — Level 3
**Level:** 3  
**Depends on:** Sections 2–9 all pass where applicable

### Play 10.1: Full workflow — generate → e2e → serve → query → test suite
**Action:** Execute the complete developer workflow in sequence from a clean state:
1. `rm -rf test_fixtures/sample_ruby_project/.autodoc/ test_fixtures/sample_ruby_project/.docs/`
2. `ruby -Ilib exe/auto-doc generate test_fixtures/sample_ruby_project --format docs`
3. `ruby -Ilib exe/auto-doc e2e test_fixtures/sample_ruby_project`
4. Start serve in background, wait for readiness
5. Curl `/query` with a meaningful search term
6. Stop the server process
7. Run `bundle exec rspec` from gem root

**Expected Result:** Every step completes successfully in sequence without unexpected errors between stages. The test suite passes after all bug fixes are applied.

**Pass/Fail Criteria:**
- [ ] Step 2 creates `.docs/` with all artifacts (no crash)
- [ ] Step 3 reports all 6 checks PASS
- [ ] Step 4 starts server without error
- [ ] Step 5 returns JSON results from query endpoint
- [ ] Step 6 cleanly terminates the background process
- [ ] Step 7 runs all tests with zero failures and completes within 30 seconds

---

### Play 10.2: Generate on a project with zero Ruby files after exclusion
**Action:** Create a temporary directory with only non-Ruby files, then run `ruby -Ilib exe/auto-doc generate <that_dir>`.
**Expected Result:** Command completes without crash. Generated output reflects an empty module (no classes, methods, or dependencies).

**Pass/Fail Criteria:**
- [ ] No exception during generation — even with zero Ruby files to analyze
- [ ] AGENTS.md file exists and contains placeholder text for "No public symbols found"
- [ ] Diagram file still produced with valid but empty graph structure (no nodes, no edges)
- [ ] Audit reports 0% coverage gracefully (not an error condition)
