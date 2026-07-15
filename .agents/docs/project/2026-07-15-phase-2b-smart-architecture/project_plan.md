# Project Plan: 2026-07-15-phase-2b-smart-architecture

## Hypotheses Considered

### Hypothesis 1: Linear Sequential (one module at a time)
Build each module individually: SchemaParser, then ModelAssociationParser, then templates, then C4DiagramGenerator, and so on — testing each in isolation. This gives tight feedback but creates too many milestones (6+) and delays integration feedback until wiring.

### Hypothesis 2: By Layer (analyzers → templates → generators → wiring)
Group all analyzers first, then all templates, then all generators, then wiring. Clean separation by architectural layer with 4 milestones. However, generators require templates to produce meaningful output, so testing generators before templates exist forces stubs.

### Hypothesis 3: By Output Category (C4 bundle, ERD bundle, class diagram bundle, architecture bundle)
Each milestone ships a complete vertical slice: parser + template + generator for one diagram type. Maximizes testability within each milestone but spreads wiring across milestones and causes merge conflicts on orchestrator.rb.

### Selected: Hypothesis 2 (Modified)
Group into 3 milestones: (1) analyzers + templates together, (2) all generators, (3) wiring. This is strongest because: templates and generators are tightly coupled (generators need templates to render), grouping them in adjacent milestones allows generators to use real templates immediately; analyzers are fully independent and testable in isolation; wiring is a single clean change at the end that can be verified against a full test suite. The 3-milestone structure keeps each pass achievable while respecting real code dependencies.

---

## Milestone 1: Analyzers and Templates

**Intent:** Build the two new analyzers (SchemaParser, ModelAssociationParser) with full specs and test fixtures, plus all 5 ERB templates. Analyzers are independent of generators; templates are simple ERB files with no logic. These are the foundation that generators will consume in M2.

### Implementation

#### Backend Work Items
- [ ] `lib/auto_doc/analyzer/schema_parser.rb`: Create SchemaParser with `.parse(project_dir)` returning `[{table_name:, columns: [{name:, type:, null:, default:}], indexes: [], foreign_keys: []}]`. Use regex to parse `db/schema.rb` `create_table` blocks. Scan `db/migrate/` for migration timestamps.
- [ ] `lib/auto_doc/analyzer/model_association_parser.rb`: Create ModelAssociationParser with `.parse(project_dir)` returning `[{model:, table:, associations: [{type:, target:, options: {}}]}]`. Scan `app/models/**/*.rb` for `has_many`, `belongs_to`, `has_one`, `has_and_belongs_to_many`. Infer table name from class name (User → users). Handle `self.table_name =` overrides.
- [ ] `spec/auto_doc/analyzer/schema_parser_spec.rb`: Test schema.rb parsing: create_table with columns (string, integer, datetime, boolean, text), null/not null, default values, index definitions, foreign_key references, multiple tables, empty schema, missing file
- [ ] `spec/auto_doc/analyzer/model_association_parser_spec.rb`: Test association extraction: belongs_to, has_many, has_one, has_and_belongs_to_many, table name inference (standard + overridden), options parsing (class_name, foreign_key, through), empty models directory, non-Rails project
- [ ] `fixtures/rails_project/db/schema.rb`: Create test fixture with realistic Rails schema (users, posts, comments tables with indexes and foreign keys)
- [ ] `fixtures/rails_project/db/migrate/20240101000000_create_users.rb`: Create migration fixture for timestamp scanning
- [ ] `fixtures/rails_project/app/models/user.rb`: Create model fixture with has_many :posts, belongs_to
- [ ] `fixtures/rails_project/app/models/post.rb`: Create model fixture with belongs_to :user, has_many :comments
- [ ] `fixtures/rails_project/app/models/comment.rb`: Create model fixture with belongs_to :post, belongs_to :user
- [ ] `templates/c4_context_template.erb`: System context diagram Mermaid template — external systems (git, filesystem, developer) and the documented system
- [ ] `templates/c4_container_template.erb`: Container diagram Mermaid template — internal modules as containers with data flow edges
- [ ] `templates/class_diagram_template.erb`: Class diagram Mermaid template — `classDiagram` with inheritance (`<|--`), includes, extends relationships
- [ ] `templates/erd_template.erb`: ERD Mermaid template — `erDiagram` with tables, typed columns, and relationship lines
- [ ] `templates/architecture_template.erb`: Architecture markdown template — System Overview, Architecture Style, Module Map, Data Flow, Design Decisions, Links to diagrams

#### Frontend Work Items
N/A

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | SchemaParser.parse with valid schema.rb fixture | Returns array of tables with typed columns, indexes, foreign keys |
| Unit | SchemaParser.parse with no schema.rb | Returns empty array |
| Unit | SchemaParser.parse with empty schema.rb | Returns empty array |
| Unit | ModelAssociationParser.parse with Rails models | Returns associations with correct types and targets |
| Unit | ModelAssociationParser.parse with no models directory | Returns empty array |
| Unit | ModelAssociationParser table name inference | User → users, AdminUser → admin_users |
| Unit | ModelAssociationParser with self.table_name override | Uses overridden table name |

### Verification Criteria
- [ ] `bundle exec rspec spec/auto_doc/analyzer/schema_parser_spec.rb` — all tests pass
- [ ] `bundle exec rspec spec/auto_doc/analyzer/model_association_parser_spec.rb` — all tests pass
- [ ] All 5 templates exist in `templates/` and render valid Mermaid/ERB syntax
- [ ] SchemaParser returns correct structure: `[{table_name: "users", columns: [{name: "id", type: :integer, null: false, default: nil}]}]`

---

## Milestone 2: Smart Architecture Generators

**Intent:** Build the four new generators (C4DiagramGenerator, ClassDiagramGenerator, ERDGenerator, ArchitectureGenerator) using the templates from M1. Each follows the existing DiagramGenerator pattern: class method `.generate`, instance method `#generate`, `TEMPLATES_DIR`, `DEFAULT_TEMPLATE`, ERB rendering, optional `output_path` file writing. All generators handle empty/edge case gracefully.

### Implementation

#### Backend Work Items
- [ ] `lib/auto_doc/generator/c4_diagram_generator.rb`: Generates context and container Mermaid diagrams. `.generate_context(project_name, external_systems, internal_system, output_path:)` and `.generate_container(project_name, modules, data_flows, output_path:)` class methods. Uses `c4_context_template.erb` and `c4_container_template.erb`.
- [ ] `lib/auto_doc/generator/class_diagram_generator.rb`: Generates Mermaid `classDiagram`. `.generate(project_name, class_hierarchy, output_path:)` where class_hierarchy is `[{name:, parent:, includes: [], extends: []}]`. Detects inheritance from SourceParser output. Uses `class_diagram_template.erb`.
- [ ] `lib/auto_doc/generator/erd_generator.rb`: Combines SchemaParser + ModelAssociationParser output into Mermaid `erDiagram`. `.generate(project_name, tables, relationships, output_path:)` where tables come from SchemaParser and relationships from ModelAssociationParser. Uses `erd_template.erb`.
- [ ] `lib/auto_doc/generator/architecture_generator.rb`: Generates `.docs/architecture.md`. `.generate(project_name, schema_tables, models, class_hierarchy, config, output_path:)` with sections for System Overview, Architecture Style (detected), Module Map, Data Flow, Design Decisions, Links. Uses `architecture_template.erb`.
- [ ] `spec/auto_doc/generator/c4_diagram_generator_spec.rb`: Test context diagram output (node labels, external system nodes, generated timestamp), container diagram output (module nodes, edges), empty data handling (no external systems, no modules), file writing via output_path
- [ ] `spec/auto_doc/generator/class_diagram_generator_spec.rb`: Test classDiagram output (inheritance arrows, class nodes, includes), empty hierarchy handling
- [ ] `spec/auto_doc/generator/erd_generator_spec.rb`: Test erDiagram output (table definitions, column types, relationship lines), empty tables handling, missing associations handling
- [ ] `spec/auto_doc/generator/architecture_generator_spec.rb`: Test architecture.md output (all required sections present, architecture style detected, links to diagrams), empty project handling (no schema, no models)

#### Frontend Work Items
N/A

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | C4DiagramGenerator.generate_context with external systems | Mermaid graph with system node and external system nodes |
| Unit | C4DiagramGenerator.generate_container with modules | Mermaid graph with container nodes and edges |
| Unit | C4DiagramGenerator with empty data | Valid skeleton with title and generated timestamp |
| Unit | ClassDiagramGenerator.generate with hierarchy | classDiagram with inheritance arrows |
| Unit | ClassDiagramGenerator.generate with includes | classDiagram with <<include>> or class members |
| Unit | ClassDiagramGenerator with empty hierarchy | Valid empty classDiagram |
| Unit | ERDGenerator.generate with tables and relationships | erDiagram with table definitions and relationship lines |
| Unit | ERDGenerator with no relationships | erDiagram with tables only, no relationship lines |
| Unit | ArchitectureGenerator.generate with full data | All sections present, valid markdown |
| Integration | ArchitectureGenerator links to all diagram files | Referenced diagram paths match expected output paths |

### Verification Criteria
- [ ] `bundle exec rspec spec/auto_doc/generator/c4_diagram_generator_spec.rb` — all pass
- [ ] `bundle exec rspec spec/auto_doc/generator/class_diagram_generator_spec.rb` — all pass
- [ ] `bundle exec rspec spec/auto_doc/generator/erd_generator_spec.rb` — all pass
- [ ] `bundle exec rspec spec/auto_doc/generator/architecture_generator_spec.rb` — all pass
- [ ] All generators follow the same pattern as DiagramGenerator (TEMPLATES_DIR, DEFAULT_TEMPLATE, .generate class method)
- [ ] All generators handle empty/edge cases without raising exceptions

---

## Milestone 3: Wiring into Orchestrator and Entry Point

**Intent:** Wire the new analyzers, generators, and output files into the orchestrator (after the existing DAG generation step) and register all new modules in `auto_doc.rb`. Update the top-level spec to verify new modules load. Run the full test suite to confirm zero regressions.

### Implementation

#### Backend Work Items
- [ ] `lib/auto_doc/orchestrator.rb`: After existing DAG generation (~line 114), add:
  - Rails detection: `File.exist?(File.join(target_dir, "db/schema.rb"))`
  - If Rails: call `SchemaParser.parse(target_dir)` and `ModelAssociationParser.parse(target_dir)`
  - Save `schema.json` and `models.json` to `.docs/schema/` directory
  - Generate `class_diagram.mmd` using SourceParser analyses data (always, Rails or not)
  - Generate `erd.mmd` (if schema tables found)
  - Generate `c4_context.mmd` and `c4_container.mmd` (always, uses detected module structure)
  - Generate `architecture.md` to `.docs/architecture.md`
  - Add `schema_tables` and `models` keys to the returned structured hash
  - Use `wrapped_say` for all output messages (consistent with existing pattern)
- [ ] `lib/auto_doc.rb`: Add `require_relative` lines for all 6 new modules (2 analyzers + 4 generators) in correct load order
- [ ] `spec/auto_doc_spec.rb`: Update top-level spec assertions to verify new modules are loaded (SchemaParser, ModelAssociationParser, C4DiagramGenerator, ClassDiagramGenerator, ERDGenerator, ArchitectureGenerator)

#### Frontend Work Items
N/A

### Testing
| Test Type | What to Test | Expected Result |
|-----------|-------------|-----------------|
| Unit | auto_doc.rb loads all new modules | All 6 new constants defined |
| Integration | Full test suite (`bundle exec rspec`) | Zero failures, zero regressions |
| Integration | Orchestrator on Rails project fixture | schema.json, models.json, c4_context.mmd, c4_container.mmd, class_diagram.mmd, erd.mmd, architecture.md all created |
| Integration | Orchestrator on non-Rails project | class_diagram.mmd, c4_context.mmd, c4_container.mmd, architecture.md created; no schema/erd output |
| Integration | Returned hash includes schema_tables and models keys | Hash keys present, nil for non-Rails projects |

### Verification Criteria
- [ ] `bundle exec rspec` — full test suite passes with 0 failures
- [ ] `bundle exec rspec spec/auto_doc_spec.rb` — all 6 new modules verified as loadable constants
- [ ] Orchestrator correctly detects Rails vs non-Rails projects (conditional generation works)
- [ ] All output files go to correct directories: `.docs/diagrams/` for .mmd files, `.docs/schema/` for JSON, `.docs/architecture.md`
- [ ] Output matches existing `wrapped_say` pattern (green "Created" messages)
