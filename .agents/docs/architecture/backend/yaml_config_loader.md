# YamlConfigLoader

## Class: `AutoDoc::Utils::YamlConfigLoader`

**File:** `lib/auto_doc/utils/yaml_config_loader.rb`

### Purpose

Simple YAML file reader with validation. Returns an empty hash if the file does not exist, is empty, or contains invalid YAML. Used by `Config` for file config loading.

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `EXPECTED_KEYS` | `[:module_roots, :exclude_patterns, :output, :audit, :diagrams]` | Documented expected top-level keys (validation only) |
| `YAML_AVAILABLE` | Boolean | `true` if `require "yaml"` succeeded, `false` if `LoadError` |

### Constructor

None — all methods are class methods.

### API

```ruby
YamlConfigLoader.load(file_path)
# Returns: Hash (always, never raises)
# Returns {} if: file doesn't exist, file is empty, YAML unavailable, parsed result not a Hash
```

### `load(file_path)`

1. Returns `{}` if file doesn't exist (`File.exist?`).
2. Returns `{}` if file is empty (`File.zero?`).
3. Returns `{}` if `YAML_AVAILABLE` is false (YAML gem not installed).
4. Reads file content via `File.read`.
5. Parses via `YAML.safe_load(content, permitted_classes: [Symbol], aliases: true)`.
6. Returns `{}` if parsed result is not a Hash.
7. Converts all string keys to symbols (recursively) via `symbolize_keys`.
8. Returns the symbolized hash.

### `symbolize_keys(hash)` (private, recursive)

```ruby
def self.symbolize_keys(hash)
  hash.each_with_object({}) do |(key, value), result|
    new_key = key.is_a?(String) ? key.to_sym : key
    result[new_key] = value.is_a?(Hash) ? symbolize_keys(value) : value
  end
end
```

- Converts string keys to symbols.
- Recursively symbolizes nested hashes.
- Preserves non-hash values as-is.

### YAML Security

Uses `YAML.safe_load` with:
- `permitted_classes: [Symbol]` — allows Symbol-typed keys in YAML (needed for Ruby config files with symbol keys)
- `aliases: true` — allows YAML anchors/aliases

### Phase 2a

The `EXPECTED_KEYS` constant is defined but not actually validated — `load` returns the parsed result regardless of whether these keys are present. This is a dead constant.