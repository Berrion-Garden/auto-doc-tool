# FileTreeBuilder

## Class: `AutoDoc::Utils::FileTreeBuilder`

**File:** `lib/auto_doc/utils/file_tree_builder.rb`

### Purpose

Builds an indented directory tree text representation using box-drawing characters (`├──`, `└──`, `│`). Similar to the Unix `tree` command output. Uses `Dir.glob` and `File.stat` to distinguish directories from files.

### Constructor

```ruby
def initialize(path, exclude_patterns = [])
  @root = File.expand_path(path)
  @exclude_patterns = Array(exclude_patterns).flatten(1)
end
```

### API

```ruby
# Class method
tree = FileTreeBuilder.build(path, exclude_patterns = [])
# Returns: String (tree text with trailing newline)

# Instance method
tree = FileTreeBuilder.new(path, exclude_patterns).build
# Returns: String
```

### `build`

1. Lists immediate children of the root directory via `entries(@root)`.
2. Returns `""` if no children.
3. Otherwise, renders children via `render_children` with empty prefix.
4. Returns joined lines with trailing newline.

### `entries(dir)` (private)

Lists immediate children of a directory:
1. Skips dotfiles/dotdirs (`e.start_with?(".")`).
2. Sorts alphabetically.
3. Filters out entries matching exclude patterns via `should_exclude?`.
4. Returns array of `{name:, path:, type: :directory/\:file}`.
5. Gracefully handles missing files via `File.stat(full_path) rescue nil`.

### `render_children(children, prefix)` (private)

Renders entries with proper tree connectors:
- Last child: `└── ` connector, `    ` continuation
- Non-last: `├── ` connector, `│   ` continuation
- Recurses into directories with updated prefix.

### `should_exclude?(filepath)` (private)

1. Returns `false` if no exclude patterns.
2. Computes relative path from root via `filepath.sub(@root.chomp("/"), "").sub(%r{^/}, "")`.
3. Checks each pattern with `File.fnmatch?(pattern, rel_path)`.
4. Returns `true` on first match.

### Output Example

```
app/
├── controllers/
│   └── users_controller.rb
└── models/
    ├── user.rb
    └── post.rb
```