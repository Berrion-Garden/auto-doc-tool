# Architecture: Fix FileTreeBuilder Exclusion Crash

## C4 System Context

```
┌──────────┐         ┌──────────────────────┐         ┌──────────────┐
│          │  runs   │                      │  reads  │              │
│ CLI User │────────▶│   Auto-Doc CLI Gem   │────────▶│  Source Code │
│          │         │                      │         │  Directories │
└──────────┘         └──────────────────────┘         └──────────────┘
                              │
                              │ writes
                              ▼
                     ┌────────────────┐
                     │  .autodoc/     │
                     │  AGENTS.md     │
                     │  README.md     │
                     │  deps.mmd      │
                     └────────────────┘
```

**Users:** CLI User — a developer running `auto-doc generate`, `auto-doc init`, or `auto-doc version` from a terminal.

**System:** Auto-Doc CLI Gem — reads Ruby source files from a directory tree, generates developer documentation (AGENTS.md, README.md, dependency diagrams) into a `.autodoc/` output directory.

## C4 Container Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                        Auto-Doc CLI Gem                           │
│                                                                   │
│  ┌──────────────────┐    ┌───────────────────────────────────┐   │
│  │  CLI Entry Point │    │  Generate Command                  │   │
│  │  (exe/auto-doc)  │───▶│  - Parses path & options           │   │
│  │                  │    │  - Orchestrates full pipeline       │   │
│  └──────────────────┘    └──────────┬────────────────────────┘   │
│                                     │                             │
│               ┌─────────────────────┼─────────────────────┐      │
│               │                     │                     │      │
│               ▼                     ▼                     ▼      │
│  ┌────────────────────┐ ┌──────────────────┐ ┌────────────────┐  │
│  │  FileTreeBuilder   │ │  YardReader      │ │  Doc Writers   │  │
│  │  - build_tree()    │ │  - extract()     │ │  - AGENTS.md   │  │
│  │  - should_exclude? │ │  - analyze deps  │ │  - README.md   │  │
│  │  - collect_files() │ │                  │ │  - deps.mmd    │  │
│  └────────┬───────────┘ └──────────────────┘ └────────────────┘  │
│           │                                                        │
│           │ reads directory structure                              │
│           ▼                                                        │
│  ┌────────────────────┐                                           │
│  │  File System       │                                           │
│  │  (source dirs,     │                                           │
│  │   output dirs)     │                                           │
│  └────────────────────┘                                           │
│                                                                   │
│  ┌──────────────────┐    ┌───────────────────────────────────┐   │
│  │  Init Command    │    │  Version Command                  │   │
│  │  - sets up dir   │    │  - prints AutoDoc::VERSION        │   │
│  │  - no FileTree   │    │  - no FileTreeBuilder involved    │   │
│  │    Builder usage │    │                                   │   │
│  └──────────────────┘    └───────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

**Key observation:** Only the Generate Command uses FileTreeBuilder. Init and Version are independent — they cannot be affected by file_tree_builder changes (satisfying FR-3 regression requirement).

## C4 Component: FileTreeBuilder (Zoomed In)

```
┌─────────────────────────────────────────────────────────────────┐
│  FileTreeBuilder                                                 │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  initialize(root_path, exclusion_patterns = [])          │    │
│  │  Stores: @root_path, @exclusion_patterns                 │    │
│  └─────────────────────────────────────────────────────────┘    │
│                              │                                    │
│                              ▼                                    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  build_tree                                              │    │
│  │  Entry point. Calls collect_files(root_path)             │    │
│  │  Returns: directory tree structure                       │    │
│  └──────────────────────────────┬──────────────────────────┘    │
│                                 │                                 │
│                                 ▼                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  collect_files(dir)                                       │    │
│  │  Recursively reads Dir.entries                           │    │
│  │  For each entry: if should_exclude? → skip               │    │
│  │                 if directory? → recurse                  │    │
│  │                 if file? → add to tree                   │    │
│  └──────────────────────────────┬──────────────────────────┘    │
│                                 │                                 │
│                                 ▼                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  should_exclude?(file_path)          ← THE BUG IS HERE   │    │
│  │                                                           │    │
│  │  BEFORE FIX:                                              │    │
│  │    @exclusion_patterns.each do |pattern|                  │    │
│  │      return true if File.fnmatch(pattern, relative_path)  │    │
│  │    end                                                    │    │
│  │  CRASH: If pattern is an Array, fnmatch gets Array→String │    │
│  │                                                           │    │
│  │  AFTER FIX:                                               │    │
│  │    @exclusion_patterns.flatten.each do |pattern|          │    │
│  │      next unless pattern.is_a?(String)                    │    │
│  │      return true if File.fnmatch(pattern, relative_path)  │    │
│  │    end                                                    │    │
│  │                                                           │    │
│  │  Strips root_path prefix. Returns Boolean.                │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow: Generate Command

```
User runs: auto-doc generate <path>
               │
               ▼
CLI parses args: path = "fixtures/sample_ruby_project"
               │
               ▼
GenerateCommand receives path
               │
               ├──▶ FileTreeBuilder.new(path, exclusion_patterns)
               │         │
               │         ├── Does NOT crash: should_exclude? now handles nested arrays
               │         └── Returns tree structure
               │
               ├──▶ YardReader.extract(tree) — reads docs from files
               │
               └──▶ DocumentWriters — produce AGENTS.md, README.md, deps.mmd
                         │
                         ▼
                    .autodoc/ directory created
```

## ADR-001: Flatten Exclusion Patterns Before fnmatch Evaluation

**Status:** Accepted

**Context:** The `should_exclude?` method in FileTreeBuilder iterates `@exclusion_patterns` and passes each element directly to `File.fnmatch`. When exclusion patterns are sourced from configuration files that produce nested arrays (e.g., YAML lists of lists, or merged configs), `File.fnmatch` receives an Array instead of a String and raises `TypeError: no implicit conversion of Array into String`. This crashes the entire `auto-doc generate` pipeline.

**Decision:** Add two guards before the `File.fnmatch` call:
1. Flatten `@exclusion_patterns` to collapse any nested arrays into a single-level array
2. Skip non-String entries with `next unless pattern.is_a?(String)`

**Alternatives considered:**
- **Schema validation at config load time:** Would prevent nested arrays from reaching FileTreeBuilder. Rejected — requires changes in config.rb (violates NFR-1: minimal change, NFR-2: no ripple effects). Also creates a dependency between config and file_tree_builder that shouldn't exist.
- **Recursive flatten in config loader:** Same rejection reason — changes multiple files.
- **Flatten at constructor:** `@exclusion_patterns = exclusion_patterns.flatten`. Simpler, but doesn't guard against non-String types within the flattened array. Rejected — insufficient defense.

**Consequences:**
- Positive: Fixes the crash for all edge cases (nested arrays, mixed types, empty arrays)
- Positive: Zero change to public API — `initialize` signature unchanged, `should_exclude?` return type unchanged
- Positive: Backward compatible — all existing behavior preserved
- Neutral: `.flatten` is called on every `should_exclude?` invocation (performance impact is negligible — pattern arrays are small, typically < 20 entries)
- Negative: None. This is a pure defensive fix.

**Edge case handling:**
| Edge Case | Before Fix | After Fix |
|-----------|-----------|-----------|
| `patterns = ["/lib", ["/test"]]` | TypeError crash | Matches both `/lib` and `/test` |
| `patterns = []` | Returns false (no match) | Returns false (unchanged) |
| `patterns = [nil, 42, "/lib"]` | TypeError on nil or 42 | Skips non-string, matches `/lib` |
| Path equals root (no prefix to strip) | `relative_path = ""` | `fnmatch(pattern, "")` — evaluates correctly |
| Pattern with glob (`**/*.rb`) | Works (passed string) | Works (unchanged) |

## Component Interfaces

### FileTreeBuilder

| Method | Input | Output | Side Effects |
|--------|-------|--------|--------------|
| `initialize(root_path, exclusion_patterns = [])` | `root_path: String`, `exclusion_patterns: Array` | `FileTreeBuilder` instance | None |
| `build_tree` | (none — uses internal state) | Directory tree structure (Hash/Node) | Reads filesystem |
| `should_exclude?(file_path)` | `file_path: String` (absolute) | `Boolean` | None |
| `collect_files(dir)` | `dir: String` | Array of file/dir entries | Reads filesystem recursively |

### Generate Command → FileTreeBuilder

```
GenerateCommand
  │
  ├── FileTreeBuilder.new(path, config.exclusion_patterns)
  │     path: String (absolute path to source directory)
  │     config.exclusion_patterns: Array (may contain nested arrays)
  │
  └── builder.build_tree
        Returns: tree structure passed to YardReader
```

## Anti-Patterns Avoided

- **No multi-file fix:** Only `file_tree_builder.rb` changes. Config validation remains in config layer.
- **No type coercion at boundary:** Patterns are flattened and filtered, not blindly converted via `.to_s` (which would turn `nil` into `""`).
- **No defensive copy in constructor:** Flatten at point of use (in `should_exclude?`) rather than at construction, so the object's internal state reflects what was passed in — only the matching logic is defensive.
