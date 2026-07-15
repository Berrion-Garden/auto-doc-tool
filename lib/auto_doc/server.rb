# frozen_string_literal: true

require "sinatra/base"
require "json"
require "erb"

module AutoDoc
  class Server < Sinatra::Base
    set :port, 4567
    set :bind, "0.0.0.0"
    set :public_folder, nil

    # GET / — list all documented modules (directories in .docs/)
    get "/" do
      docs_dir = find_docs_dir
      modules = Dir.glob(File.join(docs_dir, "*")).select { |d| File.directory?(d) }.map { |d| File.basename(d) }
      index_html = "<html><body><h1>auto-doc Server</h1>"
      index_html += "<p>Serving: #{docs_dir}</p><ul>"
      modules.each { |m| index_html += "<li><a href='/#{m}'>#{m}</a></li>" }
      index_html += "</ul>"
      index_html += "<p><a href='/README'>README</a> | <a href='/api/stats'>Stats</a> | <a href='/api/search'>Search</a></p>"
      index_html += "</body></html>"
      index_html
    end

    # GET /README — view project README
    get "/README" do
      docs_dir = find_docs_dir
      file_path = File.join(docs_dir, "README.md")
      if File.exist?(file_path)
        content = File.read(file_path)
        "<html><body><pre>#{escape_html(content)}</pre></body></html>"
      else
        status 404
        "README not found in #{docs_dir}"
      end
    end

    # GET /:module — view AGENTS.md for a module
    get "/:module" do
      docs_dir = find_docs_dir
      file_path = File.join(docs_dir, params[:module], "AGENTS.md")
      if File.exist?(file_path)
        content = File.read(file_path)
        "<html><body><pre>#{escape_html(content)}</pre></body></html>"
      else
        status 404
        "Module '#{params[:module]}' not found"
      end
    end

    # GET /diagrams/:name — view Mermaid diagram
    get "/diagrams/:name" do
      docs_dir = find_docs_dir
      file_path = File.join(docs_dir, "diagrams", "#{params[:name]}.mmd")
      if File.exist?(file_path)
        content = File.read(file_path)
        "<html><body><pre>#{escape_html(content)}</pre></body></html>"
      else
        status 404
        "Diagram '#{params[:name]}' not found"
      end
    end

    # GET /api/stats — JSON coverage stats
    get "/api/stats" do
      docs_dir = find_docs_dir
      json_path = File.join(docs_dir, "report.json")
      content_type :json
      if File.exist?(json_path)
        File.read(json_path)
      else
        { error: "No report.json found — run `auto-doc audit` first" }.to_json
      end
    end

    # GET /api/search?q=term — full-text search across all docs
    get "/api/search" do
      query = params[:q]&.strip
      content_type :json
      return { error: "Missing ?q= parameter" }.to_json if query.nil? || query.empty?

      docs_dir = find_docs_dir
      results = []
      Dir.glob(File.join(docs_dir, "**/*.{md,mmd}")).each do |file_path|
        content = File.read(file_path)
        if content.downcase.include?(query.downcase)
          relative = Pathname.new(file_path).relative_path_from(Pathname.new(docs_dir)).to_s
          lines = content.split("\n")
          matching_lines = lines.each_with_index.select { |line, _| line.downcase.include?(query.downcase) }
          results << {
            file: relative,
            matches: matching_lines.map { |line, idx| { line: idx + 1, text: line.strip } }
          }
        end
      end
      { query: query, results: results, total: results.size }.to_json
    end

    # GET /api/index?path= — read INDEX.md for a module (path relative to .docs/)
    get "/api/index" do
      docs_dir = find_docs_dir
      mod_path = (params[:path] || "").strip
      file_path = File.join(docs_dir, mod_path, "INDEX.md")
      content_type :html
      if File.exist?(file_path)
        "<html><body><h1>INDEX: #{escape_html(mod_path.empty? ? '(root)' : mod_path)}</h1><pre>#{escape_html(File.read(file_path))}</pre></body></html>"
      else
        status 404
        "INDEX.md not found"
      end
    end

    # GET /api/summary?path= — read SUMMARY.md for a module
    get "/api/summary" do
      docs_dir = find_docs_dir
      mod_path = (params[:path] || "").strip
      file_path = File.join(docs_dir, mod_path, "SUMMARY.md")
      content_type :html
      if File.exist?(file_path)
        "<html><body><h1>SUMMARY: #{escape_html(mod_path.empty? ? '(root)' : mod_path)}</h1><pre>#{escape_html(File.read(file_path))}</pre></body></html>"
      else
        status 404
        "SUMMARY.md not found"
      end
    end

    # GET /api/vectors?path= — read VECTORS.json for a module
    get "/api/vectors" do
      docs_dir = find_docs_dir
      mod_path = (params[:path] || "").strip
      content_type :json

      # Try exact name first, then case-insensitive fallback
      file_path = File.join(docs_dir, mod_path, "VECTORS.json")
      unless File.exist?(file_path)
        alt = Dir.glob(File.join(docs_dir, mod_path, "vectors.json")).first
        file_path = alt if alt
      end

      if File.exist?(file_path)
        File.read(file_path)
      else
        { error: "vectors.json not found for path '#{mod_path}'" }.to_json
      end
    end

    # GET /api/query?q= — enhanced search via SearchService with source: true, returns HTML
    get "/api/query" do
      query = params[:q]&.strip
      content_type :html
      return "<html><body><p>Missing 'q' parameter</p></body></html>" if query.nil? || query.empty?

      docs_dir = find_docs_dir
      project_dir = File.dirname(docs_dir)

      result = AutoDoc::SearchService.search(project_dir, query, options: { source: true })

      html = "<html><body><h1>Search: #{escape_html(query)}</h1>"
      html += "<p>#{result[:total]} result(s)</p><ul>"
      result[:results].each do |r|
        html += "<li><strong>#{escape_html(r[:file])}</strong>:#{r[:line]} "
        html += "<em>(#{escape_html(r[:match_type])}, score: #{r[:score]})</em><br>"
        html += "<code>#{escape_html(r[:context])}</code></li>"
      end
      html += "</ul></body></html>"
      html
    end

    # GET /api/diagram/:name — return diagram Mermaid source as JSON
    get "/api/diagram/:name" do
      docs_dir = find_docs_dir
      file_path = File.join(docs_dir, "diagrams", "#{params[:name]}.mmd")
      content_type :json
      if File.exist?(file_path)
        { name: params[:name], content: File.read(file_path, encoding: "UTF-8") }.to_json
      else
        status 404
        { error: "Diagram '#{params[:name]}' not found" }.to_json
      end
    end

    # GET /api/schema — return schema.json as JSON
    get "/api/schema" do
      docs_dir = find_docs_dir
      file_path = File.join(docs_dir, "schema", "schema.json")
      content_type :json
      if File.exist?(file_path)
        File.read(file_path)
      else
        { error: "schema.json not found" }.to_json
      end
    end

    # GET /api/architecture — return architecture.md as HTML
    get "/api/architecture" do
      docs_dir = find_docs_dir
      file_path = File.join(docs_dir, "architecture.md")
      content_type :html
      if File.exist?(file_path)
        "<html><body><h1>Architecture</h1><pre>#{escape_html(File.read(file_path))}</pre></body></html>"
      else
        status 404
        "architecture.md not found"
      end
    end

    # POST /api/agent — natural-language documentation query, returns JSON
    post "/api/agent" do
      content_type :json
      body = JSON.parse(request.body.read) rescue {}
      prompt = body["prompt"]

      return { error: "Missing 'prompt' in request body" }.to_json if prompt.nil? || prompt.strip.empty?

      docs_dir = find_docs_dir
      project_dir = File.dirname(docs_dir)

      result = AutoDoc::AgentQueryService.query(project_dir, prompt)
      result.to_json
    end

    private

    def find_docs_dir
      # Find .docs/ directory starting from current dir and walking up,
      # falling back to .autodoc/ for backward compatibility
      dir = Dir.pwd
      while true
        docs = File.join(dir, ".docs")
        return docs if File.directory?(docs)

        autodoc_dir = File.join(dir, ".autodoc")
        return autodoc_dir if File.directory?(autodoc_dir)

        parent = File.dirname(dir)
        return File.join(dir, ".docs") if parent == dir  # give up, return default
        dir = parent
      end
    end

    def escape_html(text)
      ERB::Util.html_escape(text)
    end

    run! if app_file == $0 && !defined?(Rack::Test)
  end
end
