# Auto-Documentation Tool — Implementation Plan
## Ruby Gem: `auto-doc`

**Based on:** Research compilation from 4 agents (2 scouts + 2 reviewers)  
**Execution:** Coder uses `bob_26 chat "prompt" --directory /path --no-follow --json` for all work

---

# PHASE 1 — MVP Implementation Plan

## Design Decisions Resolved

| Decision | Choice | Rationale |
|----------|--------|-----------|
| In-place vs draft files | **Draft in `.autodoc/`** | Developers review generated drafts and commit as their own edits. Never override source-of-truth docs automatically. |
| Module root detection | **Directories with ≥3 code files or a Gemfile/Gemfile.lock** | Heuristic-based; configurable via `config.yml`. Skips spec/, test/, vendor/, node_modules/ by default. |
| Output format | **Markdown (AGENTS.md + README.md) + Mermaid .mmd for diagrams** | Standard GitHub-flavored markdown renders everywhere. `.mmd` files auto-render in GitHub/GitLab. |
| Configuration | **Convention-over-configuration YAML at `.autodoc.yml`** | Auto-discovered from repo root or parent dirs. CLI flags override config: `--exclude vendor`, `--include-spec`. |
| Audit output | **Human-readable table + machine-parseable JSON** (`report.json`) | Human-readable for quick review; JSON for CI integration. Exit code 1 if unmet thresholds breached. |
| Incremental strategy | **Full regeneration with stale detection** | Store last-generation timestamps in frontmatter. `--incremental` flag skips unchanged directories. Default: always full pass. |

---

# GEM FILE STRUCTURE

```
auto-doc/                          # Gem root directory
├── auto-doc.gemspec               # Gem spec: name 'auto-doc', version 0.1.0
├── Rakefile                       # rake build, rake test, rake install tasks
├── .gitignore                     # Ignore *.gem, /pkg/, .autodoc/*/generated/
│
├── bin/auto-doc                   # CLI executable entry point (shebang + requires)
│
├── lib/
│   ├── auto_doc.rb                # Gem entry: loads all submodules, defines constants
│   │
│   └── auto_doc/
│       ├── cli.rb                 # Thor-based CLI with subcommands
│       ├── config.rb              # Config loader (.autodoc.yml parser)
│       │
│       ├── analyzer/              # Source code analysis (stdlib only for v1)
│       │   ├── source_parser.rb   # Ripper-based Ruby AST parser — extracts classes, modules, methods, constants
│       │   ├── import_extractor.rb # Extracts require/include/extend/use statements from source
│       │   └── yard_reader.rb     # Reads existing YARD/doc comments (/// style) and doc strings
│       │
│       ├── generator/             # Documentation file generators
│       │   ├── agents_md_generator.rb  # Generates AGENTS.md per directory
│       │   ├── readme_generator.rb     # Generates README.md at module root directories
│       │   └── diagram_generator.rb    # Generates dependency DAG Mermaid .mmd files
│       │
│       ├── reporter/              # Audit report output
│       │   ├── audit_reporter.rb      # Human-readable table + JSON report generation
│       │   └── completeness_checker.rb # Checks public symbols for doc coverage
│       │
│       └── utils/                 # Shared utilities
│           ├── file_tree_builder.rb    # Builds indented directory tree structure
│           └── yaml_config_loader.rb   # Reads and validates .autodoc.yml config
│
├── templates/                     # Mustache-style ERB templates for generated files
│   ├── agents_md_template.erb     # AGENTS.md template with frontmatter + sections
│   ├── readme_template.erb        # README.md template with file tree + module summary
│   └── diagram_dag_template.erb   # Dependency DAG Mermaid .mmd template
│
├── spec/                          # RSpec tests
│   ├── auto_doc_spec.rb           # Gem entry point tests
│   ├── auto_doc/
│   │   ├── cli_spec.rb            # CLI subcommand argument parsing
│   │   ├── config_spec.rb         # Config loading from YAML + CLI flags
│   │   ├── analyzer/
│   │   │   ├── source_parser_spec.rb  # Ripper parsing correctness tests
│   │   │   ├── import_extractor_spec.rb # Require/include extraction tests
│   │   │   └── yard_reader_spec.rb    # Doc comment extraction tests
│   │   ├── generator/
│   │   │   ├── agents_md_generator_spec.rb  # Generated AGENTS.md output format
│   │   │   ├── readme_generator_spec.rb     # Generated README.md output format
│   │   │   └── diagram_generator_spec.rb    # Mermaid DAG syntax correctness
│   │   ├── reporter/
│   │   │   ├── audit_reporter_spec.rb       # Report formatting tests
│   │   │   └── completeness_checker_spec.rb # Doc coverage calculation
│   │   └── utils/
│   │       └── file_tree_builder_spec.rb    # Indented tree output tests
│   └── spec_helper.rb             # Test setup + fixtures
│
└── fixtures/                      # Test fixtures with sample Ruby projects
    ├── simple_rails_app/          # Minimal Rails-like structure for testing
    │   ├── app/models/user.rb     # Sample model file for parser testing
    │   ├── app/controllers/       # Sample controller for import extraction
    │   └── config/routes.rb       # Route definitions for analysis
    └── minimal_gem/               # Gem-style project with lib/ structure
        ├── lib/minimal_gem.rb     # Entry point
        └── lib/minimal_gem/       # Submodules directory
```

---

# MODULE DETAILS — PHASE 1

## 1. `lib/auto_doc/cli.rb` — CLI Interface

**Responsibility:** Thor-based command-line interface for auto-doc subcommands.

**Subcommands:**
```ruby
class CLI < Thor
  desc "init [PATH]",     "Initialize .autodoc.yml config file in directory"
  def init(path = ".")    end

  desc "generate [PATH]",  "Generate AGENTS.md + README.md + diagrams for all module directories"
  method_option :incremental, type: :boolean, default: false
  method_option :exclude,     type: :array,   default: %w[spec test vendor node_modules]
  def generate(path = ".") end

  desc "audit [PATH]",     "Run documentation completeness audit on public symbols"
  method_option :threshold, type: :numeric,  default: 80  # min % coverage for CI gate
  def audit(path = ".")    end

  desc "orphans [PATH]",   "Find files with no import edges AND no references in generated docs"
  def orphans(path = ".") end

  desc "diff [SINCE]",     "Show documentation drift since a git ref or last generation"
  def diff(since)          end

  desc "version",          "Print gem version"
  def version              end
end
```

**Key implementation notes:**
- Uses Thor for argument parsing
- Each subcommand delegates to the appropriate generator/reporter module
- Path defaults to current directory; resolves relative paths against CWD
- Returns non-zero exit code on audit threshold failures

---

## 2. `lib/auto_doc/config.rb` — Configuration

**Responsibility:** Load `.autodoc.yml` config file with fallback conventions.

**Config file format (`config/.autodoc.yml`):**
```yaml
# Auto-doc configuration for a project

# Which directories are module roots worth documenting?
module_roots:
  - "app"          # Rails app directory
  - "lib"          # Library code  
  - "bin"          # Executable scripts

# Directories to always skip during analysis
exclude_patterns:
  - "vendor/**/*"
  - "node_modules/**/*"
  - "spec/**/*"    # Override with --include-spec flag

# Output settings
output:
  directory: ".autodoc"        # Where generated files are written
  format: "markdown"           # Always markdown for v1

# Audit thresholds (for CI gating)
audit:
  min_doc_coverage: 80         # percentage of public symbols with docs
  max_module_size: 50          # max number of public methods per module

# Diagram settings
diagrams:
  generate_dag: true           # Generate dependency DAG (default)
  diagram_directory: "diagrams"
```

**Loading strategy:**
- Walk up directory tree from source path looking for `.autodoc.yml`
- Merge CLI flags on top of config file values (flags win)
- Apply defaults for any missing keys

---

## 3. `lib/auto_doc/analyzer/source_parser.rb` — Ruby AST Parser

**Responsibility:** Parse Ruby source files using Ripper (stdlib, zero deps). Extract classes, modules, methods, constants, and their signatures.

```ruby
class AutoDoc::Analyzer::SourceParser
  def initialize(file_path)
    @file_path = file_path
    @content = File.read(file_path)
  end

  # Returns array of { type: "class"|"module", name: String, 
  #                     line:, methods: [], parent_modules: [] }
  def parse_classes
    ripper = Ripper.new(@content)
    Ripper.parse(ripper).map { |node| extract_class(node) }.compact
  end

  # Returns array of method definitions with signatures
  def parse_methods(class_or_module_name)
    # Extracts: { name:, visibility: :public/:private/:protected, 
  #             params:, return_type: nil, line:, has_doc?: bool }
  end

  # Returns list of constant names defined in this file
  def parse_constants
  end

  # Returns the module namespace path for a class/module
  def namespace_path(class_name)
  end
end
```

**Key implementation notes:**
- Uses Ripper from Ruby stdlib — no external gems needed
- Handles basic Ruby syntax: class declarations, module definitions, method definitions, constants
- Known limitation: Does NOT parse dynamic patterns (`const_set`, `define_method`, `method_missing`) — documented as v1 gap
- For Rails apps, also extracts ActiveRecord model associations from `has_one`/`belongs_to`/`has_many` keywords (simple string match)

---

## 4. `lib/auto_doc/analyzer/import_extractor.rb` — Import Extraction

**Responsibility:** Extract require/include/extend/use statements to build dependency edges between modules.

```ruby
class AutoDoc::Analyzer::ImportExtractor
  def initialize(file_path)
    @file_path = file_path
    @content = File.read(file_path)
  end

  # Returns array of { statement: "include Enumerable", type: :include, line:, target: "Enumerable" }
  def extract_includes
    @content.scan(/^(?:\s*)(?:(private_)?(include|prepend|extend))\b\s+(.+)$/).map do |priv, action, target|
      { statement: "#{action} #{target}", type: action.to_sym, line:, target: }
    end
  end

  # Returns array of require paths
  def extract_requires
    @content.scan(/require(?:_relative)?\s+['"](.+)['"]/).flatten.map do |path|
      { path:, statement: "require '#{path}'", type: :require }
    end
  end

  # Build module dependency graph for entire directory tree
  def self.build_dependency_graph(directory, config)
    # Returns Hash: { "lib/foo/bar.rb" => ["include Baz", "require_relative '../utils'"] }
  end
end
```

---

## 5. `lib/auto_doc/analyzer/yard_reader.rb` — Doc Comment Extraction

**Responsibility:** Read existing YARD/doc comments from source files. For Ruby, this means extracting comment blocks that precede class/module/method definitions.

```ruby
class AutoDoc::Analyzer::YardReader
  def initialize(file_path)
    @file_path = file_path
    @content = File.read(file_path)
  end

  # Returns array of { target_type: "class"|"module"|"method", 
  #                     target_name: String, text:, line:, has_summary?: bool }
  def extract_doc_comments
    comments = []
    lines = @content.lines.each_with_index
    i = 0
    while i < lines.length
      if lines[i][1]&.match?(/^(\s*)#(?! *~\*+|# *\!).*(?<target>\S.*)$/)
        summary = match[:summary]
        target_type = extract_target_type(match[:target])
        comments << { target_name:, text: summary.strip, line: lines[i][0], 
                      target_type:, has_summary?: !summary.nil? }
      end
      i += 1
    end
    comments
  end

  private
  
  def extract_target_type(target_str)
    case target_str
    when /^def\s/ then "method"
    when /^\w*[A-Z]\w*$/ then "class_or_module"  
    else "unknown"
    end
  end
end
```

**Note:** This is simplified for v1. A full YARD parser would use the `yard` gem (Phase 2). This extracts basic comment blocks without structured tag parsing (`@param`, `@return`, etc.).

---

## 6. `lib/auto_doc/generator/agents_md_generator.rb` — AGENTS.md Generator

**Responsibility:** Generate an AGENTS.md file for each module directory with standardized sections.

**Output format per directory:**
```markdown
# Module: <Directory Name>

> **Generated by auto-doc v0.1.0** on {date}  
> Source files: {count} | Public symbols: {count}

## Purpose
{Auto-inferred or empty skeleton — developer fills in}

## Structure
{File tree listing from utils/file_tree_builder}

## Dependencies
| Module | Type | Reference |
|--------|------|-----------|
| {import_name} | {include/require} | {line_number} |

## Public API Surface
| Symbol | Type | Documented | Line |
|--------|------|------------|------|
| ClassName | class | ✅ / ❌ | line_num |
| method_name(params) | method | ✅ / ❌ | line_num |

## Key Files
- `lib/foo/bar.rb` — Purpose inferred from file name (developer to refine)

---
*Generated by auto-doc. Review and commit these drafts as your documentation.*
```

**Key methods:**
```ruby
class AutoDoc::Generator::AgentsMdGenerator
  def self.generate_for_directory(dir_path, config, all_analyses)
    modules = extract_modules(dir_path)                    # Get list of module directories
    modules.map do |module_dir|
      analyses = load_analyses(module_dir)                 # SourceParser + ImportExtractor + YardReader results
      render_agents_md(module_dir, analyses, config)       # Apply template with ERB
    end
  end

  def self.render_agents_md(dir, analyses, config)
    erb_template = File.read("templates/agents_md_template.erb")
    ERB.new(erb_template).result(binding)
  end
end
```

---

## 7. `lib/auto_doc/generator/readme_generator.rb` — README Generator

**Responsibility:** Generate a README.md at the ROOT of each module directory (not every subdirectory — only directories flagged as "module roots" by config or heuristic).

**Output format for a module root like `app/models/`:**
```markdown
# Models

## Overview
{Auto-inferred from directory name and contained files}

## Files
| File | Classes/Modules | Methods | Documented? |
|------|-----------------|---------|-------------|
| user.rb | User(1) | create, find_by_email(2) | ❌ |
| post.rb | Post(1) | title, body, publish(3) | ✅ |

## Generated Diagrams
See [../diagrams/deps.mmd](../diagrams/deps.mmd) for module dependency graph.

---
*Generated by auto-doc v0.1.0 on {date}.*
```

**Key methods:**
```ruby
class AutoDoc::Generator::ReadmeGenerator
  def self.generate_for_module_roots(module_root_dirs, analyses)
    module_root_dirs.map do |root_dir|
      files_in_dir = Dir.glob("#{root_dir}/lib/**/*.rb") + Dir.glob("#{root_dir}/*.rb").select { |f| File.file?(f) }
      
      if files_in_dir.any?
        analysis = analyses[root_dir] || analyze_directory(root_dir)
        render_readme(root_dir, analysis)
      end
    end.compact
  end
end
```

---

## 8. `lib/auto_doc/generator/diagram_generator.rb` — Dependency DAG Generator

**Responsibility:** Generate a single Mermaid dependency DAG diagram showing top-level module hierarchy and cross-references between modules.

**Output format (Mermaid `.mmd`):**
```mermaid
graph TB
    subgraph "app"
        app[App Root<br/>12 files]
        subgraph "models"
            models[Models<br/>8 classes]
        end
        subgraph "controllers" 
            controllers[Controllers<br/>5 modules]
        end
        subgraph "services"
            services[Services<br/>3 classes]
        end
    end
    
    subgraph "lib"
        lib[Lib Root<br/>4 files]
        subgraph "utils"
            utils[Utils<br/>6 modules]
        end
    end

    models -->|include| controllers
    services -->|require_relative| utils
    controllers -->|use| models
    
    style app fill:#e1f5fe
    style lib fill:#f3e5f5
```

**Key methods:**
```ruby
class AutoDoc::Generator::DiagramGenerator
  def self.generate_dag(directory_structure, dependency_graph)
    # directory_structure: Hash mapping dir paths to file/module counts
    # dependency_graph: Hash from ImportExtractor with module-level imports
    
    mermaid_output = render_dag_template(directory_structure, dependency_graph)
    
    { 
      content: mermaid_output, 
      output_path: ".autodoc/diagrams/deps.mmd" 
    }
  end
  
  private
  
  def self.render_dag_template(structure, graph)
    template = <<~MERMAID
    graph TB\n
    #{generate_subgraphs(structure)}\n
    #{generate_edges(graph)}\n
    MERMAID
  end
end
```

---

## 9. `lib/auto_doc/reporter/audit_reporter.rb` — Audit Reporter

**Responsibility:** Generate documentation coverage reports for CI quality gates.

```ruby
class AutoDoc::Reporter::AuditReporter
  def self.generate(project_dir, config, analyses)
    uncovered = []
    
    all_analyses.each do |dir, analysis|
      analysis.public_symbols.each do |symbol|
        unless symbol.has_doc?
          uncovered << { 
            file: symbol.file_path, 
            symbol: symbol.name, 
            type: symbol.type,
            line: symbol.line_number 
          }
        end
      end
    end
    
    total = all_analyses.sum { |_, a| a.public_symbols.count }
    covered = total - uncovered.count
    coverage_pct = (covered.to_f / total * 100).round(1)
    
    { 
      total_symbols: total,
      documented: covered, 
      undocumented: uncovered.count,
      coverage_percent: coverage_pct,
      failures: uncovered,
      passed_threshold?: coverage_pct >= config.audit[:min_doc_coverage]
    }
  end
  
  # Outputs human-readable table
  def self.format_text(report)
    "Auto-Doc Audit Report\n" \
    "=====================\n" \
    "Coverage: #{report[:coverage_percent]}% (#{report[:documented]}/#{report[:total_symbols]} symbols)\n" \n
    "Threshold: #{config.audit[:min_doc_coverage]}%\n" \n
    report[:passed_threshold?] ? "✅ PASS" : "❌ FAIL\n\nUndocumented:\n" + format_failures(report[:failures])
  end
  
  # Outputs JSON for CI
  def self.format_json(report)
    JSON.pretty_generate(report.to_h)
  end
end
```

---

## 10. `lib/auto_doc/utils/file_tree_builder.rb` — Directory Tree Builder

**Responsibility:** Build indented directory tree text representation (same format as `tree` command output). Used in AGENTS.md and README.md files.

```ruby
class AutoDoc::Utils::FileTreeBuilder
  def self.build(path, depth: nil, exclude_patterns: %w[.git node_modules vendor])
    lines = ["."]
    walk_dir(Pathname.new(path), "", depth || Float::INFINITY, exclude_patterns, lines)
    lines.join("\n")
  end
  
  private
  
  def self.walk_dir(dir, indent, max_depth, excludes, lines)
    return if dir.to_s.split('/').length > max_depth
    
    entries = Dir.glob("#{dir}/*").sort.reject do |entry|
      basename = File.basename(entry)
      excludes.any? { |pat| basename.match?(Regexp.new(pat)) }
    end
    
    entries.each do |entry|
      name = File.basename(entry)
      if File.directory?(entry)
        lines << "#{indent}├── #{name}/"
        walk_dir(entry, "#{indent}│   ", max_depth, excludes, lines)
      else
        icon = file_icon(name)
        lines << "#{indent}#{icon} #{name}"
      end
    end
  end
  
  FILE_ICONS = {
    ".rb" => "⚓",
    ".erb" => "🗺️",
    ".yml" => "⚙️",
    ".json" => "📋",
    ".md" => "📝",
  }.freeze
  
  private_class_method :file_icon
end
```

---

# TEMPLATE DETAILS

## `templates/agents_md_template.erb`
```erb
<%# auto-doc template for AGENTS.md %>
# <%= module_name %>

> **Generated by auto-doc v0.1.0** on <%= generated_at %>  
> Source files: <%= source_file_count %> | Public symbols: <%= public_symbol_count %>

## Purpose
_This directory contains:_ <%= purpose_summary || "developer to fill in" %>

## Structure
```
<%= tree_text %>
```

## Dependencies
| Module | Type | Reference |
|--------|------|-----------|
<% if dependencies.any? %>
<% dependencies.each do |dep| %>
| <%= dep[:target] %> | <%= dep[:type] %> | line <%= dep[:line] %> |
<% end %>
<% else %>
| _No external dependencies detected_ | — | — |
<% end %>

## Public API Surface
| Symbol | Type | Documented | Line |
|--------|------|------------|------|
<% if public_symbols.any? %>
<% public_symbols.each do |sym| %>
| <%= sym[:name] %> | <%= sym[:type] %> | <%= sym[:has_doc?] ? "✅" : "❌" %> | <%= sym[:line] %> |
<% end %>
<% else %>
| _No public symbols found (v1 limitation: dynamic Ruby patterns not parsed)_ | — | — | — |
<% end %>

---
*Generated by auto-doc. Review and commit these drafts as your documentation.*
```

## `templates/readme_template.erb`
```erb
# <%= module_name %>

## Overview
<%= overview_text || "developer to fill in" %>

## Files
| File | Classes/Modules | Methods | Documented? |
|------|-----------------|---------|-------------|
<% files.each do |f| %>
| <%= f[:name] %> | <%= f[:class_count] %> | <%= f[:method_count] %> | <%= f[:any_documented?] ? "✅" : "❌" %> |
<% end %>

---
*Generated by auto-doc v0.1.0 on <%= generated_at %>. Review and commit as your documentation.*
```

## `templates/diagram_dag_template.erb`
```erb
graph TB<% subgraphs.each do |group| %>
    subgraph "<%= group[:name] %>"<% group[:children].each do |child| %>
        <%= child[:id>]<%= child[:name]>[<%= child[:label>]>]<% end %>
    end<% end %>

<% edges.each do |edge| %>
    <%= edge[:from] %> -->|<%= edge[:type] %>| <%= edge[:to] %>
<% end %>

<style>
  graph TB;
<% groups.each { |g| puts "    style #{g[:id]} fill:#{g[:color]}" } %>
</style>
```

---

# EXECUTION STEPS — BOB_26 CLI COMMANDS FOR CODER

## Step 1: Create Gem Skeleton
**Command:** 
```bash
bob_26 chat "Create the auto-doc gem skeleton at /home/kyle/Projects/auto-doc-tool/:
1. Run `bundle gem auto-doc --test=rspec --skip-bundle` in that directory
2. Update the gemspec with proper metadata, dependencies (none for Phase 1)
3. Create bin/auto-doc executable with shebang line requiring lib/auto_doc.rb  
4. Create Rakefile with build/test/install tasks
5. Run `bundle install`

The gem is named 'auto-doc', version 0.1.0. No external dependencies for Phase 1." --directory /home/kyle/Projects/auto-doc-tool --no-follow --json
```
**Expected files:** `auto-doc.gemspec`, `bin/auto-doc`, `lib/auto_doc.rb`, `Rakefile`, `.rspec`, `spec/spec_helper.rb`

---

## Step 2: Create Config + Utils Modules  
**Command:**
```bash
bob_26 chat "Create the config and utils modules for auto-doc gem at /home/kyle/Projects/auto-doc-tool/:

1. lib/auto_doc/config.rb - Load .autodoc.yml with fallback defaults, CLI flag override
   - Class method: AutoDoc::Config.load(path) -> Hash
   - Defaults: output.dir='.autodoc', exclude_patterns=['vendor','spec'], audit.threshold=80
   
2. lib/auto_doc/utils/file_tree_builder.rb - Build indented directory tree (tree command format)
   - Class method: build(path, depth=nil, exclude_patterns=[]) -> String
   
3. lib/auto_doc/utils/yaml_config_loader.rb - Simple YAML file reader with validation
   - Class method: load(file_path) -> Hash  
   - Validates expected keys exist
   
Create fixtures/sample_ruby_project/ directory with a minimal Rails-like structure for testing.

Verify with: ruby -I lib bin/auto-doc version should print 'auto-doc 0.1.0'" --directory /home/kyle/Projects/auto-doc-tool --no-follow --json
```
**Expected files:** `lib/auto_doc/config.rb`, `lib/auto_doc/utils/file_tree_builder.rb`, 
`lib/auto_doc/utils/yaml_config_loader.rb`, `fixtures/sample_ruby_project/app/models/user.rb`

---

## Step 3: Create Analyzer Modules
**Command:**
```bash
bob_26 chat "Create the analyzer modules for auto-doc gem at /home/kyle/Projects/auto-doc-tool/:

1. lib/auto_doc/analyzer/source_parser.rb - Ripper-based Ruby AST parser
   - Extracts classes, modules, methods, constants from .rb files
   - Returns structured data: [{name:, type:, line:, parent_modules:, methods:[]}]
   - Known v1 limitation documented in comments (dynamic Ruby patterns not parsed)

2. lib/auto_doc/analyzer/import_extractor.rb - Extract require/include/extend statements
   - Finds: include X, prepend Y, extend Z, require_relative "path"
   - Builds module-level dependency graph from directory of .rb files
   
3. lib/auto_doc/analyzer/yard_reader.rb - Extract doc comments (comment blocks before defs)
   - Parses # comment lines preceding class/module/method definitions
   - Returns [{target_type:, target_name:, text:, line:, has_summary?}]
   
4. spec/auto_doc/analyzer/source_parser_spec.rb - Test Ripper parsing on sample files
5. spec/auto_doc/analyzer/import_extractor_spec.rb - Test require/include extraction
6. spec/auto_doc/analyzer/yard_reader_spec.rb - Test doc comment extraction

Run: bundle exec rspec to verify all analyzer tests pass." --directory /home/kyle/Projects/auto-doc-tool --no-follow --json  
```
**Expected files:** `lib/auto_doc/analyzer/source_parser.rb`, `lib/auto_doc/analyzer/import_extractor.rb`, 
`lib/auto_doc/analyzer/yard_reader.rb`, + corresponding spec files

---

## Step 4: Create Generator Modules
**Command:**
```bash
bob_26 chat "Create the generator modules and templates for auto-doc gem at /home/kyle/Projects/auto-doc-tool/:

1. lib/auto_doc/generator/agents_md_generator.rb - Generate AGENTS.md per module directory
   - Uses SourceParser + ImportExtractor + YardReader results
   - Applies agents_md_template.erb template
   - Writes to .autodoc/<module_path>/AGENTS.md
   
2. lib/auto_doc/generator/readme_generator.rb - Generate README.md at module roots only
   - Only generates for directories flagged as module_roots in config
   - Includes file table and dependency references
   - Writes to .autodoc/<module_path>/README.md

3. lib/auto_doc/generator/diagram_generator.rb - Generate dependency DAG Mermaid diagram  
   - Takes dependency graph from ImportExtractor.build_dependency_graph()
   - Renders Mermaid syntax to .autodoc/diagrams/deps.mmd
   
4. templates/agents_md_template.erb - AGENTS.md ERB template (with frontmatter, purpose, 
   dependencies table, public API surface table)
5. templates/readme_template.erb - README.md ERB template (overview, file table)  
6. templates/diagram_dag_template.erb - Mermaid DAG ERB template

7. spec/generator/agents_md_generator_spec.rb - Verify AGENTS.md output format
8. spec/generator/readme_generator_spec.rb - Verify README.md output format
9. spec/generator/diagram_generator_spec.rb - Verify .mmd syntax correctness

Run: bundle exec rspec to verify all generator tests pass." --directory /home/kyle/Projects/auto-doc-tool --no-follow --json
```
**Expected files:** `lib/auto_doc/generator/agents_md_generator.rb`, `readme_generator.rb`, 
`diagram_generator.rb`, `templates/*.erb`, + corresponding spec files

---

## Step 5: Create Reporter Module + CLI Integration  
**Command:**
```bash
bob_26 chat "Create the reporter module and integrate everything into CLI for auto-doc gem at /home/kyle/Projects/auto-doc-tool/:

1. lib/auto_doc/reporter/audit_reporter.rb - Documentation coverage audit report
   - Compares public symbols vs doc comment presence per file/directory  
   - Generates human-readable text table + JSON (report.json)
   - Returns structured result with passed_threshold? flag
   - Used by CLI audit subcommand
   
2. lib/auto_doc/reporter/completeness_checker.rb - Helper that calculates coverage percentages
   - Class method: check_coverage(analyses, threshold=80) -> {coverage_pct:, failures:[], passed?:}
   
3. Update bin/auto-doc and lib/auto_doc/cli.rb to wire up subcommands:
   - auto-doc init  → creates default .autodoc.yml if not exists
   - auto-doc generate <path> → runs generators for all module dirs, writes .autodoc/
   - auto-doc audit <path>    → generates report, exits 0 or 1 based on threshold
   - auto-doc version → prints gem version
   - CLI flag parsing: --exclude vendor, --threshold 80
   
4. Update lib/auto_doc/cli_spec.rb with subcommand integration tests
5. Add acceptance test: run 'bundle exec ruby bin/auto-doc generate' on fixtures/sample_ruby_project/
   and verify .autodoc/ directory is created with expected files

Run: bundle exec rspec AND manually test: cd fixtures/sample_ruby_project && 
../bin/auto-doc generate ../fixtures/sample_ruby_project" --directory /home/kyle/Projects/auto-doc-tool --no-follow --json
```
**Expected files:** `lib/auto_doc/reporter/audit_reporter.rb`, `completeness_checker.rb`, 
updated `bin/auto-doc`, updated `lib/auto_doc/cli.rb`, integration tests, acceptance test

---

## Verification Checklist (After All Steps)
```bash
cd /home/kyle/Projects/auto-doc-tool
bundle install                                    # Should succeed with no external deps
bundle exec rake build                            # Gem builds successfully  
bundle exec rspec                                 # All tests pass
cd fixtures/sample_ruby_project                 
../bin/auto-doc generate .                        # Creates .autodoc/ with AGENTS.md, README.md, diagrams/deps.mmd
../bin/auto-doc audit .                           # Shows coverage report
../bin/auto-doc version                           # Prints "auto-doc 0.1.0"
```

---

# PHASE 2 — Useful Additions (Deferred from Phase 1)

| Feature | Description | Dependencies |
|---------|-------------|--------------|
| **Deep AST parsing** | Add tree-sitter for Ruby (`ruby-tree-sitter` gem) to handle more complex patterns beyond Ripper's capabilities | New gem dependency |
| **Staleness detection** | Compare file modification timestamps against `.autodoc/generation_timestamps.json`; flag directories where source changed but docs didn't | Built on timestamp comparison logic |
| **Additional Mermaid diagrams** | ERD from migration/schema parsing, class hierarchy diagram (if deterministic) | Requires schema/parser enhancements |
| **Incremental generation** | Skip unchanged directories based on timestamps; only regenerate stale modules | Depends on staleness detection |
| **Better YARD support** | Use the `yard` gem for structured doc comment extraction (`@param`, `@return`, `@yield`) | New gem dependency |

# PHASE 3 — Nice-to-Have (Deferred)

| Feature | Description | Dependencies |  
|---------|-------------|--------------|
| **Semantic search layer** | Vector embeddings of documentation content, searchable via natural language queries | Embedding model + vector DB integration |
| **CI quality gate** | GitHub Actions workflow that runs `auto-doc audit` on PRs and fails if coverage < threshold | CI configuration (separate from gem) |
| **Orphan file detection** | Find source files with zero import edges AND no references in generated docs | Graph analysis beyond DAG |
| **Multi-language support** | Extend analyzer to parse Go, TypeScript, etc. via language-specific parsers | Language parser gems/plugins |
| **Doc consistency checking** | Cross-reference: verify module X documented in dir Y but imported from Z matches expectations | Knowledge graph layer |
| **Interactive mode** | Prompt developer for auto-inferred "purpose" text before writing draft docs | Interactive CLI enhancement |

---

# KNOWN v1 LIMITATIONS (Documented in README)

1. **Dynamic Ruby patterns not parsed**: Ripper cannot detect methods created via `define_method`, constants set via `const_set`, or dynamic class inheritance — documented as a known gap, not hidden.
2. **One diagram type only**: Phase 1 generates dependency DAG diagrams only. ERD/classDiagram come in Phase 2.
3. **No semantic search**: Generated docs are static text files (grep-able). Vector/search layer is Phase 3+.
4. **Rust-only was the original research target but pivoted to Ruby-first**: The gem targets ANY Ruby/Rails project regardless of whether it's a Rails app or standalone gem.

---

# SUCCESS CRITERIA FOR PHASE 1 MVP

- [ ] Gem installs via `gem build && gem install auto-doc-0.1.0.gem`  
- [ ] `auto-doc init` creates `.autodoc.yml` in target project
- [ ] `auto-doc generate <path>` produces valid AGENTS.md, README.md, and diagrams/deps.mmd for a sample Ruby/Rails project
- [ ] `auto-doc audit <path>` returns exit code 0 when coverage >= threshold, exit code 1 when below
- [ ] Zero external gem dependencies in Phase 1 (stdlib only)
- [ ] All RSpec tests pass  
- [ ] Works on the existing `septa` Rust monorepo's Ruby tooling scripts AND any Rails project
- [ ] Generated output reviewed by developer and committed as their own edits within 5 minutes of `generate` command
