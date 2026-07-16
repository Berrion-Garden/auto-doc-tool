# frozen_string_literal: true

# REAL integration test that hits https://llms.berrion.garden/v1
# Run with: unset AUTO_DOC_DISABLE_LLM && bundle exec ruby -I lib spec/scripts/real_integration_check.rb

require "auto_doc"
require "json"
require "tmpdir"
require "fileutils"

def assert(description, condition, detail = "")
  if condition
    puts "  ✅ #{description}"
    true
  else
    puts "  ❌ #{description}#{detail.empty? ? '' : " — #{detail}"}"
    false
  end
rescue => e
  puts "  ❌ #{description} — ERROR: #{e.message}"
  false
end

def section(title)
  puts "\n=== #{title} ==="
end

results = []

# ── Test 1: Client basic connectivity ──────────────────────────
section("Client#chat — real API call")

client = AutoDoc::LLM::Client.new(
  endpoint: "https://llms.berrion.garden/v1",
  api_key: "autodoc",
  model: "summarizer",
  timeout: 15
)

result = client.chat([{ role: "user", content: "Reply with exactly: HELLO FROM SUMMARIZER" }])
results << assert("chat returns a non-nil response", !result.nil?, "got nil")
results << assert("response is a String", result.is_a?(String), "got #{result.class}")
results << assert("response is not empty", !result.to_s.strip.empty?, "empty string")
puts "  → Response: #{result.inspect}" if result

# ── Test 2: Summarizer#summarize_module ────────────────────────
section("Summarizer#summarize_module — real API call")

analyses = {
  "/project/lib/parser.rb" => {
    definitions: [
      { type: "class", name: "Parser", has_doc?: true },
      { type: "method", name: "parse", has_doc?: false }
    ],
    imports: [{ path: "json", type: :require }],
    docs: []
  },
  "/project/lib/formatter.rb" => {
    definitions: [
      { type: "module", name: "Formatter", has_doc?: true },
      { type: "method", name: "format", has_doc?: true }
    ],
    imports: [{ path: "fileutils", type: :require }],
    docs: []
  }
}

summary = AutoDoc::LLM::Summarizer.summarize_module("lib", analyses, client)
results << assert("summarize_module returns a non-nil result", !summary.nil?, "got nil")
results << assert("summary is a String", summary.is_a?(String), "got #{summary.class}")
results << assert("summary has substantial content", summary.to_s.length > 30, "only #{summary.to_s.length} chars")
puts "  → Summary: #{summary.inspect}" if summary

# ── Test 3: Summarizer#summarize_architecture ──────────────────
section("Summarizer#summarize_architecture — real API call")

arch = AutoDoc::LLM::Summarizer.summarize_architecture("test-project", analyses, client)
results << assert("summarize_architecture returns non-nil", !arch.nil?, "got nil")
results << assert("architecture is a String", arch.is_a?(String), "got #{arch.class}")
results << assert("architecture has substance", arch.to_s.length > 30, "only #{arch.to_s.length} chars")
puts "  → Architecture: #{arch.inspect}" if arch

# ── Test 4: Summarizer#summarize_components ────────────────────
section("Summarizer#summarize_components — real API call")

comps = AutoDoc::LLM::Summarizer.summarize_components(analyses, client)
results << assert("summarize_components returns non-nil", !comps.nil?, "got nil")
results << assert("components is a String", comps.is_a?(String), "got #{comps.class}")
results << assert("components has substance", comps.to_s.length > 30, "only #{comps.to_s.length} chars")
puts "  → Components: #{comps.inspect}" if comps

# ── Test 5: SummaryGenerator with real LLM ─────────────────────
section("SummaryGenerator — full pipeline with real LLM")

llm_test_dir = Dir.mktmpdir
File.write(File.join(llm_test_dir, ".autodoc.yml"), <<~YAML)
  llm:
    provider: openai
    endpoint: https://llms.berrion.garden/v1
    api_key: autodoc
    model: summarizer
    timeout: 120
YAML
config = AutoDoc::Config.load(llm_test_dir)
output = AutoDoc::Generator::SummaryGenerator.generate("lib", analyses, config)
results << assert("SUMMARY.md includes SUMMARY header", output.include?("SUMMARY: lib"), "missing header")
results << assert("SUMMARY.md purpose is LLM-generated (not static fallback)", !output.include?("Core library code"), "contains static fallback text")
results << assert("SUMMARY.md has substantial content", output.length > 200, "only #{output.length} chars")
puts "  → SummaryGenerator output (first 400 chars): #{output[0..400]}" if output

# ── Test 6: AgentsMdGenerator with real LLM ────────────────────
section("AgentsMdGenerator — full pipeline with real LLM")

files = [
  { name: "parser.rb", path: "/project/lib/parser.rb",
    classes: [{ name: "Parser", type: "class", has_doc?: true, line: 1 }],
    imports: [{ path: "json", type: :require }] },
  { name: "formatter.rb", path: "/project/lib/formatter.rb",
    classes: [{ name: "Formatter", type: "module", has_doc?: true, line: 1 }],
    imports: [] }
]
tree_text = "lib/\n  parser.rb\n  formatter.rb\n"

agents_output = AutoDoc::Generator::AgentsMdGenerator.generate(
  "lib", tree_text, files, config: config
)
results << assert("AGENTS.md includes module name header", agents_output.include?("# lib"), "missing header")
results << assert("AGENTS.md purpose is LLM-generated (not 'developer to fill in')", !agents_output.include?("developer to fill in"), "contains fallback text")
results << assert("AGENTS.md has substantial content", agents_output.length > 200, "only #{agents_output.length} chars")
puts "  → AgentsMdGenerator output (first 400 chars): #{agents_output[0..400]}" if agents_output

# ── Summary ────────────────────────────────────────────────────
passed = results.count(true)
failed = results.count(false)
total = results.size

puts "\n#{'=' * 50}"
puts "RESULTS: #{passed}/#{total} passed, #{failed}/#{total} failed"
puts "#{'=' * 50}"

FileUtils.remove_entry(llm_test_dir)

exit(1) if failed > 0
