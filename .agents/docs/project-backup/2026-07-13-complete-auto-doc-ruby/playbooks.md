# Auto-Documentation Tool — Manual Test Playbooks

## Prerequisites
- [ ] Gem installed locally (`gem build && gem install pkg/auto-doc-*.gem`) or run via `ruby -I lib exe/auto-doc`
- [ ] Fixtures directory `test_fixtures/sample_ruby_project/` contains sample Ruby files for testing
- [ ] Console/terminal: no pre-existing errors from building or installing the gem

---

## Section 1: Orphan File Detection (FR-1)

### Play 1.1: Run orphans on a directory with known orphans
**Action:** `ruby -I lib exe/auto-doc orphans test_fixtures/sample_ruby_project`

**Pass/Fail Criteria:**
- [ ] Command exits with code 0
- [ ] Output lists one file path per line (or prints nothing if no orphans in fixture)
- [ ] Each listed file is a `.rb` file within the target directory tree
- [ ] Output is sorted alphabetically

**Screenshot:** Terminal showing command output and exit code.

---

### Play 1.2: Run orphans on empty directory
**Action:** Create `/tmp/empty-test-dir`, run `ruby -I lib exe/auto-doc orphans /tmp/empty-test-dir`

**Pass/Fail Criteria:**
- [ ] Command exits with code 0
- [ ] Output is blank (no lines printed)
- [ ] No error messages appear on stderr

**Screenshot:** Terminal showing empty output and exit code.

---

### Play 1.3: Run orphans where all files have imports
**Action:** Create a temp directory with two `.rb` files that `require_relative` each other, run `ruby -I lib exe/auto-doc orphans <dir>`

**Pass/Fail Criteria:**
- [ ] Command exits with code 0
- [ ] Output is blank (no orphans — all files have import relationships)
- [ ] No error messages appear on stderr

**Screenshot:** Terminal showing empty output and exit code.

---

## Section 2: Web Documentation Browsing (FR-2)

### Play 2.1: Start server with default port
**Action:** Run `ruby -I lib exe/auto-doc serve test_fixtures/sample_ruby_project --port 4568` in a terminal (use non-default port to avoid conflicts). Wait for it to start.

**Pass/Fail Criteria:**
- [ ] Server starts and listens on port 4568 without errors
- [ ] Process stays running (does not crash or exit)
- [ ] Console shows the server is ready (e.g., "Thin/WEBrick/Puma is listening")

**Screenshot:** Terminal showing server start-up message.

---

### Play 2.2: Browse root module listing page
**Action:** In browser, navigate to `http://localhost:4568`. If no generated docs exist yet in the fixture, observe the "no docs" message. If docs have been pre-generated (run `generate` first), verify the module list appears.

**Pass/Fail Criteria:**
- [ ] Page loads without JavaScript errors
- [ ] If docs are present: each documented module is listed as a link or item
- [ ] If no docs exist: page shows an instruction to run `generate` first
- [ ] No console errors in browser DevTools

**Screenshot:** Browser screenshot of root page.

---

### Play 2.3: View a specific module's AGENTS.md
**Action:** Navigate to the module path endpoint (e.g., `http://localhost:4568/lib`). If using the fixture, determine which modules were generated and navigate to one.

**Pass/Fail Criteria:**
- [ ] Page loads showing the AGENTS.md content rendered as HTML
- [ ] Content includes the module name header
- [ ] Table formatting is visible (not raw markdown) if dependencies or symbols are present
- [ ] No broken image links or missing CSS classes

**Screenshot:** Browser screenshot of a module detail page.

---

### Play 2.4: View README endpoint
**Action:** Navigate to `http://localhost:4568/README` (or the appropriate path for README content).

**Pass/Fail Criteria:**
- [ ] Page loads with the README.md content rendered as HTML
- [ ] Markdown tables and links are rendered correctly
- [ ] No console errors

**Screenshot:** Browser screenshot of README view.

---

### Play 2.5: View a diagram file
**Action:** Navigate to `http://localhost:4568/diagrams/deps.mmd` (after generating docs first via the generate command on the fixture).

**Pass/Fail Criteria:**
- [ ] Page loads showing the Mermaid diagram content
- [ ] Diagram renders visually as a graph/DAG in the browser
- [ ] Nodes and edges are clearly distinguishable
- [ ] No console errors from rendering library

**Screenshot:** Browser screenshot of rendered Mermaid DAG.

---

### Play 2.6: Check API stats endpoint
**Action:** In terminal, `curl -s http://localhost:4568/api/stats` (after generating docs and running audit to create report.json).

**Pass/Fail Criteria:**
- [ ] Response is valid JSON
- [ ] JSON contains coverage percentage field (e.g., `coverage_percent`)
- [ ] JSON contains total symbol count
- [ ] HTTP status code is 200

**Screenshot:** Terminal showing the curl response.

---

### Play 2.7: Search across docs
**Action:** In terminal, `curl -s "http://localhost:4568/api/search?q=class"` (using a term that likely appears in generated docs). Then try an empty search with just `/api/search`.

**Pass/Fail Criteria:**
- [ ] Search with query returns JSON array of hit summaries
- [ ] Each result includes the source file/module name and matched text
- [ ] Empty or missing query parameter still returns valid JSON (not a server error)
- [ ] HTTP status code is 200 for all requests

**Screenshot:** Terminal showing search results.

---

### Play 2.8: Request non-existent module
**Action:** Navigate to `http://localhost:4568/nonexistent-module`.

**Pass/Fail Criteria:**
- [ ] Page shows a descriptive 404 message (not a server error page)
- [ ] HTTP status code is 404
- [ ] Server does not crash or log internal exceptions

**Screenshot:** Browser screenshot of 404 page.

---

## Section 3: E2E Self-Test Pipeline (FR-3)

### Play 3.1: Run e2e against auto-doc's own project
**Action:** `ruby -I lib exe/auto-doc e2e /home/kyle/Projects/auto-doc-tool`

**Pass/Fail Criteria:**
- [ ] Command executes all pipeline steps sequentially (generate → audit → verify files)
- [ ] Each step prints a status indicator (PASS or FAIL) with details
- [ ] Output is colorized (ANSI color codes visible in terminal)
- [ ] If auto-doc itself has sufficient doc coverage: final report shows PASS for all steps
- [ ] Exit code is 0 on full pass

**Screenshot:** Terminal showing the complete E2E report.

---

### Play 3.2: Verify output files exist after e2e run
**Action:** After Play 3.1 completes successfully, check that `.autodoc/AGENTS.md`, `.autodoc/README.md`, and `.autodoc/diagrams/deps.mmd` exist in the target directory.

**Pass/Fail Criteria:**
- [ ] File listing shows all three expected files at their correct paths
- [ ] Each file is non-empty (contains generated content)

**Screenshot:** Terminal showing `ls -la` output for each expected file.

---

## Section 4: Alternative Output Directory Format (FR-4)

### Play 4.1: Generate with default autodoc format
**Action:** Run on a clean fixture directory: `ruby -I lib exe/auto-doc generate test_fixtures/sample_ruby_project` (no --format flag). Verify output goes to `.autodoc/`.

**Pass/Fail Criteria:**
- [ ] All output files are created under `test_fixtures/sample_ruby_project/.autodoc/`
- [ ] Files include AGENTS.md, README.md, and diagrams/deps.mmd
- [ ] No files appear in a `.docs/` directory

**Screenshot:** Terminal showing successful generation + directory listing of `.autodoc/`.

---

### Play 4.2: Generate with docs format
**Action:** Run on the same fixture: `ruby -I lib exe/auto-doc generate --format docs test_fixtures/sample_ruby_project` (ensure `.autodoc/` from previous run is cleaned up first, or use a fresh copy of fixture).

**Pass/Fail Criteria:**
- [ ] All output files are created under `test_fixtures/sample_ruby_project/.docs/`
- [ ] Files include AGENTS.md, README.md, and diagrams/deps.mmd at `.docs/` paths
- [ ] No files appear in a `.autodoc/` directory (the format flag controlled the destination)

**Screenshot:** Terminal showing successful generation + directory listing of `.docs/`.

---

### Play 4.3: Audit with docs output format
**Action:** After generating with `--format docs`, run `ruby -I lib exe/auto-doc audit --format docs test_fixtures/sample_ruby_project`. Verify the audit reads from and writes to the `.docs/` directory.

**Pass/Fail Criteria:**
- [ ] Audit runs without errors, reading generated docs from `.docs/`
- [ ] The report is written to `.docs/report.json` (or equivalent under the output dir)
- [ ] Coverage percentage appears in terminal output and matches expected value

**Screenshot:** Terminal showing audit report.

---

### Play 4.4: Serve with docs output format
**Action:** After generating with `--format docs`, run `ruby -I lib exe/auto-doc serve --format docs test_fixtures/sample_ruby_project`. Navigate in browser to verify the server reads from `.docs/`.

**Pass/Fail Criteria:**
- [ ] Server starts and loads data from `.docs/` instead of `.autodoc/`
- [ ] Module listing page shows content present in `.docs/` files
- [ ] API stats endpoint returns correct coverage read from `.docs/report.json`

**Screenshot:** Browser showing module list served from .docs.

---

### Play 4.5: Invalid format value
**Action:** Run `ruby -I lib exe/auto-doc generate --format invalid test_fixtures/sample_ruby_project`.

**Pass/Fail Criteria:**
- [ ] Command prints a usage error mentioning valid format values (`autodoc`, `docs`)
- [ ] No output files are created in any directory
- [ ] Exit code is non-zero

**Screenshot:** Terminal showing error message.

---

## Section 5: Plan-Driven Verification (FR-5)

### Play 5.1: Run plan-check on project with PLAN.md
**Action:** `ruby -I lib exe/auto-doc plan-check /home/kyle/Projects/auto-doc-tool`

**Pass/Fail Criteria:**
- [ ] Command finds and reads `PLAN.md` or `COMPLETION_PLAN.md` from the project root
- [ ] Runs full generate pipeline on the target directory before checking criteria
- [ ] Runs audit after generation completes
- [ ] Prints a structured report listing each criterion with PASS, FAIL, or SKIP status
- [ ] Criteria referencing output files are verified against actual disk contents
- [ ] Exit code is non-zero if any criterion fails

**Screenshot:** Terminal showing the full plan-check report.

---

### Play 5.2: Run plan-check when no plan file exists
**Action:** Create a temporary directory with sample Ruby files (no PLAN.md), run `ruby -I lib exe/auto-doc plan-check /tmp/plan-test`.

**Pass/Fail Criteria:**
- [ ] Command prints an error message naming the expected filenames (`PLAN.md`, `COMPLETION_PLAN.md`)
- [ ] Exit code is 1

**Screenshot:** Terminal showing the error output.

---

## Section 6: CLI Subcommand Registration (FR-7)

### Play 6.1: Verify all subcommands appear in help text
**Action:** Run `ruby -I lib exe/auto-doc --help` and inspect the list of available commands. Then run each command with `-h`: `init -h`, `generate -h`, `audit -h`, `orphans -h`, `diff -h`, `version -h`, `serve -h`, `e2e -h`, `plan-check -h`.

**Pass/Fail Criteria:**
- [ ] All 9 subcommands appear in the main help listing with descriptions: init, generate, audit, orphans, diff, version, serve, e2e, plan-check
- [ ] Each `subcommand -h` shows relevant flag documentation (e.g., `serve -h` mentions `--port`)
- [ ] No subcommands show generic "no description" text

**Screenshot:** Terminal showing main help + one representative sub-help output.

---

### Play 6.2: Invoke unknown subcommand
**Action:** Run `ruby -I lib exe/auto-doc nonexistent-command`.

**Pass/Fail Criteria:**
- [ ] Command prints the available subcommands list
- [ ] Exit code is non-zero

**Screenshot:** Terminal showing error output.

---

## Section 7: Web Server Port Configuration (FR-2)

### Play 7.1: Serve on custom port
**Action:** Run `ruby -I lib exe/auto-doc serve test_fixtures/sample_ruby_project --port 9876`. Navigate to `http://localhost:9876` in browser.

**Pass/Fail Criteria:**
- [ ] Server starts and listens on port 9876 (not default 4567)
- [ ] Root page is accessible at port 9876
- [ ] Navigating to `http://localhost:4567` does NOT serve this project's docs

**Screenshot:** Browser screenshot showing content loaded from port 9876.

---

## Section 8: E2E Self-Test Failure Path (FR-3)

### Play 8.1: Run e2e against a project that fails audit threshold
**Action:** Create a temporary directory with Ruby files having zero documentation comments, run `ruby -I lib exe/auto-doc e2e /tmp/uncovered-project --threshold 50`.

**Pass/Fail Criteria:**
- [ ] Generate step succeeds (docs created)
- [ ] Audit step prints FAIL status because coverage is below threshold
- [ ] File existence check still passes
- [ ] Overall report shows at least one step as FAILED
- [ ] Exit code is non-zero

**Screenshot:** Terminal showing the failure report with details.

---

## Section 9: Configuration Initialization (FR-7)

### Play 9.1: Init creates config in current directory
**Action:** Create a temporary directory, cd into it, run `ruby -I lib exe/auto-doc init`. Then inspect the contents of the resulting `.autodoc.yml` file.

**Pass/Fail Criteria:**
- [ ] Command exits with code 0
- [ ] A `.autodoc.yml` file is created in the target directory
- [ ] File contains module roots set to `lib`, exclude patterns including `vendor/spec/node_modules`, output directory set to `.autodoc`, and audit threshold set to 80

**Screenshot:** Terminal showing exit code + cat of config file.

---

### Play 9.2: Init in existing config directory
**Action:** Create a temp directory, run `init` once, then run it again in the same directory.

**Pass/Fail Criteria:**
- [ ] First invocation creates `.autodoc.yml`, exits 0
- [ ] Second invocation prints a warning that the file already exists and does NOT overwrite it
- [ ] File content after second run is identical to what was written on first run (unchanged)
- [ ] Exit code of second run is non-zero

**Screenshot:** Terminal showing both invocations and their output.

---

### Play 9.3: Init with explicit path argument
**Action:** Run `ruby -I lib exe/auto-doc init /tmp/init-test-dir`. Check that `.autodoc.yml` exists inside `/tmp/init-test-dir/`.

**Pass/Fail Criteria:**
- [ ] Command exits with code 0
- [ ] Config file is created at the specified path, not in CWD

**Screenshot:** Terminal showing successful init + ls of target dir.

---

### Play 9.4: Init on non-existent directory
**Action:** Run `ruby -I lib exe/auto-doc init /tmp/does-not-exist-xyz`.

**Pass/Fail Criteria:**
- [ ] Command prints an error saying the directory does not exist
- [ ] No config file is created anywhere
- [ ] Exit code is non-zero

**Screenshot:** Terminal showing error output.

---

## Section 10: Comprehensive Test Coverage (FR-6)

### Play 10.1: Run full spec suite
**Action:** From the project root, run `bundle exec rspec`. Capture the complete output.

**Pass/Fail Criteria:**
- [ ] All tests pass — zero failures, zero errors
- [ ] Test count is at least as large as before adding new specs (the suite grew)
- [ ] No pending/skipped tests unless explicitly marked with skip reason
- [ ] Exit code is 0

**Screenshot:** Terminal showing full rspec output.

---

### Play 10.2: Verify spec file completeness for all modules
**Action:** Check that every Ruby module under `lib/auto_doc/` has a corresponding `_spec.rb` file in the appropriate `spec/auto_doc/` subdirectory, excluding the CLI itself which may not have direct unit tests (tested via integration).

**Pass/Fail Criteria:**
- [ ] Spec files exist for: config, source_parser, import_extractor, yard_reader, agents_md_generator, readme_generator, diagram_generator, audit_reporter, completeness_checker, file_tree_builder, yaml_config_loader, server, e2e_runner, plan_verifier
- [ ] Each spec file is non-empty and contains at least one example
- [ ] No module under `lib/auto_doc/` lacks a corresponding spec

**Screenshot:** Terminal listing all spec files vs lib files.

---

### Play 10.3: Verify new specs test edge cases (missing input)
**Action:** Run rspec with verbose format (`--format documentation`) on the config, yaml_config_loader, and completeness_checker specs specifically — these modules have notable edge-case behaviors for missing/empty/malformed input.

**Pass/Fail Criteria:**
- [ ] At least one spec tests loading a non-existent file without crashing (should handle gracefully)
- [ ] At least one spec tests an empty config file or malformed YAML handling
- [ ] At least one spec tests coverage calculation when there are zero public symbols (division by zero edge case)

**Screenshot:** Terminal showing verbose test output for these modules.

---

## Section 11: CLI Help Text & Argument Validation (FR-8 additions)

### Play 11.1: Invoke executable with no subcommand
**Action:** Run `ruby -I lib exe/auto-doc` with zero arguments.

**Pass/Fail Criteria:**
- [ ] Command prints the main help listing showing all available subcommands
- [ ] No crash, hang, or unhandled exception
- [ ] Exit code is non-zero (usage error)

**Screenshot:** Terminal showing full help text output.

---

### Play 11.2: Pass --help to a specific subcommand
**Action:** Run `ruby -I lib exe/auto-doc serve --help`.

**Pass/Fail Criteria:**
- [ ] Command prints the description of the serve command and its flags (e.g., `--port`)
- [ ] No actual server starts — only help text is shown
- [ ] Exit code is 0

**Screenshot:** Terminal showing serve-specific help.

---

### Play 11.3: Pass --help to generate with format flag visible
**Action:** Run `ruby -I lib exe/auto-doc generate --help`.

**Pass/Fail Criteria:**
- [ ] Command prints the description of generate and all its flags including `--format`
- [ ] The help text shows available values for `--format` (`autodoc`, `docs`) if documented
- [ ] Exit code is 0

**Screenshot:** Terminal showing generate-specific help.

---

### Play 11.4: Serve subcommand --port flag visible in help
**Action:** Run `ruby -I lib exe/auto-doc serve -h`. Verify that the port option is listed with its default value and description.

**Pass/Fail Criteria:**
- [ ] Help text includes a line describing the port configuration (e.g., `-p, --port PORT`)
- [ ] Default value of 4567 is indicated if shown in help
- [ ] No other flags are falsely attributed to serve

**Screenshot:** Terminal showing serve help with port flag.
