# TimestampTracker

## Class: `AutoDoc::Utils::TimestampTracker`

**File:** `lib/auto_doc/utils/timestamp_tracker.rb`

### Purpose

Tracks file modification times to detect which files have changed since the last documentation generation run. Enables incremental regeneration mode.

### Manifest Format

Stored as `generation_manifest.json` within the output directory:

```json
{
  "generated_at": "2026-07-15T01:00:00+00:00",
  "files": {
    "lib/auto_doc.rb": 1752540000,
    "lib/auto_doc/config.rb": 1752540100
  }
}
```

### API

```ruby
# Returns all Ruby files that have changed (or are new) since the last manifest.
# Returns ALL Ruby files if no manifest exists (first run).
stale = TimestampTracker.stale_files(project_dir, output_dir = ".docs")
# => ["lib/auto_doc.rb", ...]

# Saves a manifest with current mtimes
TimestampTracker.save_manifest(project_dir, file_list, output_dir = ".docs")
# => true on success, false on permission errors
```

### Method: `stale_files(project_dir, output_dir)`

1. Glob all `*.rb` files from project dir.
2. Load manifest from `{output_dir}/generation_manifest.json`.
3. Compare each file's current mtime against stored mtime.
4. Return files where stored mtime is nil or different.
5. On `Errno::ENOENT` or `JSON::ParserError`, return all files (graceful first-run).

### Method: `save_manifest(project_dir, file_list, output_dir)`

1. Build hash of `{ relative_path => mtime_epoch }` for all files.
2. Create output directory if needed (`FileUtils.mkdir_p`).
3. Write `{ generated_at: ISO8601, files: {...} }` as pretty JSON.
4. On `Errno::EACCES` or `Errno::ENOENT`, return false.

### Phase 2a Changes

`MANIFEST_PATH` changed from `".autodoc/generation_manifest.json"` to `".docs/generation_manifest.json"`. The `save_manifest` method now accepts `output_dir` parameter, allowing it to write manifest to the correct output directory regardless of the output format setting.