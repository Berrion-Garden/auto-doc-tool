# Dependency Graph

## Execution Order
1. Milestone 1 (no dependencies)
2. Milestone 2 (depends on: Milestone 1 — needs templates to exist, analyzers to be importable)
3. Milestone 3 (depends on: Milestone 2 — needs generators and analyzers to wire)

## Dependency Rationale

```
M1: Analyzers + Templates
│
├── SchemaParser (independent)
├── ModelAssociationParser (independent)
└── 5 ERB templates (independent)
         │
         ▼
M2: Generators (needs templates from M1)
│
├── C4DiagramGenerator ──► c4_context_template.erb, c4_container_template.erb
├── ClassDiagramGenerator ──► class_diagram_template.erb
├── ERDGenerator ──► erd_template.erb (uses SchemaParser + ModelAssociationParser types)
└── ArchitectureGenerator ──► architecture_template.erb
         │
         ▼
M3: Wiring (needs all generators + analyzers)
│
├── orchestrator.rb ──► all 6 new modules
└── auto_doc.rb ──► require_relative all 6
```
