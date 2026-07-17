# Verification Playbook: auto-doc End-to-End Testing

> **Purpose:** Manual verification steps to run after bob_26 delivers changes.
> Run these checks against a REAL project (Rails, Python, JS, etc.) to validate output quality.
> **Target:** `/home/kyle/Projects/pi-manager` (Rails app, 32 Ruby files + JS controllers)

---

## 1. Generation Smoke Test

```bash
cd /home/kyle/Projects/auto-doc-tool
unset AUTO_DOC_DISABLE_LLM
ruby -I lib exe/auto-doc generate /home/kyle/Projects/pi-manager --format autodoc 2>&1
```

### What to check:
| Check | Pass Criteria |
|-------|---------------|
| Exit code | `0` — no crashes |
| Files created | Count matches expected (25+ for Rails) |
| Stderr warnings | `[AutoDoc] LLM unavailable` means LLM failed — investigate |
| Generation time | Should complete under 5 min (LLM calls are slow) |

### Common failures:
- **EISDIR errors** — `Dir.glob` picking up directories as files. Check `orchestrator.rb` glob filter.
- **Schema parser crash** — Rails `schema.rb` format variations. Check `schema_parser.rb`.

---

## 2. File Inventory

```bash
find /home/kyle/Projects/pi-manager/.autodoc -type f | sort
```

### Must-have files for a Rails project:
```
AGENTS.md              # Root AI-agent project map (NEW)
app/AGENTS.md          # Per-module agent docs
lib/AGENTS.md
bin/AGENTS.md
README.md              # Project README
INDEX.md               # Project-level file/symbol index
SUMMARY.md             # LLM-powered project summary
VECTORS.json           # Vector index with LLM-enriched summaries
architecture.md        # Architecture documentation
diagrams/deps.mmd      # Dependency graph
diagrams/class_diagram.mmd  # Class hierarchy
diagrams/c4_context.mmd     # C4 context diagram
diagrams/c4_container.mmd   # C4 container diagram
diagrams/erd.mmd            # ER diagram (Rails only)
schema/schema.json          # Database schema (Rails only)
schema/models.json          # Model associations (Rails only)
.map.json                   # Generation manifest
```

### What to look for:
- **ERD missing?** Check if `db/schema.rb` exists. If yes but ERD absent, schema parser is broken.
- **schema.json empty?** (2 bytes) — parser returned nil. Check `schema_parser.rb` regex patterns.
- **Missing AGENTS.md submodules?** — `auto_doc/llm/AGENTS.md` should exist if LLM module has Ruby files.

---

## 3. Content Quality — AGENTS.md

```bash
head -30 /home/kyle/Projects/pi-manager/.autodoc/AGENTS.md       # Root overview
head -25 /home/kyle/Projects/pi-manager/.autodoc/app/AGENTS.md    # Per-module
```

### What to look for:
- **LLM-generated, not static** — Should NOT contain "developer to fill in". Should NOT contain "Ruby source files in the X module".
- **Accurate, not prescriptive** — Describes WHAT something does, not HOW. Example: "Handles extension lifecycle" NOT "Calls create/destroy actions".
- **Not code** — No code blocks, no method signatures. Pure natural language.
- **Complete skeletons** — Every class/module in the directory should be listed with a purpose.
- **LLM summaries in Public API table** — Each symbol should show a summary, not "No documentation available."

### Red flags:
```
_This directory contains:_ developer to fill in    → LLM failed
Ruby source files in the Concerns module (1 file(s)).  → Static fallback, LLM not running
No documentation available.   → LLM enrichment didn't reach this symbol
```

---

## 4. Content Quality — SUMMARY.md

```bash
head -25 /home/kyle/Projects/pi-manager/.autodoc/SUMMARY.md
```

### What to look for:
- **Rich project description** — Should describe the project's purpose, tech stack, major components.
- **Unique per project** — Not generic. Should mention specific details like "Stimulus controllers" or "Importmap" or "Pi instance management".
- **Architecture pattern** — Should mention MVC, service layer, or module organization.

### Red flags:
```
Ruby source files in the Pi Manager module (32 file(s)).  → Static fallback
```

---

## 5. Content Quality — architecture.md

```bash
cat /home/kyle/Projects/pi-manager/.autodoc/architecture.md
```

### What to look for:
- **LLM-generated architecture style** — Should describe the actual architecture (MVC, service-oriented, etc.)
- **Module map** — Should list modules with their responsibilities.
- **Data flow** — Should describe how data moves through the system.
- **Diagram links** — Should link to all generated diagrams.

### Red flags:
```
Auto-generated architecture documentation for pi-manager.  → Static fallback
Monolithic   → Fallback detection (counts <1 module)
No modules defined.   → Models data was empty
No data flows defined.  → No associations parsed
```

---

## 6. Diagram Quality

```bash
for f in /home/kyle/Projects/pi-manager/.autodoc/diagrams/*.mmd; do
  echo "=== $(basename $f) ==="
  wc -l "$f"
  head -10 "$f"
done
```

### What to look for:
| Diagram | Content | Min Size |
|---------|---------|----------|
| `deps.mmd` | `graph TB` with edges between files | >500 bytes |
| `class_diagram.mmd` | `classDiagram` with class boxes | >500 bytes |
| `c4_context.mmd` | `C4Context` with system/person boundaries | >300 bytes |
| `c4_container.mmd` | `C4Container` with container boxes | >300 bytes |
| `erd.mmd` (Rails) | `erDiagram` with tables and relationships | >300 bytes |

### Red flags:
- `graph TB` with only `A[A]` — dependency graph has no edges
- C4 diagrams with only headers and no content — LLM call failed or diagram generator is broken
- ERD missing for Rails project — schema parser issue

---

## 7. Schema & Model Quality (Rails only)

```bash
wc -c /home/kyle/Projects/pi-manager/.autodoc/schema/schema.json
wc -c /home/kyle/Projects/pi-manager/.autodoc/schema/models.json
python3 -c "
import json
s = json.load(open('/home/kyle/Projects/pi-manager/.autodoc/schema/schema.json'))
print(f'Tables: {len(s) if isinstance(s, list) else len(s.keys())}')
if isinstance(s, list) and s:
    print(f'  First table: {s[0]}')
"
```

### What to look for:
- schema.json should have table definitions with columns, types, constraints
- models.json should have model names with associations (has_many, belongs_to, etc.)
- Files should be >100 bytes. 2 bytes = parser returned empty.

---

## 8. VECTORS.json Enrichment

```bash
python3 -c "
import json
d = json.load(open('/home/kyle/Projects/pi-manager/.autodoc/VECTORS.json'))
sym = d.get('symbols', [])
w = [s for s in sym if s.get('summary') and s['summary'].strip()]
print(f'Total symbols: {len(sym)}')
print(f'With LLM summaries: {len(w)}')
print(f'Unique summaries: {len(set(s[\"summary\"] for s in w))}')
for s in w[:5]:
    print(f'  {s[\"symbol\"]}: {s[\"summary\"][:150]}')
    print(f'    keywords: {s.get(\"keywords\", [])[:8]}')
"
```

### What to look for:
- **Unique summaries** — Each symbol should have a DIFFERENT summary. If all say "Serves as the main entry point", the enricher prompt is broken.
- **Semantic keywords** — Keywords should include terms from the summary, not just the symbol name.
- **Summary quality** — Should describe WHAT the symbol does, not HOW.
- **Coverage** — At least some symbols should have summaries. For small projects, aim for 50%.

### Red flags:
- 0 symbols with summaries — Enricher not running or failing silently
- All identical summaries — LLM prompt needs `UNIQUE` constraint
- Keywords are just symbol name split — LLM text not being extracted

---

## 9. CLI Command Tests

```bash
cd /home/kyle/Projects/auto-doc-tool
```

### 9a. Search
```bash
ruby -I lib exe/auto-doc search Extension /home/kyle/Projects/pi-manager --source 2>&1
```
**Check:** Results include `source_grep` matches (score 10) AND `vector` matches (score 25-100). Should find `ExtensionsController`.

### 9b. Agent Query
```bash
ruby -I lib exe/auto-doc agent "what does ApplicationController do" /home/kyle/Projects/pi-manager 2>&1
```
**Check:** Returns intent (`describe_symbol`) + vector entry with summary. Summary should be meaningful.

```bash
ruby -I lib exe/auto-doc agent "what depends on Extension" /home/kyle/Projects/pi-manager 2>&1
```
**Check:** Returns reverse dependency results.

```bash
ruby -I lib exe/auto-doc agent "list all symbols" /home/kyle/Projects/pi-manager 2>&1
```
**Check:** Returns all symbols from INDEX.md.

### 9c. Query
```bash
ruby -I lib exe/auto-doc query auto_doc /home/kyle/Projects/pi-manager 2>&1
```
**Check:** Shows INDEX.md line count, SUMMARY.md line count, VECTORS.json symbol count.

### 9d. Diagram Display
```bash
ruby -I lib exe/auto-doc diagram deps /home/kyle/Projects/pi-manager 2>&1 | head -20
```
**Check:** Returns the full Mermaid source. Should see edge definitions.

### 9e. Audit
```bash
ruby -I lib exe/auto-doc audit /home/kyle/Projects/pi-manager 2>&1
```
**Check:** Shows coverage percentage, threshold, worst offenders. For non-auto-doc projects, 0% is expected.

### 9f. Diff
```bash
ruby -I lib exe/auto-doc diff HEAD /home/kyle/Projects/pi-manager 2>&1
```
**Check:** Shows "No Ruby files changed" or lists changed files with status.

### 9g. Orphans
```bash
ruby -I lib exe/auto-doc orphans /home/kyle/Projects/pi-manager 2>&1
```
**Check:** Lists files not documented or imported. For a typical Rails app, config/ files should appear.

### 9h. Tree
```bash
ruby -I lib exe/auto-doc tree /home/kyle/Projects/pi-manager 2>&1 | head -20
```
**Check:** Box-drawing tree showing directory structure.

### 9i. Verify (generate + audit)
```bash
ruby -I lib exe/auto-doc verify /home/kyle/Projects/pi-manager 2>&1
```
**Check:** Runs generate then audit in one step. Should complete without error.

---

## 10. Search Quality — Semantic Matching

```bash
# Search by concept, not symbol name
ruby -I lib exe/auto-doc search "extension lifecycle" /home/kyle/Projects/pi-manager 2>&1
ruby -I lib exe/auto-doc search "data transformation" /home/kyle/Projects/pi-manager 2>&1
ruby -I lib exe/auto-doc search "install" /home/kyle/Projects/pi-manager 2>&1
```

### What to look for:
- Results should include `keyword_match` or `vector` score types (not just `source_grep`)
- Semantic matches should surface symbols whose LLM summary describes the concept
- If only `source_grep` results appear, vector keywords aren't including summary text

---

## 11. Fail-Fast Mode Test

```bash
# Create a config with fail_fast: true
echo 'llm:
  fail_fast: true' > /tmp/test_failfast.yml
cp /tmp/test_failfast.yml /home/kyle/Projects/pi-manager/.autodoc.yml
unset AUTO_DOC_DISABLE_LLM
ruby -I lib exe/auto-doc generate /home/kyle/Projects/pi-manager --format autodoc 2>&1
rm /home/kyle/Projects/pi-manager/.autodoc.yml
```

### What to look for:
- Should RAISE an error when LLM fails, not silently fall back
- Error message should describe which LLM call failed
- Generation should STOP immediately

---

## 12. Per-Module Summary Uniqueness

```bash
python3 -c "
import json, os, glob
base = '/home/kyle/Projects/pi-manager/.autodoc'
for vectors_file in glob.glob(f'{base}/**/vectors.json', recursive=True):
    mod = os.path.relpath(vectors_file, base).replace('/vectors.json', '') or '(root)'
    d = json.load(open(vectors_file))
    sym = d.get('symbols', [])
    w = [s for s in sym if isinstance(s, dict) and s.get('summary')]
    unique = len(set(s['summary'] for s in w)) if w else 0
    print(f'{mod}: {len(w)} with summaries, {unique} unique')
"
```

### What to look for:
- Each module should have unique (not repeated) summaries
- Per-module vectors.json files should have summaries (not just root VECTORS.json)

---

## 13. Cross-Project Testing

After verifying against pi-manager (Rails), also test:

```bash
# Python project
ruby -I lib exe/auto-doc generate /path/to/python-project --format docs 2>&1

# JavaScript/TypeScript project
ruby -I lib exe/auto-doc generate /path/to/js-project --format docs 2>&1

# Go project
ruby -I lib exe/auto-doc generate /path/to/go-project --format docs 2>&1
```

### What to check:
- GenericScanner should detect language from file extensions
- AGENTS.md should describe the project in its own language's terms
- VECTORS.json should have symbols from the detected language

---

## 14. Self-Documentation (auto-doc on itself)

```bash
cd /home/kyle/Projects/auto-doc-tool
unset AUTO_DOC_DISABLE_LLM
ruby -I lib exe/auto-doc generate . --format docs 2>&1
```

### What to check:
- Should generate .docs/ for auto-doc itself
- AGENTS.md should describe auto-doc accurately
- VECTORS.json should have summaries for auto-doc's own symbols
- All diagrams should be present (deps, class, C4 context, C4 container)

---

## Feedback Checklist (for bob_26)

When filing issues for bob, use this standardized format:

| Category | Issue | Severity | Evidence |
|----------|-------|----------|----------|
| Content | LLM summaries all identical | Critical | `len(set(summaries)) == 1` |
| Content | Static fallback text | Major | "Ruby source files in..." in output |
| Content | "developer to fill in" | Major | No LLM content in AGENTS.md |
| Diagram | ERD missing for Rails | Major | schema.db exists but no erd.mmd |
| Diagram | C4 diagram empty | Medium | Header only, no content |
| Diagram | Dep graph has no edges | Medium | `graph TB A[A]` only |
| CLI | Search misses vector matches | Medium | No `keyword_match` score in results |
| CLI | Command crashes | Critical | Non-zero exit code |
| Performance | Generation timeout | Medium | Takes >10 min |
| Schema | schema.json empty | Major | 2-byte file (empty JSON) |
| Vector | No LLM summaries | Major | All summaries empty/missing |

---

## Version History

| Date | Author | Changes |
|------|--------|---------|
| 2026-07-16 | pi-kyle | Initial playbook — pi-manager Rails verification |
