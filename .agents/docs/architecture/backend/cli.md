# CLI Module

## Class: `AutoDoc::CLI`

**File:** `lib/auto_doc/cli.rb`

### Purpose

Thor-based CLI with subcommands for documentation generation and auditing.

### Class Options

```ruby
class_option :verbose,  type: :boolean, aliases: "-v", default: false, desc: "Verbose output"
class_option :json,     type: :boolean, default: false, desc: "Output as JSON"
class_option :agent,    type: :boolean, default: false, desc: "Output compact agent-optimized JSON"
```

### Subcommands

| Subcommand | Description | OutputFormatter? |
|-----------|-------------|------------------|
| `init [PATH]` | Initialize `.autodoc.yml` config file | No |
| `generate [PATH]` | Generate AGENTS.md + README.md + diagrams | Yes (all modes) |
| `diff SINCE` | Show documentation drift since git ref | Yes (all modes) |
| `audit [PATH]` | Run documentation completeness audit | Yes (all modes) |
| `orphans [PATH]` | Find undocumented, unreferenced files | Yes (all modes) |
| `serve [PATH]` | Start web server to browse docs | No |
| `e2e [PATH]` | Run end-to-end self-test | No |
| `verify [PATH]` | Generate + audit in one step | No (text only) |
| `version` | Print gem version | No |

### Output Routing

All subcommands except `serve`, `e2e`, and `verify` route through `OutputFormatter`:

```ruby
output_format = output_format_for(options)
if output_format != :text
  silent = ->(_msg, _color = nil) { }
  result = orchestrator.generate(path, say: silent)
  AutoDoc::Utils::OutputFormatter.format(result, format: output_format, say: method(:say))
else
  orchestrator.generate(path, say: method(:say))
end
```

### Private Methods

- **`output_format_for(opts)`** — Returns `:agent` if `opts[:agent]`, `:json` if `opts[:json]`, `:text` otherwise. Agent takes precedence over json.
- **`orchestrator`** — Memoized `AutoDoc::Orchestrator.new(options.to_h)`.
- **`generate_default_config_yml`** — Returns YAML string for default `.autodoc.yml` with `directory: .docs`.

### Phase 2a Changes

- **Milestone 3**: `--json` and `--agent` class options added (lines 16-17).
- **Milestone 3**: All subcommands route results through `OutputFormatter` in json/agent mode.
- **Milestone 1**: `--format` option default changed from `"autodoc"` to `"docs"`. Config YAML generation emits `directory: .docs`.