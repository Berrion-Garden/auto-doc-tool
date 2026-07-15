# Dependency Graph

## Execution Order

```
Milestone 1: Config Migration (.autodoc → .docs)
    │
    ├──→ Milestone 2: INDEX/SUMMARY/VECTORS Generators
    │           │
    │           └──→ Milestone 3: OutputFormatter + --json/--agent CLI
```

1. **Milestone 1** (no dependencies) — Config migration establishes the `.docs/` target directory. Must be first because M2 generators write into `.docs/` and M2 tests validate `.docs/` paths. Backward compat ensures existing `.autodoc/` users aren't broken.

2. **Milestone 2** (depends on: Milestone 1) — New generators produce INDEX.md, SUMMARY.md, and VECTORS.json into `.docs/`. Depends on M1 because the orchestrator wiring determines output paths from the config migration. Tests verify artifacts land in `.docs/`.

3. **Milestone 3** (depends on: Milestone 2) — OutputFormatter and CLI flags depend on M2 because the formatter needs to know the structure of data produced by generate/audit (which now include index/summary/vector generation). CLI wiring routes subcommand results through OutputFormatter.
