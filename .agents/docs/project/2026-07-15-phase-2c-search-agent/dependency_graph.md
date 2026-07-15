# Dependency Graph

## Execution Order
1. Milestone 1 (no dependencies) — SearchService: core search engine, no other services depend on it
2. Milestone 2 (depends on: Milestone 1) — AgentQueryService: uses SearchService.search for fallback on unrecognized intents
3. Milestone 3 (depends on: Milestone 1, Milestone 2) — CLI Subcommands: wires SearchService, AgentQueryService, and FileTreeBuilder into Thor

```
M1 (SearchService) ──┬──→ M3 (CLI Subcommands)
                     │
                     └──→ M2 (AgentQueryService) ──→ M3 (CLI Subcommands)
```

Milestones 1 and 2 could theoretically be developed in parallel if the fallback interface is defined upfront, but sequential is safer since M2 literally calls `SearchService.search` for unrecognized intents.
