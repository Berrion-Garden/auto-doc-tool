# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"
require "fileutils"

RSpec.describe AutoDoc::AgentQueryService do
  subject(:service) { described_class }

  # -----------------------------------------------------------------
  # Helpers
  # -----------------------------------------------------------------

  def with_project_dir
    dir = Dir.mktmpdir("agent_query_spec")
    FileUtils.mkdir_p(File.join(dir, ".docs"))
    yield dir
  ensure
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end

  # Writes an INDEX.md with a Dependencies section containing the given rows.
  # Each row is a hash with keys :from, :type, :to.
  def create_index_with_dependencies(dir, rows)
    lines = ["# INDEX: test", "", "## Dependencies", "", "| From | Type | To |", "|------|------|----|", ""]
    rows.each do |row|
      lines << "| #{row[:from]} | #{row[:type]} | #{row[:to]} |"
    end
    lines << ""
    File.write(File.join(dir, ".docs", "INDEX.md"), lines.join("\n"))
  end

  # Writes a schema.json file under .docs/schema/
  def create_schema_json(dir, tables)
    schema_dir = File.join(dir, ".docs", "schema")
    FileUtils.mkdir_p(schema_dir)
    File.write(File.join(schema_dir, "schema.json"), JSON.pretty_generate(tables))
  end

  # -----------------------------------------------------------------
  # Tests
  # -----------------------------------------------------------------

  describe "missing .docs/ directory" do
    it "returns error intent with descriptive message" do
      result = service.query("/nonexistent/path", "what depends on X")

      expect(result[:intent]).to eq(:error)
      expect(result[:result][:error]).to match(/No \.docs\/ directory found/)
      expect(result[:query]).to eq("what depends on X")
    end
  end

  # ── Reverse dependency ──────────────────────────────────────────

  describe ":reverse_dependency" do
    it "finds dependents matching 'what depends on X'" do
      with_project_dir do |dir|
        create_index_with_dependencies(dir, [
          { from: "controller.rb", type: "require", to: "payment_processor" },
          { from: "admin_ctrl.rb", type: "require", to: "payment_processor" },
          { from: "other.rb", type: "require", to: "logger" }
        ])

        result = service.query(dir, "what depends on payment_processor")

        expect(result[:intent]).to eq(:reverse_dependency)
        expect(result[:result].size).to eq(2)
        expect(result[:result].map { |r| r[:from] }).to contain_exactly("controller.rb", "admin_ctrl.rb")
      end
    end

    it "matches 'dependents of X' variant" do
      with_project_dir do |dir|
        create_index_with_dependencies(dir, [
          { from: "worker.rb", type: "require", to: "queue" }
        ])

        result = service.query(dir, "dependents of queue")

        expect(result[:intent]).to eq(:reverse_dependency)
        expect(result[:result].size).to eq(1)
        expect(result[:result].first[:from]).to eq("worker.rb")
      end
    end

    it "matches 'who uses X' variant" do
      with_project_dir do |dir|
        create_index_with_dependencies(dir, [
          { from: "api.rb", type: "require", to: "auth_lib" }
        ])

        result = service.query(dir, "who uses auth_lib")

        expect(result[:intent]).to eq(:reverse_dependency)
        expect(result[:result].size).to eq(1)
      end
    end

    it "returns empty array when no matches found" do
      with_project_dir do |dir|
        create_index_with_dependencies(dir, [])

        result = service.query(dir, "what depends on nonexistent")
        expect(result[:intent]).to eq(:reverse_dependency)
        expect(result[:result]).to eq([])
      end
    end
  end

  # ── Forward dependency ───────────────────────────────────────────

  describe ":forward_dependency" do
    it "finds dependencies matching 'X depends on'" do
      with_project_dir do |dir|
        create_index_with_dependencies(dir, [
          { from: "controller.rb", type: "require", to: "payment_processor" },
          { from: "controller.rb", type: "include", to: "auth_helper" },
          { from: "other.rb", type: "require", to: "logger" }
        ])

        result = service.query(dir, "controller.rb depends on")

        expect(result[:intent]).to eq(:forward_dependency)
        expect(result[:result].size).to eq(2)
        expect(result[:result].map { |r| r[:to] }).to contain_exactly("payment_processor", "auth_helper")
      end
    end

    it "matches 'deps of X' variant" do
      with_project_dir do |dir|
        create_index_with_dependencies(dir, [
          { from: "mailer.rb", type: "require", to: "smtp_lib" }
        ])

        result = service.query(dir, "deps of mailer")

        expect(result[:intent]).to eq(:forward_dependency)
        expect(result[:result].size).to eq(1)
      end
    end

    it "matches 'dependencies of X' variant" do
      with_project_dir do |dir|
        create_index_with_dependencies(dir, [
          { from: "app.rb", type: "require", to: "router" }
        ])

        result = service.query(dir, "dependencies of app")

        expect(result[:intent]).to eq(:forward_dependency)
        expect(result[:result].size).to eq(1)
      end
    end

    it "returns empty array when no matches found" do
      with_project_dir do |dir|
        create_index_with_dependencies(dir, [])

        result = service.query(dir, "nonexistent.rb depends on")
        expect(result[:intent]).to eq(:forward_dependency)
        expect(result[:result]).to eq([])
      end
    end
  end

  # ── List symbols ─────────────────────────────────────────────────

  describe ":list_symbols" do
    it "returns all symbols from INDEX.md with 'list all'" do
      result = service.query(fixture_path("partial_docs_project"), "list all")

      expect(result[:intent]).to eq(:list_symbols)
      expect(result[:result]).to be_an(Array)
      expect(result[:result].size).to be >= 2
      symbols = result[:result].map { |s| s[:symbol] }
      expect(symbols).to include("Calculator", "Silo")
    end

    it "matches 'symbols in' variant" do
      result = service.query(fixture_path("partial_docs_project"), "symbols in")

      expect(result[:intent]).to eq(:list_symbols)
      expect(result[:result].size).to be >= 2
    end
  end

  # ── Describe symbol ─────────────────────────────────────────────

  describe ":describe_symbol" do
    it "describes a symbol matching 'what does X do'" do
      result = service.query(fixture_path("partial_docs_project"), "what does Silo do")

      expect(result[:intent]).to eq(:describe_symbol)
      expect(result[:result]).to be_a(Hash)
      expect(result[:result]["symbol"]).to eq("Silo")
      expect(result[:result]["type"]).to eq("class")
    end

    it "matches 'describe X' variant" do
      result = service.query(fixture_path("partial_docs_project"), "describe Calculator")

      expect(result[:intent]).to eq(:describe_symbol)
      expect(result[:result]["symbol"]).to eq("Calculator")
    end

    it "matches 'what is X' variant" do
      result = service.query(fixture_path("partial_docs_project"), "what is Calculator")

      expect(result[:intent]).to eq(:describe_symbol)
      expect(result[:result]).not_to be_nil
      expect(result[:result]["symbol"]).to eq("Calculator")
    end

    it "returns nil for unknown symbol" do
      result = service.query(fixture_path("partial_docs_project"), "describe NonExistentSymbol")

      expect(result[:intent]).to eq(:describe_symbol)
      expect(result[:result]).to be_nil
    end
  end

  # ── Architecture ─────────────────────────────────────────────────

  describe ":architecture" do
    it "returns architecture content and diagram list" do
      result = service.query(fixture_path("partial_docs_project"), "architecture of")

      expect(result[:intent]).to eq(:architecture)
      expect(result[:result][:content]).to be_a(String)
      expect(result[:result][:content]).to include("partial_docs_project")
      expect(result[:result][:diagrams]).to be_an(Array)
      expect(result[:result][:diagrams]).to include("diagrams/deps.mmd")
    end

    it "matches 'arch of' variant" do
      result = service.query(fixture_path("partial_docs_project"), "arch of")

      expect(result[:intent]).to eq(:architecture)
      expect(result[:result][:diagrams]).not_to be_empty
    end
  end

  # ── Diagram lookup ──────────────────────────────────────────────

  describe ":diagram_lookup" do
    it "finds and reads a diagram file matching 'diagram for X'" do
      result = service.query(fixture_path("partial_docs_project"), "diagram for deps")

      expect(result[:intent]).to eq(:diagram_lookup)
      expect(result[:result][:name]).to eq("deps")
      expect(result[:result][:content]).to be_a(String)
      expect(result[:result][:content]).to include("Dependency Graph")
      expect(result[:result][:path]).to eq("diagrams/deps.mmd")
    end

    it "matches 'show diagram X' variant" do
      result = service.query(fixture_path("partial_docs_project"), "show diagram class_diagram")

      expect(result[:intent]).to eq(:diagram_lookup)
      expect(result[:result][:name]).to eq("class_diagram")
    end

    it "returns nil when diagram not found" do
      result = service.query(fixture_path("partial_docs_project"), "diagram for nonexistent")
      expect(result[:result]).to be_nil
    end
  end

  # ── Schema lookup ───────────────────────────────────────────────

  describe ":schema_lookup" do
    it "looks up a table in schema.json with 'schema for X'" do
      with_project_dir do |dir|
        create_schema_json(dir, [
          { "table" => "users", "columns" => [{ "name" => "id", "type" => "integer" }] },
          { "table" => "posts", "columns" => [{ "name" => "title", "type" => "string" }] }
        ])

        result = service.query(dir, "schema for users")

        expect(result[:intent]).to eq(:schema_lookup)
        expect(result[:result]["table"]).to eq("users")
      end
    end

    it "matches 'table X' variant" do
      with_project_dir do |dir|
        create_schema_json(dir, [
          { "table" => "comments", "columns" => [{ "name" => "body", "type" => "text" }] },
          { "table" => "articles", "columns" => [{ "name" => "title", "type" => "string" }] }
        ])

        result = service.query(dir, "table comments")

        expect(result[:intent]).to eq(:schema_lookup)
        expect(result[:result]["table"]).to eq("comments")
      end
    end

    it "returns nil when schema.json does not exist" do
      with_project_dir do |dir|
        # No schema/ subdirectory created
        result = service.query(dir, "schema for users")
        expect(result[:result]).to be_nil
      end
    end

    it "returns nil when table not found in schema" do
      with_project_dir do |dir|
        create_schema_json(dir, [
          { "table" => "users", "columns" => [] }
        ])

        result = service.query(dir, "schema for nonexistent")
        expect(result[:result]).to be_nil
      end
    end

    it "handles hash-formatted schema.json" do
      with_project_dir do |dir|
        schema_dir = File.join(dir, ".docs", "schema")
        FileUtils.mkdir_p(schema_dir)
        schema = { "users" => { "columns" => [{ "name" => "id", "type" => "integer" }] } }
        File.write(File.join(schema_dir, "schema.json"), JSON.pretty_generate(schema))

        result = service.query(dir, "schema for users")

        expect(result[:intent]).to eq(:schema_lookup)
        expect(result[:result]).to be_a(Hash)
        expect(result[:result]["columns"]).to be_an(Array)
      end
    end
  end

  # ── Case insensitive matching ───────────────────────────────────

  describe "case insensitive matching" do
    it "matches pattern regardless of case" do
      with_project_dir do |dir|
        create_index_with_dependencies(dir, [
          { from: "api.rb", type: "require", to: "auth_lib" }
        ])

        result = service.query(dir, "WHAT DEPENDS ON AUTH_LIB")

        expect(result[:intent]).to eq(:reverse_dependency)
        expect(result[:result].size).to eq(1)
        expect(result[:result].first[:from]).to eq("api.rb")
      end
    end

    it "matches symbol description case insensitively" do
      result = service.query(fixture_path("partial_docs_project"), "describe calculator")

      expect(result[:intent]).to eq(:describe_symbol)
      expect(result[:result]).not_to be_nil
      expect(result[:result]["symbol"]).to eq("Calculator")
    end
  end

  # ── Fallback to SearchService ───────────────────────────────────

  describe "fallback to SearchService" do
    it "delegates unrecognized prompts to SearchService" do
      with_project_dir do |dir|
        result = service.query(dir, "some random search term")

        expect(result[:intent]).to eq(:search)
        expect(result[:result]).to have_key(:query)
        expect(result[:result]).to have_key(:results)
        expect(result[:result]).to have_key(:total)
      end
    end
  end

  # ── Result shape enforcement ────────────────────────────────────

  describe "result shape" do
    it "every result has the top-level keys :intent, :result, :query" do
      result = service.query(fixture_path("partial_docs_project"), "list all")

      expect(result).to have_key(:intent)
      expect(result).to have_key(:result)
      expect(result).to have_key(:query)
      expect(result[:query]).to eq("list all")
    end
  end
end
