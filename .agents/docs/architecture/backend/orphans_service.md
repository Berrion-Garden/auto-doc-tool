# OrphansService

## Class: `AutoDoc::Analyzer::OrphansService`

**File:** `lib/auto_doc/analyzer/orphans_service.rb`

### Purpose

Finds Ruby files that are not documented, not imported by any other file, and not referenced by any other file in the project. Called by the `auto-doc orphans` CLI subcommand.

### Constructor

```ruby
def initialize(project_dir, say: method(:puts))
  @project_dir = project_dir
  @say         = say
end
```

### API

```ruby
result = OrphansService.run(project_dir, say: method(:puts))
# Returns: Hash with :orphans array of relative file paths

# Instance method
result = OrphansService.new(project_dir, say: method(:puts)).run
# Returns: Hash
```

### Return Value

```ruby
{
  orphans: ["lib/orphan_file.rb", "app/unused.rb"]
  # Sorted array of relative file paths
}
```

### `run`

1. Outputs status message via `@say.call("Scanning for orphan files in #{@project_dir}...", :green)`.
2. Collects Ruby files via `collect_ruby_files` (respects config exclude patterns).
3. Returns early if no files found.
4. Builds import map via `build_import_map`.
5. Builds referenced set via `build_referenced_set`.
6. Builds documented set via `build_documented_set`.
7. Orphans = files NOT referenced AND NOT documented.
8. Returns `{ orphans: orphans.sort }`.

### `collect_ruby_files`

1. Loads config for exclude patterns.
2. Globs `**/*.rb` from project dir.
3. Rejects files matching exclude patterns via `File.fnmatch?`.
4. Returns relative file paths.

### `build_import_map(ruby_files)`

For each file, calls `ImportExtractor.extract(file_path)` and builds `{ file_path => [imports...] }` map.

### `build_referenced_set(import_map)`

Flattens all import targets from the import map into a `Set`. A file is "referenced" if it appears as an import target in any other file.

### `build_documented_set(ruby_files)`

For each file, calls `YardReader.extract(file_path)`. Adds the file to the set if any doc record has `has_summary? == true`.

### Orphan Logic

```ruby
orphans = ruby_files.reject { |f| referenced.include?(f) || documented.include?(f) }
```

A file is an orphan if it is neither:
- Imported/referenced by another file, AND
- Documented (has a YARD doc summary on its primary class/module)

### Edge Cases

- If a file has a doc comment but the symbol isn't a class/module/method (e.g., standalone comment), it may still be orphaned.
- Import detection relies on `ImportExtractor` which parses `require`, `require_relative`, `include`, `extend` statements — files referenced only by constants (not explicit imports) won't be detected as referenced.
- Uses `Set` for O(1) lookups in the referenced check.