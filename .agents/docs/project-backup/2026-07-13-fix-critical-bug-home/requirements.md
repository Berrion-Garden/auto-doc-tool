# Requirements: Fix FileTreeBuilder Exclusion Crash

## Product Vision

The auto-doc tool is a Ruby gem that generates developer documentation (AGENTS.md, README.md, and dependency diagrams) from Ruby source code directories. A critical bug in the file tree builder crashes on every `auto-doc generate` invocation when exclusion patterns contain non-string values, making it impossible to use the primary feature of the application. This fix restores the core generation capability with minimal, targeted changes and zero regressions.

## User Roles

| Role | Description |
|------|-------------|
| CLI User | Developer who runs `auto-doc generate <path>`, `auto-doc init`, or `auto-doc version` from the command line to generate documentation for source code projects. |

## Functional Requirements

### FR-1: Exclusion patterns must never be passed non-string values to fnmatch matching logic
**As a** CLI user running `auto-doc generate <path>`
**I want** directory exclusion filtering to work without crashing regardless of the input format
**So that** I can reliably generate documentation for any project

**Acceptance Criteria:**
- AC1.1: Directory exclusion filtering completes without TypeError or ArgumentError regardless of input pattern format (single values, nested arrays, or mixed types)
- AC1.2: Every path evaluated against exclusion patterns is handled as a string comparison — no type conversion errors occur
- AC1.3: Directory tree construction completes without error on any valid project path
- AC1.4: Exclusion filtering still functions correctly — excluded paths are skipped, non-excluded paths are included

**Edge Cases:**
- EC1.1: Patterns array contains nested arrays (e.g., `["/lib", ["/test"]]`)
- EC1.2: Patterns array is empty — returns false for all paths
- EC1.3: File path equals root path exactly (no prefix to strip)
- EC1.4: Pattern uses glob wildcards (e.g., `"**/*.rb"`)

### FR-2: `auto-doc generate <path>` completes successfully on both fixture projects
**As a** CLI user
**I want** the generate command to produce output files without errors on known test fixtures
**So that** I can verify the fix works across different project structures

**Acceptance Criteria:**
- AC2.1: Running `auto-doc generate` on the sample Ruby fixture path completes without error and exits with code 0
- AC2.2: Running `auto-doc generate` on the minimal gem fixture path completes without error and exits with code 0
- AC2.3: All three output files are created in `.autodoc/`: AGENTS.md, README.md, and diagrams/deps.mmd

**Edge Cases:**
- EC2.1: Fixture contains subdirectories (nested directory structure)
- EC2.2: Fixture contains minimal depth (few levels of nesting)

### FR-3: `auto-doc version` and `auto-doc init` continue to work without regression
**As a** CLI user
**I want** existing commands that do not use file tree building to function unchanged
**So that** I can trust the fix did not introduce unintended side effects

**Acceptance Criteria:**
- AC3.1: `auto-doc version` runs successfully and outputs a version string
- AC3.2: `auto-doc init` completes its initialization flow without error when run in a target directory

**Edge Cases:**
- EC3.1: `auto-doc init` is run on the project root itself (not a subproject)

## Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NFR-1 | **Minimal change:** Only the affected module is modified. No other files touched. |
| NFR-2 | **No ripple effects:** All existing modules continue to load and function. Zero changes to public API signatures. |
| NFR-3 | **Defensive coding:** The fix must guard against non-string coercion at the fnmatch boundary, not just for Array types but for any unexpected value type. |

## Out of Scope

- Adding new CLI commands or options
- Changing exclusion pattern syntax or matching behavior beyond what is necessary to prevent crashes
- Modifying the file tree rendering output format
- Adding unit tests or integration tests (covered separately under automated test suite work)
- Performance optimization of fnmatch matching
