# Dependency Graph

## Execution Order
1. Milestone 1: AgentQueryService (no dependencies) ────┐
2. Milestone 2: MapGenerator + Orchestrator Wiring (no dependencies) ─┤
                                                                      │
                                                                      ├── Both feed into
                                                                      │
3. Milestone 3: CLI Subcommands + Server Expansion + Main Wiring (depends on: Milestone 1, Milestone 2)
```

**Rationale:** AgentQueryService (M1) and MapGenerator (M2) share zero code dependencies. They operate on different concerns — query routing vs. artifact inventory. Both are leaf modules that the presentation layer (M3) consumes. The CLI `agent` subcommand and `POST /api/agent` server endpoint need AgentQueryService. The orchestrator wiring point for MapGenerator is independent. Building M1 and M2 in parallel is safe; M3 must come after both to wire everything together.
