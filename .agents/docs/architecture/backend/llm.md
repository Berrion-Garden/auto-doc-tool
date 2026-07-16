# Auto-Doc — LLM Module

## Purpose

Provides LLM-powered summarization for documentation generation. **Fully integrated** into `SummaryGenerator` and `AgentsMdGenerator` with graceful fallback to static inference when LLM is unavailable.

## Files

### `lib/auto_doc/llm.rb`

Module loader that defines the `AutoDoc::LLM` namespace and requires `llm/client` and `llm/summarizer`.

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

Builds metadata-only prompts and delegates to a `Client` instance.

**Key property:** Never includes full source code — only file names, class/module names, method names, and structural relationships.

**Interface (public class methods):**
- `summarize_module(dir_name, analyses, client)` — Summary of a specific module directory
- `summarize_architecture(project_name, analyses, client)` — Overall project architecture summary
- `summarize_components(analyses, client)` — Component relationships and dependencies
- `summarize_architecture_full(project_name, analyses, client)` — Multi-paragraph architecture overview covering purpose, style, modules, and data flow
- `summarize_system_context(project_name, analyses, client)` — External systems interaction list (JSON or bullet list format)
- `summarize_containers(analyses, module_roots, client)` — Container/module descriptions keyed by module root name

**Private prompt builders:** `build_module_prompt`, `build_architecture_prompt`, `build_components_prompt`, `build_architecture_full_prompt`, `build_system_context_prompt`, `build_containers_prompt`, `extract_metadata_lines`

**Prompt structure:** Each method builds a prompt with:
1. System persona ("You are a software documentation expert...")
2. Context (module name / project name / component grouping)
3. Instruction ("Provide a concise summary... Do NOT include any source code")
4. Metadata extracted from analyses (file paths, definition names, types, documentation status)

**Metadata extraction (`extract_metadata_lines`):**
```
**File:** path/to/file.rb
  - Class: `ClassName` (documented)
  - Module: `ModuleName`
  - Method: `methodName`
  - Constant: `CONST_NAME`
```

## Integration Status

The LLM module is **fully implemented and integrated** into the generation pipeline:

1. **Config:** `llm:` defaults with `provider: "openai"`, `endpoint: "https://llms.berrion.garden/v1"`, `api_key: "autodoc"`, `model: "summarizer"`, `timeout: 120` and `llm_config` accessor are present
2. **SummaryGenerator:** Calls `Summarizer.summarize_module`, `summarize_architecture`, and `summarize_components` via `llm_purpose`, `llm_architecture`, `llm_components` methods. Falls back to `infer_purpose`, `extract_key_components`, `infer_architecture_pattern` when LLM unavailable
3. **AgentsMdGenerator:** Accepts `config:` keyword parameter. Calls `Summarizer.summarize_module` via `llm_purpose_summary` method. Falls back to `nil` (template renders placeholder text) when LLM unavailable
4. **AgentsMdStep:** Passes `config: config` to `AgentsMdGenerator.generate`
5. **Client.build_if_configured:** Centralized safe construction with `AUTO_DOC_DISABLE_LLM` ENV guard, config validation, and `configured?` check
6. **Additional Summarizer methods** (added in final commit `8e7254a` by LLM self-doc regeneration): `summarize_architecture_full` (multi-paragraph overview), `summarize_system_context` (external systems list), `summarize_containers` (module root descriptions) — available but not yet wired into a pipeline step or generator

All LLM calls use `rescue` blocks that return `nil` on any failure, ensuring graceful degradation. The integration is verified by `spec/auto_doc/llm/integration_spec.rb` (15 examples, tagged `:integration`).

## Prompt Safety

All Summarizer prompt methods are metadata-only: they never include full source code (`def ` or `class ` keyword patterns). The `extract_metadata_lines` private method produces structured output with file paths, class/module/method/constant names, types, and documentation status — but no source code. Prompt text was also standardized from "Ruby project" to "software project" for broader applicability.