# frozen_string_literal: true

require "spec_helper"
require "rack/test"
require "json"

RSpec.describe AutoDoc::Server do
  include Rack::Test::Methods

  def app
    AutoDoc::Server.set :environment, :test
    AutoDoc::Server.set :protection, except: [:host_authorization]
    AutoDoc::Server
  end

  let(:tmpdir) { Dir.mktmpdir }
  let(:docs_dir) { File.join(tmpdir, ".docs") }

  around do |example|
    # Set up a minimal .docs directory structure
    FileUtils.mkdir_p(docs_dir)
    FileUtils.mkdir_p(File.join(docs_dir, "lib"))
    FileUtils.mkdir_p(File.join(docs_dir, "diagrams"))
    FileUtils.mkdir_p(File.join(docs_dir, "schema"))

    File.write(File.join(docs_dir, "README.md"), "# Test README\nThis is test content.")
    File.write(File.join(docs_dir, "lib", "AGENTS.md"), "# AGENTS.md for lib\nClass Foo\n")
    File.write(File.join(docs_dir, "diagrams", "deps.mmd"), "graph TD\n  A --> B")
    File.write(File.join(docs_dir, "report.json"), '{"coverage": 85}')
    File.write(File.join(docs_dir, "INDEX.md"), "# Project INDEX\n\n## Symbols\n| Name | Type | File |\n| --- | --- | --- |\n| Foo | Class | lib/foo.rb |\n")
    File.write(File.join(docs_dir, "SUMMARY.md"), "# Project Summary\nThis is a test project.\n")
    File.write(File.join(docs_dir, "VECTORS.json"), '{"symbols":[{"symbol":"Foo","keywords":["foo","class"]}]}')
    File.write(File.join(docs_dir, "architecture.md"), "# Architecture\nThe system has one component.\n")
    File.write(File.join(docs_dir, "schema", "schema.json"), '{"users":{"columns":[{"name":"id","type":"integer"}]}}')
    File.write(File.join(docs_dir, "lib", "INDEX.md"), "# lib INDEX\n\n## Symbols\n| Name | Type | File |\n| --- | --- | --- |\n| LibClass | Class | lib/lib_class.rb |\n")

    old_pwd = Dir.pwd
    Dir.chdir(tmpdir)

    example.run

    # Cleanup
    Dir.chdir(old_pwd)
    FileUtils.remove_entry(tmpdir)
  end

  describe "GET /" do
    it "returns HTML listing" do
      get "/"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("auto-doc Server")
      expect(last_response.body).to include("<html>")
    end

    it "lists documented modules" do
      get "/"
      expect(last_response.body).to include("lib")
    end

    it "links to README and API pages" do
      get "/"
      expect(last_response.body).to include("/README")
      expect(last_response.body).to include("/api/stats")
      expect(last_response.body).to include("/api/search")
    end
  end

  describe "GET /README" do
    it "returns README content" do
      get "/README"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Test README")
      expect(last_response.body).to include("This is test content")
    end

    it "escapes HTML in content" do
      File.write(File.join(docs_dir, "README.md"), "<script>alert('xss')</script>")
      get "/README"
      expect(last_response.body).not_to include("<script>")
      expect(last_response.body).to include("&lt;script&gt;")
    end
  end

  describe "GET /:module" do
    it "returns AGENTS.md content for existing module" do
      get "/lib"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("AGENTS.md for lib")
    end

    it "returns 404 for nonexistent module" do
      get "/nonexistent"
      expect(last_response.status).to eq(404)
    end
  end

  describe "GET /diagrams/:name" do
    it "returns diagram content" do
      get "/diagrams/deps"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("graph TD")
    end

    it "returns 404 for nonexistent diagram" do
      get "/diagrams/nonexistent"
      expect(last_response.status).to eq(404)
    end
  end

  describe "GET /api/stats" do
    it "returns JSON stats" do
      get "/api/stats"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("coverage")
    end

    it "returns JSON coverage data from report.json" do
      get "/api/stats"
      json = JSON.parse(last_response.body)
      expect(json).to have_key("coverage")
    end

    it "returns error when report.json is missing" do
      File.delete(File.join(docs_dir, "report.json"))
      get "/api/stats"
      expect(last_response.status).to eq(200)
      json = JSON.parse(last_response.body)
      expect(json["error"]).to include("report.json")
    end
  end

  describe "fallback to .autodoc/" do
    it "serves from .autodoc/ when .docs/ does not exist" do
      # Remove .docs/ and create .autodoc/ instead
      FileUtils.rm_rf(docs_dir)
      autodoc_fallback = File.join(tmpdir, ".autodoc")
      FileUtils.mkdir_p(File.join(autodoc_fallback, "lib"))
      File.write(File.join(autodoc_fallback, "README.md"), "# Legacy README")
      File.write(File.join(autodoc_fallback, "lib", "AGENTS.md"), "# Legacy AGENTS.md")

      get "/"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("auto-doc Server")

      get "/README"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Legacy README")

      get "/lib"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Legacy AGENTS.md")
    end
  end

  describe "GET /api/search" do
    it "returns search results for matching term" do
      get "/api/search?q=Class"
      expect(last_response.status).to eq(200)
      json = JSON.parse(last_response.body)
      expect(json["query"]).to eq("Class")
      expect(json["total"]).to be > 0
    end

    it "returns no results for non-matching term" do
      get "/api/search?q=zzzznonexistent"
      expect(last_response.status).to eq(200)
      json = JSON.parse(last_response.body)
      expect(json["total"]).to eq(0)
    end

    it "returns error when query parameter is missing" do
      get "/api/search"
      expect(last_response.status).to eq(200)
      json = JSON.parse(last_response.body)
      expect(json["error"]).to include("Missing")
    end
  end

  describe "GET /api/index" do
    it "returns INDEX.md as HTML" do
      get "/api/index?path=."
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Project INDEX")
      expect(last_response.body).to include("<html>")
    end

    it "returns INDEX.md for a module subpath" do
      get "/api/index?path=lib"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("LibClass")
    end

    it "returns 404 when INDEX.md does not exist" do
      get "/api/index?path=nonexistent"
      expect(last_response.status).to eq(404)
    end
  end

  describe "GET /api/summary" do
    it "returns SUMMARY.md as HTML" do
      get "/api/summary"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Project Summary")
    end

    it "returns 404 when SUMMARY.md does not exist" do
      get "/api/summary?path=nonexistent"
      expect(last_response.status).to eq(404)
    end
  end

  describe "GET /api/vectors" do
    it "returns VECTORS.json as JSON" do
      get "/api/vectors"
      expect(last_response.status).to eq(200)
      json = JSON.parse(last_response.body)
      expect(json).to have_key("symbols")
    end

    it "returns error when vectors.json does not exist" do
      get "/api/vectors?path=nonexistent"
      expect(last_response.status).to eq(200)
      json = JSON.parse(last_response.body)
      expect(json["error"]).to include("not found")
    end
  end

  describe "GET /api/query" do
    it "returns HTML search results for a term" do
      get "/api/query?q=Foo"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Search:")
      expect(last_response.body).to include("Foo")
      expect(last_response.body).to include("<html>")
    end

    it "returns HTML when no results found" do
      get "/api/query?q=zzzznonexistent"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("0 result")
    end

    it "returns HTML with error for missing query parameter" do
      get "/api/query"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Missing")
    end
  end

  describe "GET /api/diagram/:name" do
    it "returns diagram content as JSON" do
      get "/api/diagram/deps"
      expect(last_response.status).to eq(200)
      json = JSON.parse(last_response.body)
      expect(json["name"]).to eq("deps")
      expect(json["content"]).to include("graph TD")
    end

    it "returns 404 for nonexistent diagram" do
      get "/api/diagram/nonexistent"
      expect(last_response.status).to eq(404)
      json = JSON.parse(last_response.body)
      expect(json["error"]).to include("not found")
    end
  end

  describe "GET /api/schema" do
    it "returns schema.json as JSON" do
      get "/api/schema"
      expect(last_response.status).to eq(200)
      json = JSON.parse(last_response.body)
      expect(json).to have_key("users")
    end

    it "returns error when schema.json does not exist" do
      FileUtils.rm_rf(File.join(docs_dir, "schema"))
      get "/api/schema"
      expect(last_response.status).to eq(200)
      json = JSON.parse(last_response.body)
      expect(json["error"]).to include("not found")
    end
  end

  describe "GET /api/architecture" do
    it "returns architecture.md as HTML" do
      get "/api/architecture"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Architecture")
      expect(last_response.body).to include("one component")
    end

    it "returns 404 when architecture.md does not exist" do
      File.delete(File.join(docs_dir, "architecture.md"))
      get "/api/architecture"
      expect(last_response.status).to eq(404)
    end
  end

  describe "POST /api/agent" do
    it "returns JSON result for a valid prompt" do
      post "/api/agent", { prompt: "list all" }.to_json, { "CONTENT_TYPE" => "application/json" }
      expect(last_response.status).to eq(200)
      json = JSON.parse(last_response.body)
      expect(json).to have_key("intent")
      expect(json).to have_key("result")
      expect(json).to have_key("query")
    end

    it "returns error for missing prompt" do
      post "/api/agent", {}.to_json, { "CONTENT_TYPE" => "application/json" }
      expect(last_response.status).to eq(200)
      json = JSON.parse(last_response.body)
      expect(json["error"]).to include("Missing")
    end

    it "returns error for empty prompt" do
      post "/api/agent", { prompt: "" }.to_json, { "CONTENT_TYPE" => "application/json" }
      expect(last_response.status).to eq(200)
      json = JSON.parse(last_response.body)
      expect(json["error"]).to include("Missing")
    end

    it "returns error for invalid JSON body" do
      post "/api/agent", "not json", { "CONTENT_TYPE" => "application/json" }
      expect(last_response.status).to eq(200)
      json = JSON.parse(last_response.body)
      expect(json["error"]).to include("Missing")
    end
  end
end
