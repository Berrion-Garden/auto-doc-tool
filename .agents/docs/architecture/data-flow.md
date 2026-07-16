# Auto-Doc Tool — Request Lifecycle & Data Flow

## Generation Request Lifecycle

```
CLI (exe/auto-doc generate)
    │
    ├→ Orchestrator#generate(path, say:)
    │     │
    │     ├→ Config.load(target_dir, cli_overrides)
    │     │
    │     ├→ resolve_module_roots(target_dir, config)
    │     │
    │     ├→ analyze_project(target_dir, config, file_list)
    │     │     │
    │     │     ├→ AnalysisCache.fetch(base_dir, config) { ... }  # in-process cache
    │     │     │     │
    │     │     │     └→ run_analysis_pipeline(base_dir, excludes, file_list)
    │     │     │           │
    │     │     │           ├→ Source files globbed (**/*.rb, etc.)
    │     │     │           ├→ AnalysisPipeline.run(source_files) → analyses
    │     │     │           │     │
    │     │     │           │     └→ For each file:
    │     │     │           │           SourceParser.parse → definitions
    │     │     │           │           YardReader.read → docs
    │     │     │           │           GenericScanner.detect → language
    │     │     │           │
    │     │     │           └→ For each file:
    │     │     │                 ImportExtractor.extract → imports
    │     │     │
    │     │     └→ Returns: { file_path => { definitions, docs, imports, language } }
    │     │
    │     ├→ Enricher.enrich_analyses(analyses, config, base_dir: target_dir)
    │     │     │
    │     │     ├→ Guard: config.llm_primary? → return analyses unchanged if false
    │     │     ├→ Client.build_if_configured(config) → nil if LLM unavailable
    │     │     ├→ Build symbol_types lookup (name → type)
    │     │     ├→ For each module root:
    │     │     │     ├→ Filter analyses by root (start_with? matching)
    │     │     │     ├→ Summarizer.summarize_symbols(root, filtered, client) → LLM response
    │     │     │     ├→ ResponseParser.parse_symbol_summaries(response, symbol_types)
    │     │     │     └→ For each parsed summary:
    │     │     │           analyses[file_path][:docs] << {target_name, target_type, summary}
    │     │     │
    │     │     └→ Returns: enriched analyses (same hash, mutated)
    │     │
    │     ├→ Pipeline.new(config).run(analyses, ...)
    │     │     │
    │     │     └→ For each step in STEPS (7 steps):
    │     │           step.run(context)
    │     │           │
    │     │           └→ Context evolves with shared state:
    │     │                 analyses → enriched analyses hash
    │     │                 all_classes, all_methods, coverage_pct → counts
    │     │                 schema_tables, models → detected data
    │     │
    │     └→ Return: { project, output_dir, module_roots, analyses_count,
    │                    classes_count, methods_count, coverage_pct, generated_at,
    │                    schema_tables, models, created_files }
    │
    └→ CLI formatting / exit
```

## Vector Entry Data Flow

```
Source file → AnalysisPipeline → analyses[:docs] (YARD docs)
                                         │
                              Enricher.enrich_analyses
                                         │
                              analyses[:docs] += {target_name, target_type, summary}
                                         │
                              IndexSummaryVectorsStep.collect_symbol_summaries
                                         │
                              llm_summaries hash = { entry_id => summary }
                                         │
                    ┌────────────────────┼────────────────────┐
                    │                                                    │
          build_vectors(analyses, llm_summaries:)              generate_project/dir()
                    │                                                    │
          For each defn in analyses:             For each file → build_doc_index(docs)
          build_vector_entry(defn, ...)          For each defn: build_vector_entry(...)
                    │                                                    │
          Inside build_vector_entry:     Inside build_vector_entry:
          ┌─────────────────────────┐    ┌─────────────────────────────────┐
          │ doc_index lookup        │    │ doc_index lookup                │
          │ → doc_rec[:summary]     │    │ → doc_rec[:summary]             │
          └─────────────────────────┘    └─────────────────────────────────┘
          │                              │
          │ llm_summaries[entry_id]     │ summary (from docs)
          │ passed to...                │ passed to keyword_extraction
          └──────────┬──────────────────┘
                     │
          ┌──────────┴──────────────────┐
          │                             │
    extract_keywords_from_text     keyword_extraction(name, summary)
    (llm_summary_text)             (merges name + summary keywords)
          │                             │
          └──────────┬──────────────────┘
                     │
          keywords array (up to 15, deduplicated)
                     │
          Vector entry written to vectors.json
```

## Search Request Flow

```
SearchService.search(project_dir, term, options: {source: true, limit: 20})
    │
    ├→ DocumentationIndex.new(docs_dir)
    │     │
    │     └→ Loads: INDEX.md, VECTORS.json, SUMMARY.md, AGENTS.md, all markdown content
    │
    ├→ search_index_md(doc_index, term)
    │     ├→ Symbol exact matches (score 100)
    │     └→ Dependency partial matches (score 80)
    │
    ├→ search_vectors_json(doc_index, term)
    │     ├→ First pass: keyword overlap (score 60 for 3+, 40 for 1-2)
    │     │     search_words = term.split(/\s+|_|CamelCase/) → lowercase
    │     │     overlap = search_words.count { |w| keyword_words.include?(w) }
    │     │
    │     └→ Second pass: summary full-text match (score 15)
    │           search_words.any? { |w| summary.downcase.include?(w) }
    │           match_type: "vector_summary_match"
    │
    ├→ search_summary_md(doc_index, term)    (score 20)
    └→ search_agents_md(doc_index, term)      (score 20)
    └→ search_source_files(project_dir, term) (score 10, opt-in)
    │
    ├→ results.sort_by! { |r| -r[:score] }
    └→ results.first(limit)
    │
    └→ { query: term, results: [...], total: n }
```

## Incremental Analysis Flow

```
Orchestrator#generate(path, options: {incremental: true})
    │
    ├→ TimestampTracker.stale_files(target_dir, output_dir)
    │     │
    │     └→ Compares current file mtimes against stored timestamps
    │         Returns array of changed file paths
    │
    ├→ analyze_project(target_dir, config, stale_files)
    │     │
    │     └→ Run analysis ONLY on stale files (not cached)
    │
    └→ Enricher.enrich_analyses + Pipeline run on partial analyses
```

## Error Handling & Guard Chains

Every LLM call is protected by a multi-layer guard:

1. **Env guard:** `AUTO_DOC_DISABLE_LLM` → Client.build_if_configured returns nil
2. **Config guard:** `config.llm_primary?` → Enricher returns analyses unchanged
3. **Client guard:** `Client.build_if_configured(config)` → nil if no valid config
4. **Response guard:** LLM returns nil → Enricher logs warning, skips that module
5. **Parse guard:** ResponseParser returns empty hash → Enricher skips that module

This ensures the pipeline always completes even when the LLM is unavailable.