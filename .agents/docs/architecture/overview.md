# Auto-Doc Tool — Architecture Overview

## Purpose

Auto-Doc is a Ruby gem that automates documentation generation for Ruby projects. It analyzes source code to extract symbol metadata (classes, modules, methods, constants), generates structured documentation artifacts (INDEX.md, SUMMARY.md, AGENTS.md, vectors.json, diagrams), and provides multi-strategy search across all generated and source files.

## Project Structure

```
auto-doc/
├── exe/auto-doc                  # CLI entry point (Thor)
├── lib/auto_doc.rb               # Main gem entry, requires all submodules
├── lib/auto_doc/
│   ├── cli.rb                    # Thor-based CLI (generate, audit, search, server, test)
│   ├── config.rb                 # Configuration loader (.autodoc.yml with fallback defaults)
│   ├── server.rb                 # Sinatra server for serving generated docs
│   ├── documentation_index.rb    # Unified data-access layer for .docs/ artifacts
│   ├── search_service.rb         # Multi-strategy ranked search engine
│   ├── agent_query_service.rb    # Agent-facing query abstraction
│   ├── transformer.rb            # Markdown transformation utilities
│   ├── errors.rb                 # Custom error types
│   ├── version.rb                # Gem version
│   ├── llm/                      # LLM integration submodule
│   │   ├── client.rb             # OpenAI-compatible HTTP client (Net::HTTP)
│   │   ├── summarizer.rb         # LLM summarization coordinator
│   │   ├── prompt_builder.rb     # Prompt construction for all LLM use cases
│   │   ├── response_parser.rb    # Response parsing (markdown, JSON, bullet lists)
│   │   └── enricher.rb           # Pre-processing enrichment of analyses with LLM summaries
│   ├── analyzer/                 # Source code analysis submodule
│   │   ├── analysis_pipeline.rb  # Entry point: file globbing → parsing → YARD
│   │   ├── analysis_cache.rb     # In-process analysis caching
│   │   ├── source_parser.rb      # Ruby syntax parser
│   │   ├── yard_reader.rb        # YARD documentation extraction
│   │   ├── schema_parser.rb      # Database schema detection
│   │   ├── model_association_parser.rb  # ActiveRecord association detection
│   │   ├── import_extractor.rb   # require/include/extend/prepend extraction
│   │   ├── generic_scanner.rb    # Multi-language file type detection
│   │   ├── diff_service.rb       # Incremental analysis change detection
│   │   └── orphans_service.rb    # Undocumented symbol detection
│   ├── generator/                # Documentation artifact generation
│   │   ├── index_generator.rb
│   │   ├── summary_generator.rb
│   │   ├── vector_generator.rb   # VECTORS.json generation with keyword search support
│   │   ├── agents_md_generator.rb
│   │   ├── readme_generator.rb
│   │   ├── architecture_generator.rb
│   │   ├── diagram_generator.rb
│   │   ├── c4_diagram_generator.rb
│   │   ├── class_diagram_generator.rb
│   │   ├── erd_generator.rb
│   │   ├── agents_overview_generator.rb
│   │   ├── map_generator.rb
│   │   └── template_helper.rb
│   ├── orchestrator/             # Pipeline orchestration
│   │   ├── pipeline.rb           # 7-step generation pipeline
│   │   ├── base_step.rb          # Step base class
│   │   ├── index_summary_vectors_step.rb  # INDEX/SUMMARY/vectors.json generation
│   │   ├── agents_md_step.rb
│   │   ├── agents_overview_step.rb
│   │   ├── readme_step.rb
│   │   ├── diagram_step.rb
│   │   ├── architecture_step.rb
│   │   ├── manifest_step.rb
│   │   └── metrics_helper.rb
│   ├── reporter/                 # Audit and completeness reporting
│   │   ├── audit_reporter.rb
│   │   └── completeness_checker.rb
│   ├── tester/                   # E2E test runner
│   │   └── e2e_runner.rb
│   ├── utils/                    # Shared utilities
│   │   ├── yaml_config_loader.rb
│   │   ├── file_tree_builder.rb
│   │   ├── timestamp_tracker.rb  # Incremental analysis change tracking
│   │   ├── output_formatter.rb
│   │   └── markdown_helper.rb
│   └── transformer/              # Markdown transformation steps
│       ├── files_data_builder.rb
│       ├── class_hierarchy_builder.rb
│       ├── container_data_flow_builder.rb
│       ├── erd_relationship_builder.rb
│       └── graph_data_builder.rb
├── spec/                         # RSpec test suite (832 examples)
│   ├── spec_helper.rb
│   ├── support/llm_mock_helper.rb
│   ├── auto_doc/
│   ├── e2e/
│   └── scripts/
└── templates/                    # ERB templates for generated docs
```

## Design Principles

1. **Modular, composable pipeline** — The `Orchestrator::Pipeline` runs discrete steps (AgentsOverview → AgentsMd → Readme → IndexSummaryVectors → Diagram → Architecture → Manifest), each operating on a shared context hash.
2. **Analysis-first, generation-second** — Source code is analyzed once into a structured `analyses` hash (definitions, docs, imports per file), then consumed by all downstream generators.
3. **LLM as optional enrichment** — LLM-powered summarization is gated behind `config.llm_primary?` and `AUTO_DOC_DISABLE_LLM`. When disabled, the pipeline produces the same artifacts minus LLM-generated summaries.
4. **Additive feature design** — New features (Enricher pre-processing) are additive: they don't modify existing behaviors but insert new capabilities into the pipeline.
5. **Multi-strategy search** — Search ranks results across multiple sources (vectors keywords, vector summaries, INDEX.md, SUMMARY.md, AGENTS.md, source grep) with configurable scores.

## Domain Model Summary

The core domain data flow:

```
Source Files → AnalysisPipeline → analyses hash
                                        │
                                        ├→ Enricher.enrich_analyses (LLM summaries → docs arrays)
                                        │
                                        └→ Pipeline.steps → Documentation artifacts
                                               │
                                               ├→ INDEX.md (symbol index per directory)
                                               ├→ SUMMARY.md (module overview)
                                               ├→ AGENTS.md (detailed API docs)
                                               ├→ VECTORS.json (keyword-indexed symbol entries)
                                               ├→ Diagrams (mermaid .mmd files)
                                               ├→ Architecture.md
                                               └→ Manifest.json
```

### Key Data Structures

**`analyses`** — Hash of `file_path => { definitions: [...], docs: [...], imports: [...] }` where each definition is a Hash with `:name`, `:type`, `:line`, `:has_doc?`, `:signature`, `:visibility`, `:dependencies`, `:parent_module`.

**Vector entry** — Generated for each symbol with fields: `id`, `symbol`, `type`, `scope`, `file`, `line`, `summary`, `signature`, `visibility`, `keywords`, `dependencies`, `consumed_by`, `parent_module`.

## Deviations from Plan

The project plan specified 5 milestones (Enricher creation, Orchestrator wiring, VectorGenerator keyword merge, SearchService summary search, E2E verification). All milestones were completed as planned with no skipped features.

**Intentional deviations from the original Hypothesis 1 plan:**

- **Keyword merging in `keyword_extraction`**: The plan specified merging name + summary keywords in `keyword_extraction`. The actual implementation passes `summary` (from docs array) to `keyword_extraction` when a summary exists, but uses `extract_keywords_from_text(llm_summary_text)` directly for the legacy `llm_summaries` path. This preserves backward compatibility with the existing `llm_summaries` flow while adding summary-based keyword merging to the new `docs` array path.

- **Orchestrator always calls Enricher**: The plan suggested guarding Enricher calls in the orchestrator with `@config.respond_to?(:llm_primary?) && @config.llm_primary?`. The actual implementation always calls `Enricher.enrich_analyses` unconditionally — the guard is deferred inside `Enricher.enrich_analyses` itself (line 19: `return analyses unless config.llm_primary?`). This simplifies the orchestrator and keeps the LLM gate localized.

- **`grep_md_file` removal from SearchService**: The remediation removed dead code `grep_md_file` from `search_service.rb` (31 lines). This was not in the original plan but was required to pass review.

- **`collect_symbol_summaries` extracted to `BaseStep`**: The plan described `agents_md_step.rb` as collecting LLM summaries "similar to `collect_symbol_summaries` in `index_summary_vectors_step`", implying a duplicated implementation. Instead, the M3-R remediation extracted `collect_symbol_summaries` into `BaseStep` as a shared protected method, making both `AgentsMdStep` and `IndexSummaryVectorsStep` inherit it. This is DRY and ensures consistent behavior across all steps.

- **LLM summaries flow via `FilesDataBuilder`**: The plan described accepting `llm_summaries` as a separate parameter in `AgentsMdGenerator.build_public_symbols`. The actual implementation passes `llm_summaries` through `FilesDataBuilder.build(analyses, llm_summaries)`, which injects `:llm_summary` into each definition hash. This keeps the data transformation centralized in the transformer submodule rather than scattered across generators.