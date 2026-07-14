# Product Requirements: Auto-Documentation Tool (v0.1.0 Production Readiness)

## Product Vision

`auto-doc` is a Ruby gem that automatically generates draft documentation — AGENTS.md, README.md, and Mermaid dependency diagrams — by statically analyzing Ruby source code. A developer runs one command (`auto-doc generate <path>`) and gets structured markdown drafts in minutes for review and commit. The tool uses only Ruby stdlib (Ripper-based parsing) with zero external dependencies, making it a lightweight first step toward better project documentation. This initiative brings the partially built gem to production-ready quality: all runtime bugs are fixed, test coverage is added across critical paths, new subcommands (`e2e`, `serve`) function correctly, and the end-to-end pipeline validates itself reliably.

## User Roles

| Role | Responsibility | Interaction with Tool |
|------|---------------|----------------------|
| Developer (primary user) | Runs the gem on their Ruby/Rails project, reviews generated drafts, commits as edits | Invokes CLI subcommands (`generate`, `audit`, `init`, `orphans`, `e2e`, `serve`) |
| CI system (secondary) | Runs `auto-doc audit` to gate PRs on doc coverage threshold | Calls CLI with flags; reads JSON report for pass/fail decision |

## Functional Requirements

### FR-1: Generate Command Executes Without Runtime Errors

**As a** developer running documentation generation,  
**I want** the `generate` subcommand to complete without any crash or unhandled exception,  
**so that** I have draft documentation ready to review.

**Acceptance Criteria:**
- [ ] Running `auto-doc generate <path>` on any valid project directory completes with exit code 0 (or non-zero only for audit threshold failures, not crashes)
- [ ] No TypeError, NoMethodError, or NameError appears in stdout or stderr during execution
- [ ] The `.autodoc/` output directory is created and populated with expected artifact files
- [ ] All detected module directories receive AGENTS.md output

**Edge Cases:**
- Source project has deeply nested directory structures (depth > 5)
- Module directory contains zero Ruby files after exclusion filtering
- No config file exists — tool falls back to all defaults
- Config file `.autodoc.yml` references non-existent paths for module_roots
- A single subdirectory's generation fails — remaining directories still process and errors go to stderr

---

### FR-2: Source Code Analysis Pipeline Produces Structured Data Correctly

**As a** developer running `generate`,  
**I want** each analysis stage (class extraction, import detection, doc comment reading) to return properly structured results that generators can consume without type errors,  
**so that** the documentation pipeline completes end-to-end.

**Acceptance Criteria:**
- [ ] Running any analyzer module on a source file produces an array of structured results — never wraps results in unexpected nesting levels
- [ ] Import detection identifies `require`, `include`, `prepend`, and `extend` statements with accurate line numbers and target names
- [ ] Doc comment lookup returns a keyed structure supporting direct name-to-comment access — no need to linearly search through an array
- [ ] All analyzer output shapes are internally consistent so generators iterate over arrays or access hashes uniformly without type mismatches

**Edge Cases:**
- Source file contains no classes, modules, or methods (empty file, only comments)
- Parser encounters dynamic Ruby patterns (`define_method`, `const_set`) — silently skip with no crash
- Multiple comment lines preceding a single definition (multi-line doc block)

---

### FR-3: Diagram Generator Produces Valid Mermaid Output

**As a** developer reviewing the generated dependency graph,  
**I want** the Mermaid DAG diagram in `.autodoc/diagrams/deps.mmd` to be syntactically valid and renderable,  
**so that** I can understand module dependencies visually.

**Acceptance Criteria:**
- [ ] Generated `.mmd` file starts with `graph TB` declaration
- [ ] All subgraph declarations are properly opened and closed — no undefined variables or missing blocks
- [ ] Node identifiers use consistent naming (no bare variables or nil interpolation)
- [ ] Edge arrows (`-->`) connect existing node IDs only

**Edge Cases:**
- Project has zero inter-file dependencies (single file, or all files isolated) → diagram still produces valid empty graph structure
- Module directories have deeply nested hierarchies — subgraphs render without duplicate declarations
- Import targets reference modules not present in analyzed directory tree

---

### FR-4: File Tree Builder Handles Exclusion Patterns Without Crashes

**As a** developer viewing file trees in generated docs,  
**I want** exclusion patterns applied safely to every basename comparison,  
**so that** the tool never crashes on type mismatches during pattern matching.

**Acceptance Criteria:**
- [ ] Every exclusion check ensures both pattern and string are converted to strings before fnmatch call — no TypeError from Array-to-String coercion
- [ ] Default exclusions (`spec`, `test`, `vendor`, `node_modules`, `.git`) prevent those directories from appearing in any file tree output
- [ ] Custom exclusion patterns loaded from config (YAML arrays, strings, mixed types) are all applied without crashing
- [ ] Exclusion pattern values that resolve to nil or non-string are safely skipped

**Edge Cases:**
- Config `exclude_patterns` contains nested arrays instead of flat lists
- A file basename is an empty string (corner case from unusual filesystem state)
- Glob patterns with special characters (`*`, `?`, `[`) — handled as glob, not literal strings

---

### FR-5: End-to-End Self-Test Validates Full Pipeline

**As a** developer or CI system,  
**I want** an `e2e` subcommand that runs the complete generation and audit pipeline against a project directory,  
**so that** I can verify tool correctness before relying on it.

**Acceptance Criteria:**
- [ ] Running `auto-doc e2e <path>` executes generate then audit in sequence without intermediate errors
- [ ] The E2E command runs exactly 6 sequential checks and reports pass/fail for each: (1) output directory created, (2) AGENTS.md files written, (3) README.md written, (4) diagram file written, (5) JSON report exists, (6) audit exit code reflects threshold compliance
- [ ] If any check fails, remaining checks still run and a final summary shows total pass/fail count
- [ ] The E2E test works without requiring output directory to be manually cleaned — it detects existing output and continues

**Edge Cases:**
- Source project has zero public symbols → audit reports 0% coverage (not an error, just the result)
- Project directory doesn't exist → prints clear error message and exits non-zero without stack trace
- E2E is run against a large real-world project — timing out after reasonable threshold

---

### FR-6: Init Subcommand Creates Configuration Scaffold

**As a** developer starting with an undocumented project,  
**I want** an `init` subcommand that creates a default configuration file,  
**so that** I can customize module roots and exclusions before running generate.

**Acceptance Criteria:**
- [ ] Running `auto-doc init <path>` creates a `.autodoc.yml` configuration file in the target directory without crashing
- [ ] No TypeError or crash when optional CLI arguments resolve to nil during scaffold creation
- [ ] Generated YAML is valid and parseable — contains default module_roots, exclude_patterns, output settings, and audit thresholds
- [ ] Running `init` on a path that already has `.autodoc.yml` does not overwrite existing config

**Edge Cases:**
- Target directory does not exist — creates it or prints clear error (depends on implementation choice)
- Config file already exists with custom values — preserved, not overwritten
- Nil optional arguments passed by CLI framework during init call

---

### FR-7: Orphans Subcommand Detects Undocumented Files

**As a** developer auditing project documentation coverage,  
**I want** an `orphans` subcommand that lists source files with zero import edges and no doc references,  
**so that** I can identify modules that may have been forgotten or are truly isolated.

**Acceptance Criteria:**
- [ ] Running `auto-doc orphans <path>` completes without crash and outputs a list of file paths to stdout
- [ ] Listed files have no require/include/extend/import statements referencing other project modules AND contain no doc comments preceding any definition
- [ ] Files that DO have imports or doc comments are NOT included in the orphan list
- [ ] Command exits with code 0 even when zero orphans are found (empty output is valid)

**Edge Cases:**
- All files have documentation — output is empty but exit code is 0
- Source directory contains no Ruby files at all — command completes gracefully with informative output
- Deeply nested project structure — orphan detection traverses all levels without stack overflow or timeout

---

### FR-8: Web Server Subcommand Serves Generated Docs Locally

**As a** developer who wants to browse documentation in a browser,  
**I want** a `serve` subcommand that starts a local HTTP server on the generated docs directory,  
**so that** I can review output without opening individual files.

**Acceptance Criteria:**
- [ ] Running `auto-doc serve <path>` starts a web server (default port 4567) and serves static content from the generated output directory
- [ ] The server is lazy-loaded — gem boots without error even if the server dependency isn't installed; error only appears when user invokes `serve`
- [ ] Browsing to the root URL lists available module documentation files
- [ ] Accessing a specific module file (e.g., `/app/AGENTS.md`) serves it with correct content type

**Edge Cases:**
- Server port 4567 is already in use → prints error and exits non-zero (no crash)
- Generated output directory doesn't exist yet on first serve → server starts but shows "no docs generated" message
- Server dependency is not installed → `serve` command fails gracefully with a helpful install instruction

---

### FR-9: Query Server Phase — Interactive Query Endpoint

**As a** developer who wants to ask questions about their project structure,  
**I want** an interactive query endpoint accessible via the web server,  
**so that** I can explore documented modules and find specific symbols without browsing file by file.

**Acceptance Criteria:**
- [ ] Running `auto-doc serve <path>` exposes a `/query` JSON endpoint that accepts POST requests with a search term
- [ ] The query returns matching module names, classes, methods, and their brief descriptions from the analysis data
- [ ] Query results are sorted by relevance (exact match > prefix > substring)
- [ ] Empty or missing query parameters return all top-level modules

**Edge Cases:**
- Query matches zero results → returns empty array with 200 status (not an error)
- Very large project (>100 modules) → query response completes within 3 seconds
- Non-JSON request body to `/query` → returns clear JSON error message

---

### FR-10: Automated Tests Cover Critical Code Paths

**As a** maintainer verifying tool correctness,  
**I want** unit and integration tests covering all analyzer modules, generators, reporters, and the CLI layer,  
**so that** bug regressions are caught before reaching production.

**Acceptance Criteria:**
- [ ] Every module in the analyzer subdirectory has a corresponding test file with tests for its primary methods
- [ ] Every generator module has tests verifying output format correctness (not just "does not crash")
- [ ] Reporter modules have tests covering both success and failure paths (threshold pass, threshold fail)
- [ ] CLI layer has tests covering argument parsing for each subcommand (`generate`, `audit`, `init`, `orphans`, `e2e`, `serve`)
- [ ] All existing test files continue to pass after bug fixes are applied — no regressions in the test suite

**Edge Cases:**
- Tests run against fixture projects with known structures, not live repos (deterministic results)
- Full test execution completes within 30 seconds
- Test output uses clear descriptions so failures indicate the exact assertion that broke

---

### FR-11: Alternative Output Directory Support

**As a** developer whose project prefers `.docs/` over `.autodoc/`,  
**I want** an option to direct all generated output to a different directory,  
**so that** tool output coexists naturally with my existing documentation conventions.

**Acceptance Criteria:**
- [ ] Running `auto-doc generate <path> --format docs` creates output under `<project_dir>/.docs/` instead of `.autodoc/`
- [ ] All artifact files (AGENTS.md, README.md, deps.mmd, report.json) appear in the alternate directory with correct relative paths
- [ ] Subsequent `audit <path>` reads from and writes to the same alternate directory — no mismatch between where generate wrote and audit reads
- [ ] The `.docs/` output is a complete mirror of what `.autodoc/` would produce (same content, different path)

**Edge Cases:**
- Alternate directory already contains files → overwritten without warning (generate is destructive by design for drafts)
- Project root has no write permission → graceful error message instead of unhandled filesystem exception

---

## Non-Functional Requirements

| Requirement | Detail |
|------------|--------|
| **Zero new runtime dependencies (v1)** | Only stdlib used for generate, audit, e2e. Server dependency is optional/lazy-loaded |
| **CLI execution time** | `generate` on fixture project completes under 30 seconds; E2E pipeline under 60 seconds |
| **Error reporting** | Per-directory failures don't block remaining directories; all errors logged to stderr with file path context |
| **Backward compatibility** | Existing `.autodoc.yml` config format unchanged; no breaking changes to analyzer or generator APIs |
| **Test suite speed** | Full test execution completes within 30 seconds |

## Out of Scope

- Fixing Ripper's inability to parse dynamic Ruby patterns (`define_method`, `const_set`) — documented v1 limitation, not a bug
- Adding Phase 2 features (deep AST via tree-sitter, YARD gem structured parsing, incremental generation)
- CI integration or GitHub Actions workflow files
- Multi-language support beyond Ruby
