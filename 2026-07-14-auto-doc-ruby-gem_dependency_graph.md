# Dependency Graph

## Execution Order
1. Milestone 1 (no dependencies) — "Fix Infrastructure and Compilation Errors"
2. Milestone 2 (depends on: Milestone 1) — "Fix Failing Spec Logic and Source Bugs"

Milestone 2 depends on Milestone 1 because you cannot diagnose failing spec logic until all specs can load and be discovered without error.
