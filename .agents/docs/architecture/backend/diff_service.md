# DiffService

## Class: `AutoDoc::Analyzer::DiffService`

**File:** `lib/auto_doc/analyzer/diff_service.rb`

### Purpose

Detects documentation drift by comparing current documentation state against a git reference (commit, branch, tag). Finds Ruby files changed since the git ref and identifies undocumented symbols in those changed files.

### Constructor

```ruby
def initialize(project_dir, since, say: method(:puts))
  @project_dir = project_dir
  @since       = since
  @say         = say
end
```

### API

```ruby
result = DiffService.run(project_dir, since, say: method(:puts))
# Returns: Hash with :changed_files and :undocumented_changes

# Instance method
result = DiffService.new(project_dir, since, say: method(:puts)).run
# Returns: Hash
```

### Return Value

```ruby
{
  changed_files:          ["lib/user.rb", "app/models/post.rb"],
  undocumented_changes:  [{ type: :class, symbol: "NewClass", file: "lib/user.rb" }, ...]
}
```

### `run`

1. Outputs status message via `@say.call("Checking for undocumented changes since '#{@since}'...", :green)`.
2. Gets changed Ruby files via `git_changed_ruby_files`.
3. Returns early if no changes.
4. Loads config, analyzes changed files via `analyze_files`.
5. Finds undocumented symbols via `find_undocumented`.
6. Returns `{ changed_files:, undocumented_changes: }`.

### `git_changed_ruby_files`

Executes `git diff --name-only #{@since} -- '*.rb'` and filters results:
- Splits output into lines.
- Strips whitespace from each line.
- Only includes files that exist on disk (`File.exist?`).
- Returns empty array and warns on git failure.

### `analyze_files(file_list)`

1. Loads config for exclude patterns.
2. For each file:
   - Checks file exists.
   - Skips excluded patterns via `File.fnmatch?`.
   - Parses via `SourceParser.parse_file(file_path)`.
   - Extracts docs via `YardReader.extract(file_path)`.
   - Builds doc lookup index from docs: `{:"#{type}_#{name}" => doc_record}`.
   - Merges doc presence into definitions: `defn[:has_doc?] = doc_index[key] && doc_record[:has_summary?] == true`.
   - Records in analyses hash.

### `find_undocumented(analyses)`

Iterates through analyses, collecting definitions where `has_doc?` is false/nil:

```ruby
{
  type:   defn[:type].to_s,
  symbol: defn[:name],
  file:   file_path
}
```

### `config`

Memoized config loader: `AutoDoc::Config.load(@project_dir)`.