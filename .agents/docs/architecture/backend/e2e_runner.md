# E2ERunner

## Class: `AutoDoc::Tester::E2ERunner`

**File:** `lib/auto_doc/tester/e2e_runner.rb`

### Purpose

Runs end-to-end validation of the auto-doc pipeline against itself. Verifies generate, audit, and output file completeness. Used by the `auto-doc e2e` CLI subcommand.

### Constants

```ruby
PASS  = "PASS"
FAIL  = "FAIL"
WARN  = "WARN"
OUTPUT_DIR = ".docs"
```

### Constructor

```ruby
def initialize(project_dir)
  @project_dir = File.expand_path(project_dir)
  @gem_dir     = File.expand_path(File.join(__dir__, "../../.."))
  @results     = []
end
```

### API

```ruby
passed = E2ERunner.run(project_dir = ".")
# Returns: Boolean — true if all steps pass, false if any fail
```

### Test Steps

The E2E test runs 7 sequential steps, each wrapped in a `step` helper that prints `PASS` or `FAIL` and tracks results:

| Step | Name | Test |
|------|------|------|
| 0 | Clean up existing `.docs` | Removes `.docs/` directory if it exists |
| 1 | Generate docs | Runs `ruby -I#{gem_dir}/lib #{gem_dir}/exe/auto-doc generate #{project_dir} 2>&1`, checks exit status |
| 2 | Check `.docs/` exists | Verifies output directory was created |
| 3 | Check README.md | Verifies `README.md` exists in `.docs/` |
| 4 | Check diagrams/deps.mmd | Verifies `diagrams/deps.mmd` exists in `.docs/` |
| 5 | Check AGENTS.md | For each module root directory in `.docs/`, verifies `AGENTS.md` exists and has > 50 bytes of content |
| 6 | Run audit | Runs `ruby -I#{gem_dir}/lib #{gem_dir}/exe/auto-doc audit --threshold 0 #{project_dir} 2>&1`, checks exit status |
| 7 | Check report.json | Verifies `report.json` exists and contains `overall_coverage` key |

### `step(name)` (private)

Yield-based step runner:
1. Prints `"  #{name}... "`
2. Yields to the block, captures `[result, detail]`.
3. If result is truthy: appends `{ name:, status: PASS }`, prints `PASS`.
4. If result is false: appends `{ name:, status: FAIL, detail: }`, prints `FAIL`, prints detail on next line.

### Output

```
============================================================
auto-doc E2E Self-Test
Project: /path/to/project
============================================================

  Clean up existing .docs... PASS
  Generate docs... PASS
  Check .docs/ directory exists... PASS
  Check README.md exists... PASS
  Check diagrams/deps.mmd exists... PASS
  Check lib/AGENTS.md exists... PASS
  Check lib/AGENTS.md has content... PASS
  Run audit... PASS
  Check report.json exists... PASS
  Check report.json contains coverage data... PASS

============================================================
Results: 10 passed, 0 failed, 10 total
============================================================
```

### Implementation Note

- The test invokes auto-doc via subprocess (`ruby -I... exe/auto-doc ...`) rather than calling the classes directly. This tests the full binary path including CLI, config loading, and orchestrator.
- Uses `--threshold 0` for audit so the test completes regardless of actual documentation coverage levels.
- Module root detection uses directory listing of `.docs/` (excluding `diagrams/` subdirectory).