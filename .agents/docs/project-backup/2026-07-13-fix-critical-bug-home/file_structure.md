# File Structure: Fix FileTreeBuilder Exclusion Crash

## Current State

```
auto-doc-tool/
├── exe/
│   └── auto-doc                          (unchanged — CLI entry point)
├── lib/
│   └── auto_doc/
│       ├── version.rb                    (unchanged)
│       ├── cli.rb                        (unchanged — command dispatch)
│       ├── config.rb                     (unchanged — previously fixed)
│       ├── document_generator.rb         (unchanged)
│       ├── yard_reader.rb                (unchanged — previously fixed)
│       └── utils/
│           ├── file_tree_builder.rb      ← MODIFIED (should_exclude? flatten fix)
│           └── ...                       (unchanged)
├── fixtures/
│   ├── sample_ruby_project/              (unchanged — verification target)
│   │   ├── lib/
│   │   │   └── sample.rb
│   │   └── ...
│   └── minimal_gem/                      (unchanged — verification target)
│       ├── lib/
│       │   └── minimal.rb
│       └── ...
├── .autodoc/                             (generated output — created by generate)
│   ├── AGENTS.md
│   ├── README.md
│   └── diagrams/
│       └── deps.mmd
├── README.md                             (unchanged)
└── ...
```

## Proposed

```
auto-doc-tool/
├── exe/
│   └── auto-doc                          (unchanged)
├── lib/
│   └── auto_doc/
│       ├── version.rb                    (unchanged)
│       ├── cli.rb                        (unchanged)
│       ├── config.rb                     (unchanged)
│       ├── document_generator.rb         (unchanged)
│       ├── yard_reader.rb                (unchanged)
│       └── utils/
│           ├── file_tree_builder.rb      ← MODIFIED: should_exclude? now flattens
│           │                               patterns and skips non-strings before
│           │                               calling File.fnmatch
│           └── ...                       (unchanged)
├── fixtures/
│   ├── sample_ruby_project/              (unchanged)
│   └── minimal_gem/                      (unchanged)
├── .autodoc/                             (generated output)
│   ├── AGENTS.md
│   ├── README.md
│   └── diagrams/
│       └── deps.mmd
├── README.md                             (unchanged)
└── ...
```

## Change Summary

| File | Status | Change |
|------|--------|--------|
| `lib/auto_doc/utils/file_tree_builder.rb` | MODIFIED | `should_exclude?` method: flatten `@exclusion_patterns` before iterating; skip non-String entries before calling `File.fnmatch` |
| All other files | UNCHANGED | No modifications |

## Module Hierarchy

```
AutoDoc::Utils::FileTreeBuilder
├── initialize(root_path, exclusion_patterns = [])  — unchanged signature
├── build_tree                                       — unchanged, calls should_exclude?
├── should_exclude?(file_path)                       ← MODIFIED: flatten + type guard added
└── collect_files(dir)                               — unchanged, uses should_exclude?
```

## File Change Scope

**Single file modified:** `lib/auto_doc/utils/file_tree_builder.rb`

**Change location:** The `should_exclude?` method

**Change description:** Two guard operations added before `File.fnmatch`:
1. Flatten `@exclusion_patterns` to collapse nested arrays
2. Skip entries that are not Strings (`next unless pattern.is_a?(String)`)

**No other files touched.** Satisfies NFR-1 (minimal change) and NFR-2 (no ripple effects).
