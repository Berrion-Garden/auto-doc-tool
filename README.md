# auto-doc

> **Automated documentation intelligence for Ruby projects.**  
> Analyze source code, generate rich docs, detect drift, and serve them as a browsable knowledge base — all with zero external dependencies.

auto-doc uses a pure-Ruby Ripper-based parser to extract classes, modules, methods, constants, imports, and doc comments from your Ruby code. It produces per-module AGENTS.md files, project-level README.md/INDEX.md/SUMMARY.md, Mermaid diagrams (DAG, class, C4 context/container, ERD), architecture docs, schema extraction, and a vector-based search index — all in a single command.

**No external services. No API keys. No heavy dependencies.** Just Ruby + stdlib.

---

## Quick Start

```bash
# Install
gem install auto-doc

# Generate documentation for your project
auto-doc generate

# Run a documentation completeness audit
auto-doc audit

# Or do both in one step
auto-doc verify

# Search the generated docs
auto-doc search "CacheService"
```

That's it. Run `auto-doc generate` in any Ruby project and you get a `.docs/` directory with full documentation. Review and commit it.

---

## CLI Reference

### Common Aliases

| Alias | Command |
|-------|---------|
| `auto-doc g` | `auto-doc generate` |
| `auto-doc doc` | `auto-doc generate` |
| `auto-doc gen` | `auto-doc generate` |

### All Commands

| Command | Description |
|---------|-------------|
| `generate [PATH]` | Generate AGENTS.md, README.md, INDEX.md, SUMMARY.md, diagrams, and vectors |
| `audit [PATH]` | Run documentation completeness audit |
| `verify [PATH]` | Generate + audit in one step |
| `diff SINCE [PATH]` | Show documentation drift since a git ref (e.g., `diff HEAD~5`) |
| `orphans [PATH]` | Find undocumented, unimported files |
| `search TERM [PATH]` | Search across INDEX.md, vectors, AGENTS.md, and source files |
| `agent PROMPT` | Natural-language queries (e.g., `agent "what depends on User"`) |
| `query MODULE [PATH]` | Show structured summary for a module |
| `diagram NAME [PATH]` | Display a Mermaid diagram |
| `tree [PATH]` | Display directory tree with box-drawing characters |
| `serve [PATH]` | Start a web server to browse generated docs |
| `init [PATH]` | Create `.autodoc.yml` config file |
| `e2e [PATH]` | Run end-to-end self-test |
| `version` | Print gem version |

### Global Flags

| Flag | Description |
|------|-------------|
| `--json` | Output structured JSON (machine-readable) |
| `--agent` | Output compact agent-optimized JSON (no timestamps) |
| `-v, --verbose` | Verbose output |

### Generate Options

| Option | Default | Description |
|--------|---------|-------------|
| `--format docs\|autodoc` | `docs` | Output to `.docs/` or `.autodoc/` |
| `--output-dir PATH` | — | Custom output directory (overrides `--format`) |
| `--incremental` | `false` | Skip unchanged files (uses mtime manifest) |
| `--exclude a b c` | `spec test vendor node_modules` | Additional exclude patterns |

### Audit Options

| Option | Default | Description |
|--------|---------|-------------|
| `--threshold N` | `80` | Minimum doc coverage % for passing |
| `--fail` | `false` | Exit with code 1 if below threshold |

### Verify Options

| Option | Default | Description |
|--------|---------|-------------|
| `--threshold N` | `80` | Same as audit threshold |
| `--ci` | `false` | Exit with code 1 on failure (for CI) |

### Search Options

| Option | Default | Description |
|--------|---------|-------------|
| `--source` | `false` | Also search source `.rb` files |
| `--limit N` | `20` | Maximum results |

### Orphans Options

| Option | Default | Description |
|--------|---------|-------------|
| `--rails` | `false` | Skip Rails autoloaded paths (models, controllers, etc.) |

### Agent Options

| Option | Default | Description |
|--------|---------|-------------|
| `--path PATH` | `.` | Project root directory |

### Serve Options

| Option | Default | Description |
|--------|---------|-------------|
| `--port N` | `4567` | Server port (binds to 127.0.0.1 by default) |

---

## Examples

```bash
# Generate docs for a specific project
auto-doc generate ~/projects/my-app

# Generate with compact agent-friendly output
auto-doc generate --agent

# Search with source file fallback
auto-doc search "User" --source --json

# Natural-language agent queries
auto-doc agent "what depends on Calculator"
auto-doc agent "describe the SearchService"
auto-doc agent "diagram for architecture"
auto-doc agent --json "list all symbols"

# Rails-specific: skip autoloaded paths in orphan detection
auto-doc orphans --rails

# Serve docs on a custom port
auto-doc serve --port 8080

# Check documentation drift
auto-doc diff HEAD~3

# CI gate
auto-doc verify --ci --threshold 85

# Custom output
auto-doc generate --format autodoc --exclude "tmp log"
```

---

## Output Structure (`--format docs`)

```
.docs/
├── README.md                      # Project overview with stats
├── INDEX.md                       # Full file/symbol/dependency index (project-level)
├── SUMMARY.md                     # Executive summary
├── VECTORS.json                   # Keyword vectors for all symbols
├── architecture.md                # C4-informed architecture doc
├── .map.json                      # Master manifest for tools
├── diagrams/
│   ├── deps.mmd                   # Dependency DAG
│   ├── class_diagram.mmd          # Inheritance hierarchy
│   ├── c4_context.mmd             # System context diagram
│   ├── c4_container.mmd           # Container diagram
│   └── erd.mmd                    # Entity-relationship (Rails only)
├── schema/
│   ├── schema.json                # Parsed db/schema.rb (Rails only)
│   └── models.json                # Model associations (Rails only)
├── <module>/
│   ├── AGENTS.md                  # Per-module public symbols docs
│   ├── INDEX.md                   # Per-module file/symbol index
│   ├── SUMMARY.md                 # Per-module summary
│   └── vectors.json               # Per-module vectors
├── bin/
│   └── AGENTS.md
├── lib/
│   ├── AGENTS.md
│   ├── INDEX.md
│   ├── SUMMARY.md
│   └── vectors.json
└── report.json                    # Latest audit report (machine-readable)
```

---

## Configuration

Create `.autodoc.yml` in your project root (or run `auto-doc init`):

```yaml
# auto-doc configuration
module_roots:
  - app
  - lib
  - bin

exclude_patterns:
  - vendor/**/*
  - node_modules/**/*
  - spec/**/*

output:
  directory: .docs
  format: markdown

audit:
  min_doc_coverage: 80
  max_module_size: 50

diagrams:
  generate_dag: true
  diagram_directory: diagrams
```

Without a config file, auto-doc uses sensible defaults (module roots: `app`, `lib`, `bin`; excludes: `spec`, `test`, `vendor`, `node_modules`).

---

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

---

## Server API

Start with `auto-doc serve`, then explore:

| Endpoint | Description |
|----------|-------------|
| `GET /` | List documented modules |
| `GET /README` | View project README |
| `GET /:module` | View module AGENTS.md |
| `GET /diagrams/:name` | View diagram |
| `GET /api/stats` | Coverage stats (JSON) |
| `GET /api/search?q=` | Full-text search (JSON) |
| `GET /api/query?q=` | Enhanced search (HTML) |
| `GET /api/index?path=` | Module INDEX.md |
| `GET /api/summary?path=` | Module SUMMARY.md |
| `GET /api/vectors?path=` | Module VECTORS.json |
| `GET /api/diagram/:name` | Diagram source (JSON) |
| `GET /api/schema` | Schema (JSON, Rails only) |
| `GET /api/architecture` | Architecture doc |
| `POST /api/agent` | Natural-language query (JSON) |

---

## Performance

- **Analysis cache**: Repeated commands (`verify`, `audit`) reuse cached analysis — **173× faster** on warm cache for a 193-file project.
- **Incremental generation**: `--incremental` only re-analyzes changed files using mtime comparison.
- **Server**: All routes use safe path resolution. Defaults to localhost only.

---

## Development

```bash
git clone https://github.com/auto-doc-tool/auto-doc
cd auto-doc

# Install dependencies
bundle install

# Run all tests
bundle exec rspec

# Run end-to-end self-test
bundle exec rake e2e

# Run against fixtures
ruby -I lib exe/auto-doc generate fixtures/sample_ruby_project
ruby -I lib exe/auto-doc audit fixtures/sample_ruby_project

# Documentation lint check
rubocop --lint lib/
```

---

## Philosophy

auto-doc follows these design principles:

1. **Zero new gem dependencies** — everything built on stdlib Ruby + existing deps (thor, sinatra)
2. **File-based everything** — `.docs/` directory is a self-contained knowledge base
3. **Dual-purpose output** — every file is human-readable AND machine-parseable
4. **Incremental generation** — when a file changes, only regenerate affected artifacts
5. **Agent-first design** — every command supports `--json` and `--agent` flags

---

## License

MIT
