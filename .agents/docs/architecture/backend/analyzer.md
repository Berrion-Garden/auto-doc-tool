# Analyzer Submodule — Backend

## Entry Point

### `analysis_pipeline.rb` — Pipeline Orchestration

Entry point for source code analysis. Accepts an array of file paths, runs each through `SourceParser` and `YardReader`, returns a hash of `file_path => { definitions: [...], docs: [...], language: ... }`.

**Behavior:**
1. Iterates over provided source files
2. Runs `SourceParser.parse(file_path)` for each file (extracts classes, modules, methods, constants, imports)
3. Runs `YardReader.read(file_path)` for YARD doc comment extraction
4. Detects language via `GenericScanner` (Ruby, TypeScript, etc.)
5. Returns structured analysis data

## Core Parsers

### `source_parser.rb` — Ruby Syntax Parser

Parses Ruby source files to extract:
- Classes, modules, methods, constants
- Method signatures
- Visibility (public/private/protected)
- Parent module nesting
- Line numbers

Uses Ruby's `Parser` library for AST-based parsing (more reliable than regex).

### `yard_reader.rb` — YARD Documentation Extraction

Reads YARD doc comments from source files. Extracts:
- Summary text
- Parameter descriptions
- Return type descriptions
- Tags (@param, @return, @example, etc.)

### `schema_parser.rb` — Database Schema Detection

Detects database schema from Rails applications by parsing:
- `db/schema.rb` or `db/schema.sql`
- Migration files

Extracts tables, columns, types, indexes, and foreign keys.

### `model_association_parser.rb` — ActiveRecord Association Detection

Scans Ruby files for ActiveRecord association declarations (`has_many`, `belongs_to`, `has_one`, `has_and_belongs_to_many`). Used for dependency analysis.

## Supporting Services

### `import_extractor.rb` — Import Statement Extraction

Extracts all import/deployment statements from a file:
- `require`
- `require_relative`
- `include`
- `extend`
- `prepend`

Returns a list of import hashes with `:type`, `:target`, `:line`, `:resolved_path` (when resolvable).

### `generic_scanner.rb` — Multi-Language File Detection

Detects the programming language of source files based on file extension. Supports multiple languages beyond Ruby for future extensibility.

Known extensions: Ruby (`.rb`), TypeScript (`.ts`, `.tsx`), JavaScript (`.js`, `.jsx`), Python (`.py`), etc.

### `diff_service.rb` — Incremental Analysis Change Detection

Compares current analysis state against stored state to identify which files have changed and need re-analysis. Used for incremental generation mode.

### `orphans_service.rb` — Undocumented Symbol Detection

Identifies symbols that lack documentation comments. Used by the audit reporter to calculate documentation coverage.

## Caching

### `analysis_cache.rb` — In-Process Analysis Cache

Caches analysis results in-process to avoid re-parsing files across multiple CLI invocations within the same process (e.g., when `verify` + `audit` + `generate` are called in sequence). Cleared between test runs via `spec_helper.rb`.