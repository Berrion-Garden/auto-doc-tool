# auto-doc

> Automated documentation generator for Ruby projects

**auto-doc** analyzes Ruby source files to generate AGENTS.md (per-module), README.md (project overview), and Mermaid dependency DAG diagrams. It extracts classes, modules, methods, constants, imports, and doc comments — no external Ruby parsing dependencies required beyond a pure-Ruby Ripper-based parser.

## Quick Start

```bash
# Install
gem install auto-doc

# Initialize config
auto-doc init

# Generate documentation
auto-doc generate

# Audit coverage
auto-doc audit

# One-step verify (generate + audit)
auto-doc verify
```

## CLI Commands

| Command | Description |
|---------|-------------|
| `init [PATH]` | Create `.autodoc.yml` config in directory |
| `generate [PATH]` | Generate AGENTS.md, README.md, and diagrams |
| `audit [PATH]` | Run documentation completeness audit |
| `verify [PATH]` | Generate docs then run audit in one step |
| `diff SINCE` | Show documentation drift since a git ref |
| `orphans [PATH]` | Find undocumented, unimported files |
| `serve [PATH]` | Start a web server to browse docs |
| `e2e [PATH]` | Run end-to-end self-test |
| `version` | Print gem version |

### Generate Options

- `--format autodoc|docs` — Output to `.autodoc/` or `.docs/`
- `--output-dir PATH` — Custom output directory
- `--incremental` — Skip unchanged directories
- `--exclude one two` — Additional exclude patterns

### Audit Options

- `--threshold N` — Minimum doc coverage percentage (default: 80, exit 1 if below)

### Verify Options

- `--threshold N` — Same as audit threshold
- `--ci` — CI-friendly mode (minimal output)

### Serve Options

- `--port N` — Server port (default: 4567)

## Configuration

Create a `.autodoc.yml` file in your project root (or run `auto-doc init`):

```yaml
module_roots:
  - app
  - lib
  - bin

exclude_patterns:
  - vendor/**/*
  - node_modules/**/*
  - spec/**/*

output:
  directory: .autodoc
  format: markdown

audit:
  min_doc_coverage: 80
  max_module_size: 50

diagrams:
  generate_dag: true
  diagram_directory: diagrams
```

## Output Structure

Generated documentation is placed in `.autodoc/` by default:

```
.autodoc/
├── README.md                        # Project-level overview
├── <module_name>/
│   └── AGENTS.md                    # Per-module docs (classes, methods, dependencies)
├── diagrams/
│   └── deps.mmd                     # Mermaid dependency DAG
└── report.json                      # Audit report (machine-readable)
```

## CI Integration

```yaml
# .github/workflows/docs.yml
name: Documentation Check
on: [push, pull_request]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
      - run: gem install auto-doc
      - run: auto-doc verify --ci --threshold 80
```

## Development

```bash
git clone https://github.com/auto-doc-tool/auto-doc
cd auto-doc

# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run end-to-end self-test
bundle exec rake e2e

# Run against fixtures
ruby -I lib exe/auto-doc generate fixtures/sample_ruby_project
ruby -I lib exe/auto-doc audit fixtures/sample_ruby_project
```

## License

MIT
