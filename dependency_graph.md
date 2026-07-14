# Dependency Graph

## Execution Order

```
Milestone 1 (Fix Blocking Bugs)
  |
  v
Milestone 2 (Utility + Config Specs)
  |
  +--------+
  |        |
  v        v
Milestone 3 (Reporter + Generator Specs)
  |
  v
Milestone 4 (CLI + Server Specs + Final Verification)
```

## Dependencies

- **Milestone 1** (Fix Blocking Bugs) — no dependencies. Must complete first: all subsequent spec writing depends on correct analyzer/reporter behavior. Running specs against broken code produces noise, not signal.

- **Milestone 2** (Utility and Config Specs) — depends on Milestone 1. Tests Config, YamlConfigLoader, FileTreeBuilder. These modules are truly independent (no analyzer/reporter dependencies), so they can be tested safely once the gem loads correctly (thor dependency fixed).

- **Milestone 3** (Reporter and Generator Specs) — depends on Milestone 2. Reporter specs test CompletenessChecker and AuditReporter which consume Config patterns validated in M2. Generator specs test AgentsMdGenerator and DiagramGenerator which produce output formats tested in isolation. These two groups (reporter and generator) could run in parallel but are sequenced for simplicity.

- **Milestone 4** (CLI and Server Specs + Final Verification) — depends on Milestone 3. CLI integration tests exercise all modules below (config → analyzer → generator → reporter). Server specs test the Sinatra endpoints serving generated docs. Final verification runs the E2E self-test pipeline against the gem's own source.

## Parallelism Potential

- Milestone 3's reporter and generator specs are independent of each other (both depend only on shared utilities validated in M2). They could execute in parallel if needed.
- All spec files within a milestone can be written in any order — they test independent modules.

## Module Dependency Hierarchy

```
                    CLI (Thor subcommands)
                   /    |    \         \
                  /     |     \         \
          Server   Reporter  Generator  Analyzer
             |         |        |          |
             +---------+--------+----------+
                       |
                   Config / Utils
```

- **Config/Utils** (bottom layer): YamlConfigLoader, FileTreeBuilder, Config — no dependencies
- **Analyzer**: SourceParser, ImportExtractor, YardReader — depends on Config for exclusions
- **Generator**: AgentsMdGenerator, ReadmeGenerator, DiagramGenerator — depends on Analyzer output shapes
- **Reporter**: AuditReporter, CompletenessChecker — depends on Analyzer output + Config thresholds
- **Server**: Sinatra — depends on generated .autodoc/ output
- **CLI**: Thor — orchestrates all modules; depends on Config for settings, Analyzer for parsing, Generator for output, Reporter for audit
