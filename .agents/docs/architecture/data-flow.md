# Data Flow

## Generate Pipeline

```
CLI (generate)
  → Orchestrator.generate(project_dir, say, output_format)
    → Config.load(project_dir)
    → SourceParser.analyze_file(path) × N files
    → ImportExtractor.extract(path) × N files
    → YardReader.extract(path) × N files
    → [Optional] SchemaParser.parse(schema_path)  (Rails only)
    → [Optional] ModelAssociationParser.parse(project_dir)  (Rails only)
    → DiagramGenerator.generate(analysis, output_dir, config)
    → ERDGenerator.generate(analysis, output_dir, config)  (if Rails)
    → C4DiagramGenerator.generate(analysis, output_dir, config)  (if Rails)
    → ClassDiagramGenerator.generate(analysis, output_dir, config)  (if Rails)
    → ArchitectureGenerator.generate(analysis, output_dir, config)  (if Rails)
    → IndexGenerator.generate(modules, output_dir)
    → SummaryGenerator.generate(modules, output_dir)
    → VectorGenerator.generate_project(definitions, output_dir)
    → VectorGenerator.generate_directory(module, output_dir)  × N module roots
    → walk_subdirectories(output_dir, target_dir, modules, definitions, all_analyses)
    → ReadmeGenerator.generate(modules, analysis, output_dir, project_dir)
    → [output_format == :agent] → OutputFormatter.format(agents, :agents)
    → [output_format == :agent] → OutputFormatter.format(index, :index)
    → OutputFormatter.format(summary, :summary)
    → OutputFormatter.format(vectors_json, :vectors_json)
    → OutputFormatter.format(readme, :readme)
```

## Audit Pipeline

```
CLI (audit)
  → Orchestrator.audit(project_dir, say, output_format, threshold)
    → SourceParser.analyze_file(path) × N files
    → ImportExtractor.extract(path) × N files
    → YardReader.extract(path) × N files
    → CompletenessChecker.check_coverage(definitions, docs)
    → AuditReporter.generate(analysis, definitions)
    → [output_format == :json || :agent] → OutputFormatter.format(report)
    → AuditReporter.write_report(analysis, definitions, report, output_path)
```

## Diff Pipeline

```
CLI (diff)
  → DiffService.run(project_dir, since)
    → git diff --name-only since -- '*.rb'  (shell out)
    → SourceParser.analyze_file(changed_path) × N changed
    → YardReader.extract(changed_path) × N changed
    → find_undocumented(analyses)
    → OutputFormatter.format(changes, :diff)  (if :json || :agent)
```

## Orphans Pipeline

```
CLI (orphans)
  → OrphansService.run(project_dir)
    → collect_ruby_files(project_dir)
    → build_import_map(ruby_files)  (ImportExtractor × N)
    → build_referenced_set(import_map)
    → build_documented_set(ruby_files)  (YardReader × N)
    → orphans = files - referenced - documented
    → OutputFormatter.format(orphans, :orphans)  (if :json || :agent)
```

## Search Data Flow

```
SearchService.search(project_dir, query, index)
  → IndexManager.read(project_dir)  (reads INDEX.md files)
  → IndexManager.read(project_dir, "SUMMARY.md")  (reads SUMMARY.md files)
  → IndexManager.read_vector_index(project_dir)  (reads vectors.json)
  → source_grep(project_dir, query)  (grep across .rb files)
  → For each index entry:
    - symbol_exact match → score += 100
    - dependency_match → score += 60
    - summary_text match → score += 40
    - vector_keyword_high → score += 30
    - vector_keyword_low → score += 10
    - source_grep hit → score += 10
  → Sort by score descending, cap at max_results
  → Return ranked results
```

## Server Request Lifecycle

```
HTTP Request → Sinatra Router → Server#handle_request(path)
  → path == "/" → Server#directory_listing(base_dir, path) → Markdown.render
  → path == "/search" (POST) → SearchService.search(project_dir, query) → JSON
  → path == "/search/expand" (POST) → IndexManager.expand(path) → JSON
  → else → File.read(path) → Markdown.render
```

## Write Path

All generators follow the same write pattern:

1. `TemplateHelper.read_template(TEMPLATES_DIR + DEFAULT_TEMPLATE)` — loads ERB template
2. Render template with analysis data
3. Write to disk (or return string if `output_path` not provided)

When `output_format` is `:agent`, `OutputFormatter.format(data, mode)` is called before writing:
- `:text` → Human-readable formatted output (via `say.call`)
- `:json` → `JSON.pretty_generate(data)` 
- `:agent` → Compact JSON with timestamps and noise removed

## File Tree Generation

```
FileTreeBuilder.build_tree(dir)
  → Dir.entries(dir).sort.each
  → For each entry:
    - If directory: recurse (depth + 1)
    - If file: append with spacing based on depth
  → Return joined string with tree characters (├──, └──, │)
```

## Manifest-Based Incremental Detection

```
TimestampTracker.load_manifest(output_dir)
  → File.exist?(manifest_path) ? JSON.load_file(manifest_path) : {}

# In Orchestrator.walk_subdirectories:
TimestampTracker.track_write(file_path, timestamp)
  → manifest[relative] = File.stat(file_path).mtime.to_i

TimestampTracker.files_needing_rewrite(output_dir, target_dir, manifest)
  → For each dir in target_dir:
    - Dir.glob(dir + "/*.md") × N
    - Compare each file's mtime against manifest[relative]
    - If no manifest entry OR mtime > manifest, mark as needing rewrite
  → Returns { dir: [new_or_changed_files...] }
```