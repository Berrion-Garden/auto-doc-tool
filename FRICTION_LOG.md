# Friction Log — auto-doc Gem

> Maintained by orchestrator sessions. Generated docs should include this metadata.

## Active Friction Points

### F1: Root-Owned File Permissions (HIGH)
**Date:** 2026-07-13
bob_26 agents create files as `root:root`. Container has "no new privileges" flag, preventing `sudo chown`/`chmod`. Neither kyle user nor subsequent bob_26 sessions can modify these files.
**Workaround:** All file modifications must go through bob_26 agents. Create new files in kyle-owned dirs when possible.
**Resolution:** Requires container config change to disable "no new privileges" flag.

### F2: CLI Lifecycle Discoverability (HIGH)
**Date:** 2026-07-13
bob_26's `chat` is shown first in help but `plan`/`build` are the intended workflows. Not discoverable.
**Workaround:** Always use `plan`, `build`, or `debug` for structured work. `chat` for trivial one-shots only.

### F3: Architecture Planner Stall (MEDIUM)
**Date:** 2026-07-13
`architecture_planner` node hangs indefinitely on `ast_grep_search` (zero output, idle_seconds climbs past 60).
**Workaround:** Intervene at 60s idle on architecture_planner. Cancel and relaunch.

### F6: bob_26 Chat Startup Stalling (HIGH)
**Date:** 2026-07-13
New `chat` executions consistently stall at 0 outputs for 30-60+ seconds.
**Workaround:** Wait at least 60-90 seconds before cancelling. Use `research`/`debug` as alternatives.

### F8: Dynamic Ruby Patterns Not Parsed (LOW)
**Date:** 2026-07-13
Ripper-based parser doesn't handle `const_set`, `define_method`, `method_missing`.
**Planned fix:** Phase 2.

## Resolved

### R1: FileTreeBuilder TypeError (2026-07-13)
`.flatten` + `is_a?(String)` guard at line 82.

### R2: Readme Template (2026-07-13)
`module_name`→`project_name` in readme_template.erb.

### R3: Diagram Template (2026-07-13)
`subgraphs`→`graph_nodes`, `edges`→`graph_edges` in diagram_dag_template.erb.

### R4: ERB Template Variable Mismatch (2026-07-13)
`module_name→project_name`, `subgraphs→graph_nodes`, `edges→graph_edges` in all three ERB templates.
**Lesson:** Always cross-reference generator `binding()` locals when creating ERB templates.

### R5: `--help` Treated As Generate Path (2026-07-16)
`auto-doc generate --help` now correctly shows Thor help instead of treating `--help` as a path argument. Thor intercepts `--help` before the method is called. Guard clause (`return help("generate") if path == "--help"`) retained as safety net.

### R6: No Staleness Detection (2026-07-13)
`generate` now supports TimestampTracker + `--incremental` flag (commit 85cbe52) to skip unchanged directories.
