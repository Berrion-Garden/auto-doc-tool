# Auto-Doc — Analyzer Module

## Purpose

The analyzer module extracts structured information from Ruby source files. It uses the Ruby stdlib `Ripper` for AST-based parsing and custom extraction for YARD doc comments, imports, and Rails-specific metadata.

## Files

### `SourceParser` (`analyzer/source_parser.rb`)

Ripper-based parser that walks Ruby S-expressions to extract class, module, and method definitions.

**Algorithm:**
1. Reads file content and calls `Ripper.sexp(code)`
2. Recursively walks the S-expression tree via `walk_sexp(sexp, current_scope)`
3. Tracks module nesting context for proper scope resolution
4. Handles node types: `:program`, `:class`, `:module`, `:def`, `:defs`, `:sclass`, `:alias`, `:cdecl`, `:const_path_ref`

**Output:** Array of `Definition` hashes:
```ruby
{
  name:           "ClassName",       # Symbol name
  type:           :class,            # :class, :module, :method
  line:           5,                 # Line number
  parent_modules: ["AutoDoc"],      # Nesting context
  methods:        [{ name: "foo", type: :method, line: 10 }]
}
```

**Nesting handling:** Constant paths like `::AutoDoc::Analyzer::Foo` are resolved to `["AutoDoc", "Analyzer"]` parent modules.

### `YardReader` (`analyzer/yard_reader.rb`)

Extracts YARD-style documentation comments from source files.

**Output per comment:**
```ruby
{
  target_name:    "ClassName",
  target_type:    :class,
  summary:        "Description text",
  has_summary?:   true,
  line:           2
}
```

### `ImportExtractor` (`analyzer/import_extractor.rb`)

Extracts dependency declarations from source files: `require`, `require_relative`, `include`, `extend`, `prepend`.

**Output:**
```ruby
{ path: "json", type: :require, line: 1 }
```

### `SchemaParser` (`analyzer/schema_parser.rb`)

Parses Rails `db/schema.rb` files to extract table definitions, columns, types, and constraints. Rails-only — skipped for non-Rails projects.

### `ModelAssociationParser` (`analyzer/model_association_parser.rb`)

Extracts Rails model associations (`belongs_to`, `has_many`, `has_one`, `has_and_belongs_to_many`). Rails-only.

### `AnalysisPipeline` (`analyzer/analysis_pipeline.rb`)

Shared pipeline that combines `SourceParser` and `YardReader` results.

**Workflow:**
1. For each file in the input list:
   a. `SourceParser.parse_file(file_path)` → definitions
   b. `YardReader.extract(file_path)` → docs
   c. Build doc index keyed by `:"#{type}_#{name}"`
   d. Merge `has_doc?` boolean onto each definition
2. Return analyses hash: `{ file_path => { definitions:, docs: } }`

**Note:** Import extraction is NOT included in this pipeline — it is handled separately by the Orchestrator.

### `AnalysisCache` (`analyzer/analysis_cache.rb`)

In-process caching of analysis results. Keyed by directory path + config fingerprint.

**Usage:** `AnalysisCache.fetch(base_dir, config) { ... }` — returns cached results or executes block and caches result.

**Clearing:** `AnalysisCache.clear!` — called before each test to isolate test runs.

**Performance:** Warm cache is ~173x faster than cold cache for a 193-file project.

### `DiffService` (`analyzer/diff_service.rb`)

Compares current source analysis against a git ref (e.g., `HEAD~5`) to identify:
- Changed files
- New or modified symbols
- Undocumented changes (symbols without doc comments in changed files)

### `OrphansService` (`analyzer/orphans_service.rb`)

Finds `.rb` files that are not documented (no AGENTS.md), not imported by other files, and not referenced. Supports `--rails` mode to skip Rails autoloaded paths.