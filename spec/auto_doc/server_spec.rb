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

    File.write(File.join(docs_dir, "README.md"), "# Test README\nThis is test content.")
    File.write(File.join(docs_dir, "lib", "AGENTS.md"), "# AGENTS.md for lib\nClass Foo\n")
    File.write(File.join(docs_dir, "diagrams", "deps.mmd"), "graph TD\n  A --> B")
    File.write(File.join(docs_dir, "report.json"), '{"coverage": 85}')

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
end
