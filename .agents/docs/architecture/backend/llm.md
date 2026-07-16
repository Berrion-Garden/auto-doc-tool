# Auto-Doc — LLM Module

## Purpose

Provides LLM-powered summarization for documentation generation. **Fully integrated** into all four LLM-aware generators (`SummaryGenerator`, `AgentsMdGenerator`, `ArchitectureGenerator`, `ReadmeGenerator`) and diagram generation (`DiagramStep`). LLM enhancement is gated behind a `llm_primary` config flag — when disabled (`llm.primary: false`, the default), zero LLM calls are made.

## Files

### `lib/auto_doc/llm.rb`

Module loader that defines the `AutoDoc::LLM` namespace and requires `llm/client`, `llm/summarizer`, `llm/prompt_builder`, and `llm/response_parser`.

### `lib/auto_doc/llm/client.rb`

OpenAI-compatible HTTP client for chat completion endpoints.

**Dependencies:** `net/http`, `json`, `uri` (all Ruby stdlib)

**Interface:**
- `initialize(config_hash)` — Accepts `:endpoint`, `:api_key`, `:model`, `:timeout`
- `chat(messages, options = {})` — Sends POST to `{endpoint}/chat/completions`. Returns `String` or `nil`
- `configured?` — Returns `true` when both `:endpoint` and `:api_key` are present and non-empty
- `self.from_config(config)` — Builds client from an object responding to `llm_config`
- `self.build_if_configured(config)` — Safe client construction with ENV guard (`AUTO_DOC_DISABLE_LLM`), config validity checks, and `configured?` check. Returns `Client` or `nil`.

**Error handling:** Catches `Net::OpenTimeout`, `Net::ReadTimeout`, `Net::HTTPError`, `JSON::ParserError`, `SocketError`, `Errno::ECONNREFUSED`, `Errno::ECONNRESET` — all return `nil`

**Request format:**
```
POST {endpoint}/chat/completions
Content-Type: application/json
Authorization: Bearer {api_key}
Body: { model, messages, ...options }
```

**Response extraction:** `choices[0].message.content`

### `lib/auto_doc/llm/summarizer.rb`

Central orchestrator for LLM summarization. Delegates prompt construction to `PromptBuilder` and response parsing to `ResponseParser`.

**Key property:** Never includes full source code — only file names, class/module names, method names, and structural relationships.

**Interface (public class methods):**
- `summarize_module(dir_name, analyses, client)` — Summary of a specific module directory (delegates to `PromptBuilder.build(:summary, ...)`)
- `summarize_architecture(project_name, analyses, client)` — Overall project architecture summary (delegates to `PromptBuilder.build(:architecture, ...)`)
- `summarize_components(analyses, client)` — Component relationships and dependencies (delegates to `PromptBuilder.build(:components, ...)`)
- `summarize_architecture_full(project_name, analyses, client)` — Multi-paragraph architecture overview; returns parsed `Hash` with `:purpose`, `:style`, `:modules`, `:data_flow` keys via `ResponseParser.parse_architecture_full`
- `summarize_system_context(project_name, analyses, client)` — External systems interaction list; returns structured `Array<Hash>` via `ResponseParser.parse_system_context`
- `summarize_containers(analyses, module_roots, client)` — Container/module descriptions; returns structured `Hash` via `ResponseParser.parse_containers`
- `parse_architecture_modules(summary)` — Delegates to `ResponseParser.parse_llm_modules(summary[:modules])` (centralizes key-coupling from `ArchitectureGenerator`)
- `parse_architecture_data_flows(summary)` — Delegates to `ResponseParser.parse_llm_data_flows(summary[:data_flow])` (centralizes key-coupling from `ArchitectureGenerator`)

**Refactoring note:** Prompt building was extracted from inline methods in the original `Summarizer` into a dedicated `PromptBuilder` class. Response parsing was similarly extracted into `ResponseParser`. `Summarizer` remains the primary public API for all consumers.

### `lib/auto_doc/llm/prompt_builder.rb`

Dedicated prompt construction class. Builds structured prompt messages for 8 generator types without mixing parsing concerns.

**Interface:**
- `self.build(generator_type, name, analyses, module_roots = nil)` — Accepts a symbol (`:agents_md`, `:summary`, `:architecture`, `:components`, `:architecture_full`, `:system_context`, `:containers`, `:readme`) and returns `Array<Hash>` of `{role:, content:}` message hashes.

**Private prompt builders:**
- `build_summary_messages(dir_name, analyses)` — Module-level purpose summary prompt
- `build_architecture_messages(project_name, analyses)` — Architecture pattern prompt
- `build_components_messages(analyses)` — Component relationship prompt (groups by top-level directory)
- `build_architecture_full_messages(project_name, analyses)` — Multi-paragraph architecture overview prompt
- `build_system_context_messages(project_name, analyses)` — External systems prompt (asks for JSON or bullet list)
- `build_containers_messages(analyses, module_roots)` — Container descriptions prompt (one section per root)
- `build_agents_md_messages(module_name, analyses)` — Agents.md module description prompt
- `build_readme_messages(project_name, analyses)` — README generation prompt

**Metadata extraction (`extract_metadata_lines`):**
```
**File:** path/to/file.rb
  - Class: `ClassName` (documented)
  - Module: `ModuleName`
  - Method: `methodName`
  - Constant: `CONST_NAME`
```

### `lib/auto_doc/llm/response_parser.rb`

Dedicated response parsing class. Handles markdown headings, JSON arrays, and bullet list formats.

**Interface (public class methods):**
- `parse_purpose(text)` — Extracts first paragraph or `## Purpose` section content
- `parse_components(text)` — Parses markdown bullet list (`- Name: Description` or `- **Name** - Description`) into `Array<Hash>` with `:name`, `:description`
- `parse_architecture_full(response)` — Parses markdown into `Hash` with `:purpose`, `:style`, `:modules`, `:data_flow` keys; tries alternative heading names and paragraph-only fallback
- `parse_system_context(response)` — Tries JSON array first (`[{name:, interaction:}]`), then markdown bullet list fallback
- `parse_containers(response)` — Parses `## Module Root: name` sections into `Hash` of `{module_root_name => description_string}`
- `parse_llm_modules(text)` — Parses markdown bullet list into `Array<Hash>` with `:name`, `:responsibility`
- `parse_llm_data_flows(text)` — Parses `- From -> To: Description` or `- From → To: Description` into `Array<Hash>` with `:from`, `:to`, `:description`

**Private methods:** `parse_section(response, section_name)` — Extracts content under a named `##` heading (case-insensitive) until the next `##` heading or end-of-string.

## Integration Status

The LLM module is **fully implemented and integrated** into the generation pipeline:

1. **Config:** `llm:` defaults with `provider: "openai"`, `endpoint: "https://llms.berrion.garden/v1"`, `api_key: "autodoc"`, `model: "summarizer"`, `timeout: 120`, `primary: false` and `llm_config`/`llm_primary?` accessors are present
2. **LLM Primary Gate:** When `llm.primary: false` (default), no generator makes any LLM calls. When `llm.primary: true` (set via `--llm-primary` CLI flag or config), generators try LLM first and fall back to static analysis with `$stderr` warning
3. **SummaryGenerator:** Uses `llm_primary?` gate (via `TemplateHelper` mixin). When primary: calls `llm_purpose` (`Summarizer.summarize_module`), `llm_architecture` (`Summarizer.summarize_architecture`), `llm_components` (`Summarizer.summarize_components`). Falls back to `infer_purpose`, `extract_key_components`, `infer_architecture_pattern` with `warn_llm_fallback` on failure
4. **AgentsMdGenerator:** Uses `llm_primary?` gate. When primary: calls `llm_purpose_summary` (`Summarizer.summarize_module`). Falls back to placeholder text with `warn_llm_fallback` on failure
5. **ArchitectureGenerator:** Uses `llm_primary?` gate gated behind `@auto_doc_config && @analyses`. When primary: calls `Summarizer.summarize_architecture_full` (single LLM call returning structured hash). Parses modules via `Summarizer.parse_architecture_modules` and data flows via `Summarizer.parse_architecture_data_flows`. LLM block wrapped in `begin/rescue StandardError`. Falls back to model-based data on all sections
6. **ReadmeGenerator:** Uses `llm_primary?` gate. When primary: calls `llm_module_overview` (`Summarizer.summarize_module`). Falls back to placeholder text with `warn_llm_fallback` on failure
7. **DiagramStep:** LLM calls for C4 context (`summarize_system_context`) and container (`summarize_containers`) diagrams gated behind `config.llm_primary?`. Falls back to hardcoded defaults
8. **CLI:** `--llm-primary` flag on `generate`, `audit`, and `verify` commands; mapped to `{ llm: { primary: true } }` in `Orchestrator#cli_overrides`
9. **TemplateHelper mixin:** Provides `llm_primary?` (checks `@auto_doc_config || @config` for `llm_primary?`) and `warn_llm_fallback(description)` (consistent `$stderr` warning) — included by all 4 LLM-aware generators
10. **Client.build_if_configured:** Centralized safe construction with `AUTO_DOC_DISABLE_LLM` ENV guard, config validation, and `configured?` check

All LLM calls use `rescue` blocks that return `nil` on any failure. In primary mode, `warn_llm_fallback` emits a warning to stderr before falling back. The integration is verified by `spec/auto_doc/llm/integration_spec.rb` (15 examples, tagged `:integration`).

## Prompt Safety

All prompt methods are metadata-only: they never include full source code (`def ` or `class ` keyword patterns). The `extract_metadata_lines` private method produces structured output with file paths, class/module/method/constant names, types, and documentation status — but no source code. Prompt text was also standardized from "Ruby project" to "software project" for broader applicability.