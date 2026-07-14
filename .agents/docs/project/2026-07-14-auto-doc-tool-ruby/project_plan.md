# Project Plan: 2026-07-14-auto-doc-tool-ruby

## Hypotheses Considered

### Hypothesis 1: Incremental enhancement — extend existing verify, rewrite server_spec with rack/test, add standalone CI docs
The `verify` subcommand already exists and chains `generate` → `audit`. Extend it with a `--ci` option that controls exit codes. Rewrite `server_spec.rb` to use `rack/test` (replacing the current `Net::HTTP`-based approach that isn't even running in the test suite). Add `README.md` and CI config as standalone new files. Fix any missing exit codes.

### Hypothesis 2: Two-phase serial approach — CI infrastructure first, then code changes
Phase 1: add `rack-test` gem dependency, README.md, CI config. Phase 2: rewrite server_spec.rb, add `--ci` to verify. Unnecessary serialization — these are largely independent and can be parallelized within a single milestone.

### Hypothesis 3: Minimalist — only add new files, don't touch CLI
Create README.md, CI config, and server_spec.rb. Leave `verify` as-is since it already works. This fails to meet the explicit requirement for `--ci` mode with exit code behavior.

### Selected: Hypothesis 1
The `verify` command already exists as a working chain; the `--ci` addition is a surgical change. The server_spec.rb already exists but uses a fragile `Net::HTTP` + real-thread approach that doesn't run in the test suite (no entries in `spec/examples.txt`). Rewriting to `rack/test` makes it fast, reliable, and actually part of CI. README and CI config are standalone file additions. Risk: rack-test must be compatible with Rack 3.x / Sinatra 4.x.

---

## Milestone 1: Add verify --ci option, server_spec rewrite, README, and CI config

**Intent:** All five deliverables are small, independently testable, and have no blocking dependencies on each other. Grouping them into a single milestone keeps the plan lean while enabling parallel work within the implementation pass.

### Implementation

#### Backend Work Items
- [ ] `lib/auto_doc/cli.rb` (lines 288-294): Update existing `verify` subcommand to add `method_option :ci, type: :boolean, default: false` and modify the method body to handle CI exit codes — on failure with `--ci`, exit 1; on success, exit 0. The `audit` invocation already exits 1 on failure; ensure verify propagates that properly when `--ci` is set.
- [ ] `lib/auto_doc/cli.rb` (line 121-125): Verify `diff` already exits 1 for missing SINCE (confirmed at lines 123-124). No changes needed for diff or audit — both already have correct exit codes.
- [ ] `Gemfile`: Add `gem "rack-test", "~> 2.1"` to the `:development` group (required by rewritten server_spec).

#### Frontend Work Items
- [ ] `spec/auto_doc/server_spec.rb`: **Rewrite** from current `Net::HTTP` + real-thread approach to use `rack/test`. Replace `around` block + `@server_thread` + `Net::HTTP.get_response` with `include Rack::Test::Methods` and `app { AutoDoc::Server }`. Use rack-test's `get(path)` and `last_response` for assertions. Preserve all existing test coverage: GET / returns HTML listing, GET /README returns content, GET /README escapes HTML, GET /:module returns AGENTS.md, GET /:module returns 404, GET /diagrams/:name, GET /diagrams nonexistent 404, GET /api/stats JSON, GET /api/search with/without query. Add: GET /nonexistent returns 404 (explicitly called out in requirements).
- [ ] `spec/spec_helper.rb`: Add `require "rack/test"` and `RSpec.configure { |c| c.include Rack::Test::Methods }` so the helper methods are available to server_spec.
- [ ] `spec/auto_doc/cli_spec.rb`: Add tests for the `verify` subcommand — verify it invokes generate+audit, and verify `--ci` flag is accepted.
- [ ] `README.md` (project root, NEW): Write gem-level README covering: what auto-doc is, quick start (`gem install auto-doc`, `auto-doc init`, `auto-doc generate`, `auto-doc audit`), CLI commands reference (all 9 subcommands), configuration via `.autodoc.yml`, output format (.autodoc/ directory structure), CI integration example using `verify --ci`, development setup.
- [ ] `.github/workflows/ci.yml` (NEW): GitHub Actions workflow triggering on push/PR to main, matrix of Ruby 3.0/3.1/3.2/3.3, steps: checkout, setup-ruby, bundle install, rspec, e2e self-test.

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit (server_spec) | All 13+ server routes via rack/test | All pass, fast (no real server) |
| Unit (cli_spec) | `verify` command accepts --threshold and --ci | Command is defined, options accepted |
| Integration | RSpec full suite after changes | 110+ examples, 0 failures |
| E2E | `ruby -I lib exe/auto-doc e2e .` | 12/12 steps passing |
| Manual | `ruby -I lib exe/auto-doc help verify` | Shows verify with --threshold and --ci |
| Manual | `ruby -I lib exe/auto-doc verify --threshold 0 .` | Passes (generates docs then audits) |

### Verification Criteria
- [ ] `bundle exec rspec --format progress` shows 0 failures and 110+ examples (up from 103; server_spec contributes ~15, cli_spec verify adds ~2)
- [ ] `ruby -I lib exe/auto-doc help verify` shows the `verify` command with both `--threshold` and `--ci` options
- [ ] `ruby -I lib exe/auto-doc e2e .` passes all 12 steps
- [ ] `ruby -I lib exe/auto-doc verify --threshold 0 .` passes (generate + audit with low threshold)
- [ ] `ruby -I lib exe/auto-doc verify --threshold 100 --ci .` exits with code 1 (audit fails below 100% coverage)
- [ ] `ruby -I lib exe/auto-doc diff` exits with code 1 and error message
- [ ] `README.md` exists at project root with all required sections
- [ ] `.github/workflows/ci.yml` exists with matrix of Ruby 3.0-3.3
