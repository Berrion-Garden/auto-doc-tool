# PHASE 2 PLAN — auto-doc v1.0 Architecture
## From Static Doc Generator to Interactive Documentation Intelligence System

**Status:** Architecture Design | **Target:** v1.0 | **Current:** v0.2.0

---

## Objective
Transform `auto-doc` from a "generate static docs" tool into an **interactive documentation intelligence system** that produces richer generated artifacts, offers intelligent search, serves as an agent-friendly knowledge base, and auto-generates architecture-level diagrams — all without external vector databases or heavy dependencies.

## Architecture Decision

**Approach: File-based intelligence with keyword-structured vector representations — no external services, no embedding models.**

The core architectural bet: instead of integrating a vector DB or requiring an LLM API key, we store all intelligence as structured files that both humans and LLM agents can consume directly. Semantic search is implemented as **keyword-extracted ranking** over structured chunks — each symbol's "vector" is a JSON record containing summary, signature, dependencies, doc text, and extracted keywords.

**Key principles:**
1. **Zero new gem dependencies** — everything built on stdlib Ruby + existing deps (thor, sinatra)
2. **File-based everything** — `.docs/` directory is a self-contained knowledge base
3. **Dual-purpose output** — every file is human-readable AND machine-parseable
4. **Incremental generation** — when a file changes, only regenerate affected artifacts
5. **Agent-first design** — `--agent` and `--json` flags on every command

---

## Implementation Plan

### Phase 2a — Foundation: Output Rename + INDEX/SUMMARY/VECTORS

**Goal:** Establish the `.docs/` output structure with rich per-directory artifacts and universal `--json`/`--agent` flags.

#### Step 2a.1: Rename `.autodoc/` → `.docs/`
#### Step 2a.2: Add `INDEX.md` Generator at every directory level
#### Step 2a.3: Add `SUMMARY.md` Generator at every directory level
#### Step 2a.4: Add `VECTORS.json` Project-level + per-module vector files
#### Step 2a.5: Add `--json` and `--agent` Flags with OutputFormatter

### Phase 2b — Smart Architecture Generation

#### Step 2b.1: Schema Parser (db/schema.rb + migrations)
#### Step 2b.2: Model Association Parser
#### Step 2b.3: C4 Context & Container Diagram Generator
#### Step 2b.4: Class Diagram Generator (inheritance, includes)
#### Step 2b.5: ERD Generator (tables + associations)
#### Step 2b.6: Architecture.md Generator
#### Step 2b.7: Wire all into orchestrator.rb

### Phase 2c — Search & Agent CLI

#### Step 2c.1: Search Service (multi-strategy ranked)
#### Step 2c.2: Agent Query Service (intent detection)
#### Step 2c.3: New CLI subcommands: search, query, tree, diagram, agent
#### Step 2c.4: Wire search/agent into orchestrator

### Phase 2d — Server Expansion & Polish

#### Step 2d.1: Expand Sinatra Server with new API endpoints
#### Step 2d.2: `.map.json` — master manifest generator
#### Step 2d.3: E2E test updates

---

## Final `.docs/` Directory Structure

```
.docs/
├── .map.json
├── README.md
├── INDEX.md
├── SUMMARY.md
├── VECTORS.json
├── architecture.md
├── report.json
├── diagrams/
│   ├── deps.mmd
│   ├── architecture_context.mmd
│   ├── architecture_container.mmd
│   ├── classes.mmd
│   └── erd.mmd
├── schema/
│   ├── schema.json
│   └── models.json
├── lib/
│   ├── AGENTS.md
│   ├── INDEX.md
│   ├── SUMMARY.md
│   ├── vectors.json
│   ├── auto_doc/
│   │   ├── AGENTS.md
│   │   ├── INDEX.md
│   │   ├── SUMMARY.md
│   │   ├── vectors.json
│   │   ├── analyzer/
│   │   │   ├── AGENTS.md
│   │   │   ├── INDEX.md
│   │   │   ├── SUMMARY.md
│   │   │   └── vectors.json
│   │   ├── generator/  ...
│   │   ├── reporter/   ...
│   │   └── utils/      ...
│   └── ...
└── bin/ ...
```

---

## Success Criteria

1. `.docs/` directory contains all specified artifacts at every directory level
2. All CLI subcommands work with `--json` and `--agent` flags
3. `auto-doc search` returns relevant results ranked by relevance
4. `auto-doc agent "show me X's dependencies"` returns correct dependency information
5. Architecture diagrams render correctly in GitHub/GitLab
6. Schema extraction works on any Rails project with `db/schema.rb`
7. Backward compatible — existing `.autodoc/` users are not broken
8. Zero new gem dependencies
9. All RSpec tests pass (target: 250+ examples)
10. Self-hosted: `auto-doc` documents itself using its own v1.0 features
