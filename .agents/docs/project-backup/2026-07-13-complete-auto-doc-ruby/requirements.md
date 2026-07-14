# Auto-Documentation Tool — Requirements

## Product Vision

Auto-doc is a command-line documentation analyzer and generator for Ruby projects that inspects source code, extracts structural information (classes, modules, methods, constants, imports), and produces developer-reviewable draft documentation files. It helps teams keep documentation aligned with code by generating per-module guides, cross-referenced dependency diagrams, and coverage audits — all without external tooling beyond the Ruby standard library (plus optional web browsing features).

## User Roles

| Role | Description |
|------|-------------|
| **Ruby Developer** | Primary user. Runs auto-doc commands in their project directory to generate documentation drafts, audit coverage, identify gaps, and browse docs locally. |
| **Team Lead / Tech Writer** | Reviews generated draft documentation for accuracy, fills in "purpose" sections, commits as their own edits. May use the web server or plan-check feature for oversight. |
| **CI Pipeline** | Non-interactive user. Runs `auto-doc audit` with thresholds to gate PRs on doc coverage; may run self-test and plan verification automatically. |

## Functional Requirements

### FR-1: Orphan File Detection
A developer can identify Ruby source files that have no documentation comments, no import relationships (require/include/extend), and are not referenced in any other file's analysis — effectively "invisible" to the project's documentation graph.

**Acceptance Criteria:**
- Running `auto-doc orphans` on a target directory lists all qualifying Ruby files with their relative paths
- A file qualifies as an orphan when ALL three conditions hold: no doc comments, no require/include/prepend/extend statements, and no cross-references from other analyzed files
- The command exits 0 regardless of whether orphans are found (informational)
- Output lists one path per line, sorted alphabetically

**Edge Cases:**
- Empty directory → prints nothing, exits 0
- Directory contains only non-.rb files → prints nothing, exits 0
- All files have imports or docs → prints nothing, exits 0

### FR-2: Web Documentation Browsing
A developer can serve generated documentation in a local web server to browse modules, view individual module guides, see diagrams, and query stats without opening the file system.

**Acceptance Criteria:**
- Running `auto-doc serve` on a directory starts an HTTP server listening on port 4567 by default
- The root page lists all documented modules found in the generated output
- Clicking/navigating to a module path shows its AGENTS.md content rendered as HTML
- A README endpoint shows the project-level README.md content
- Diagrams are viewable at `/diagrams/<name>` (e.g., `/diagrams/deps.mmd`)
- An API stats endpoint returns JSON with coverage statistics read from `report.json` in the output directory
- An API search endpoint accepts a `q` query parameter and searches across all documentation content for matching terms, returning hit summaries as JSON
- The port is configurable via a `--port` flag (default 4567)

**Edge Cases:**
- No generated docs exist yet → root page shows a message instructing the user to run `generate` first
- Requested file does not exist → returns HTTP 404 with a descriptive message
- Search query matches nothing → returns empty results array in JSON

### FR-3: E2E Self-Test Pipeline
A developer can validate the auto-doc tool's own output by running its full pipeline against its source code, confirming that generation succeeds, audit passes coverage thresholds, and all expected output files are present.

**Acceptance Criteria:**
- Running `auto-doc e2e` executes the complete generate-and-audit pipeline against a target project (default: auto-doc's own project directory)
- Step 1 runs documentation generation for all module directories
- Step 2 runs a completeness audit and checks coverage meets the configured threshold
- Step 3 verifies that core output files exist in the output directory (`AGENTS.md`, `README.md`, `diagrams/deps.mmd`)
- The command prints a colorized PASS/FAIL report with details for each step
- Exit code is 0 if all steps pass, non-zero if any step fails

**Edge Cases:**
- Output files from a previous run exist but are stale → still validates file presence (staleness detection deferred)
- Audit threshold not configured in project → uses default 80% coverage

### FR-4: Alternative Output Directory Format
A developer can choose between the default `.autodoc/` output directory and an alternative `.docs/` directory, allowing teams with existing conventions to place generated docs where they prefer.

**Acceptance Criteria:**
- The `generate` command accepts a `--format` flag with values `autodoc` (default) or `docs`
- When `--format autodoc` is used (or not specified), output is written to `.autodoc/`
- When `--format docs` is used, output is written to `.docs/` instead
- The configuration file supports `output.directory` set to either `.autodoc` or `.docs`, overriding the CLI default
- All subcommands that read output files (`audit`, `serve`, `orphans`) respect the configured output directory
- Existing projects using the default `.autodoc/` are unaffected (backward compatible)

**Edge Cases:**
- Invalid `--format` value → prints usage error and exits non-zero
- Config specifies an unsupported directory name that does not start with a dot → accepts it as-is (no validation constraint on directory naming beyond what's needed for the two documented values)

### FR-5: Plan-Driven Verification
A team lead can define success criteria in a project plan file and have auto-doc automatically generate documentation, run an audit, and compare results against those criteria — producing a pass/fail report for each criterion.

**Acceptance Criteria:**
- Running `auto-doc plan-check` on a target directory reads a `PLAN.md` or `COMPLETION_PLAN.md` from the project root
- The command runs the full generate pipeline followed by an audit against the same directory
- It parses success criteria from the plan file (checklist items with pass/fail markers)
- Each criterion is matched against actual audit results and output files:
  - Criteria referencing doc coverage thresholds are verified against the audit report
  - Criteria referencing specific output file existence are checked by listing the output directory
  - Criteria describing command outcomes are validated by running those commands and checking exit codes
- The command prints a structured report showing each criterion with PASS, FAIL, or SKIP status
- Exit code is non-zero if any criterion fails

**Edge Cases:**
- Neither `PLAN.md` nor `COMPLETION_PLAN.md` found → prints error with available paths and exits 1
- Plan file exists but has no parseable success criteria sections → skips gracefully with a warning, exits 0
- A criterion references an output path not yet generated (because generate ran first) → verified as PASS if present

### FR-6: Comprehensive Test Coverage
Every module in the auto-doc codebase has unit tests that verify its core behavior, ensuring the tool can be safely modified and extended.

**Acceptance Criteria:**
- All existing modules have corresponding spec files covering their primary functionality
- Specs for each new or missing module test: default values, file loading behavior with valid input, handling of missing/empty/malformed input, and key output formatting
- The full spec suite runs without errors when executed from the project root
- New specs do not break existing passing tests

**Edge Cases:**
- Spec files for modules with no external dependencies use only stdlib or test fixtures
- Fixtures used by specs are self-contained and copied in `spec_helper` setup where needed
- Specs for modules depending on non-standard-library gems use conditional loading — tests are skipped with a descriptive message when optional dependencies are not installed
- Specs for file-reading modules handle files that: exist, do not exist, are empty, contain valid content, contain malformed content (invalid syntax for the reader's expected format)
- A spec that tests behavior depending on directory structure uses a temporary directory created in its setup block, not the project's fixture directory

### FR-7: Configuration Initialization
A developer can bootstrap a new project for auto-doc by running a single command that creates the configuration file with default settings.

**Acceptance Criteria:**
- Running `auto-doc init` in a directory creates a project config file at the expected convention path with default values
- The default configuration includes: module roots (`lib`), exclude patterns (`vendor`, `spec`, `node_modules`), output directory (`.autodoc`), and audit threshold (80%)
- Running `init` in a directory that already has a config file prints a warning and does not overwrite the existing file
- A path argument may be provided to create the config in a specific directory

**Edge Cases:**
- The target directory does not exist → prints error and exits non-zero
- The target directory exists but is empty → creates config file successfully
- The existing config file is empty or contains invalid syntax → prints warning and does not overwrite

### FR-8: CLI Subcommand Registration & Help Text
Every subcommand is registered on the CLI, responds to invocation from the executable entry point, and provides accurate help text accessible via `-h`.

**Acceptance Criteria:**
- All subcommands (`init`, `generate`, `audit`, `orphans`, `diff`, `version`, `serve`, `e2e`, `plan-check`) are callable from the CLI executable
- Each subcommand shows its description when running `auto-doc --help` or `auto-doc <subcommand> -h`
- The `serve` and `e2e` commands accept their documented flags (`--port`, defaults)
- The `generate` command accepts the new `--format` flag with valid values

**Edge Cases:**
- Invoking a subcommand without required arguments → shows help text for that subcommand, demonstrating that the CLI validates argument presence
- Unknown subcommand name → prints available subcommands and exits non-zero
- Invoking the executable without any subcommand → prints the main help listing (available commands list), does not crash or hang
- Passing a `--help` flag to any subcommand displays that subcommand's description and flags

## Non-Functional Requirements

| ID | Requirement | Details |
|----|-------------|---------|
| NFR-1 | Backward Compatibility | Existing commands (`init`, `generate`, `audit`, `diff`, `version`) continue to work unchanged. New commands (`orphans`, `serve`, `e2e`, `plan-check`) and the `--format` flag are additive only — they do not change existing behavior. Output paths, config formats, and report shapes must not change for existing users. |
| NFR-2 | No Breaking API Changes | Public module interfaces and class method signatures must not change — only additions are allowed, never removal or parameter changes to existing methods. |
| NFR-3 | Minimal Dependencies | Only `sinatra` and `webrick` are added beyond the existing `thor` dependency. All analyzer/generator/reporter modules use stdlib only. |
| NFR-4 | Web Server Isolation | The web server runs independently of any generation state — it reads already-generated files from disk. No data transformation happens in the HTTP layer. |

## Out of Scope

- Semantic search using embeddings or vector databases (deferred)
- Full YARD tag parsing (`@param`, `@return`) — current extraction is comment-block level only
- Incremental/stale detection comparing file modification timestamps against output
- Multi-language support (Ruby-only for now)
- CI integration configuration files (GitHub Actions workflows are separate from the gem)
