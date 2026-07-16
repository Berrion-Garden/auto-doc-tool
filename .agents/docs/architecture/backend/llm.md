# LLM Submodule — Backend

## Components

### `client.rb` — LLM HTTP Client

OpenAI-compatible HTTP client using Ruby's stdlib `Net::HTTP`. No external HTTP gem required.

**Key methods:**
- `#chat(messages, options = {})` — Sends a chat completion POST request, returns response text or nil on failure
- `#configured?` — Validates that endpoint and api_key are present
- `Client.from_config(config)` — Builds client from a config object
- `Client.build_if_configured(config)` — Gated client construction: checks `AUTO_DOC_DISABLE_LLM` env, validates config, checks `configured?`, catches all HTTP errors

**Error handling:** Catches `Net::OpenTimeout`, `Net::ReadTimeout`, `Net::HTTPError`, `Net::HTTPClientException`, `Net::HTTPFatalError`, `JSON::ParserError`, `SocketError`, `Errno::ECONNREFUSED`, `Errno::ECONNRESET` — always returns nil on failure (never raises).

### `prompt_builder.rb` — Prompt Construction

Builds metadata-only prompts for LLM summarization. Never includes full source code — only file names, class/module/method names, and structural relationships.

**Supported generator types:**
| Type | Purpose |
|------|---------|
| `:summary` | Module-level purpose summary |
| `:architecture` | Overall project architecture |
| `:components` | Component relationships and data flow |
| `:architecture_full` | Detailed architecture overview (purpose, style, modules, data flow) |
| `:system_context` | External systems and interactions |
| `:containers` | Container/module descriptions by root |
| `:agents_md` | AGENTS.md generation prompt |
| `:readme` | README generation prompt |
| `:agents_overview_*` | Agents overview sub-sections (overview, tech_stack, architecture, conventions) |
| `:symbol_summaries` | Per-symbol one-line descriptions |

**Shared behavior:** All prompts start with "You are a software documentation expert..." and instruct the LLM to NOT include source code. The `extract_metadata_lines` helper iterates analyses, outputting file paths and symbol definitions (class/module/method/constant) with documentation status.

### `response_parser.rb` — Response Parsing

Parses raw LLM responses into structured data. Supports multiple output formats:

| Method | Input format | Output |
|--------|-------------|--------|
| `parse_purpose` | Markdown heading or first paragraph | String |
| `parse_components` | Bullet list (`- Name: Description`) | Array of `{name:, description:}` |
| `parse_architecture_full` | Sectioned markdown (`## Purpose`, `## Architecture Style`, etc.) | Hash with `:purpose`, `:style`, `:modules`, `:data_flow` |
| `parse_system_context` | JSON array or bullet list | Array of `{name:, interaction:}` or nil |
| `parse_containers` | `## Module Root: name` headings with content | Hash of `{module_root => description}` |
| `parse_symbol_summaries` | `symbol_name: one-line summary` lines | Hash of `{entry_id => summary_text}` |
| `parse_llm_modules` | Bullet list (`- **Name** - Description`) | Array of `{name:, responsibility:}` |
| `parse_llm_data_flows` | `From -> To: Description` | Array of `{from:, to:, description:}` |

### `summarizer.rb` — LLM Summarization Coordinator

Delegates to `PromptBuilder.build` and `ResponseParser` methods. Never directly includes source code in prompts.

**Key methods:**
- `summarize_module(dir_name, analyses, client)` — Module purpose summary
- `summarize_architecture(project_name, analyses, client)` — Architecture overview
- `summarize_components(analyses, client)` — Component relationships
- `summarize_architecture_full(project_name, analyses, client)` — Structured hash (purpose, style, modules, data_flow)
- `summarize_system_context(project_name, analyses, client)` — External systems
- `summarize_symbols(module_name, analyses, client)` — Per-symbol descriptions (used by Enricher)
- `summarize_containers(analyses, module_roots, client)` — Container descriptions by module root
- `parse_architecture_modules(summary)` — Delegates to `ResponseParser.parse_llm_modules`
- `parse_architecture_data_flows(summary)` — Delegates to `ResponseParser.parse_llm_data_flows`

### `enricher.rb` — Pre-Processing Enrichment (New)

Groups analyses by module root directory, calls `Summarizer.summarize_symbols` per module, and appends generated summaries to each file's `analyses[file_path][:docs]` array.

**Key method:** `enrich_analyses(analyses, config, base_dir: nil)`

**Behavior:**
1. Guard: returns immediately if `config.llm_primary?` is false
2. Builds `Symbol.build_if_configured(config)` — nil if LLM client unavailable
3. Pre-builds a `symbol_types` lookup: `symbol_name => type.downcase` for all definitions across all files
4. Resolves module roots: handles relative roots (e.g., `["app", "lib"]`) by joining with `base_dir` when needed for `start_with?` matching
5. For each module root, filters analyses, calls `Summarizer.summarize_symbols`, parses response via `ResponseParser.parse_symbol_summaries`
6. For each parsed summary, appends `{target_name:, target_type:, summary:}` to the corresponding file's `:docs` array
7. Handles nil LLM responses gracefully (logs warning to stderr, continues processing other modules)
8. Handles empty responses (skips silently)
9. Namespaced symbol names (`Payment::Processor`) are handled by converting `::` to `_` in the entry_id

**Entry ID construction:** `"#{type}_#{name.gsub('::', '_')}"` (e.g., `class_Payment_Processor`)

**Guard chain:**
```
config.llm_primary? → Client.build_if_configured → symbol_types build → module filter → Summarizer.summarize_symbols → ResponseParser.parse_symbol_summaries → docs array append
```

Any guard returning early means zero LLM calls are made.