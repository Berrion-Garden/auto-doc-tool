# frozen_string_literal: true

require "sinatra/base"
require "json"

module AutoDoc
  class Server < Sinatra::Base
    set :port, 4567
    set :bind, "0.0.0.0"
    set :public_folder, nil

    # GET / — list all documented modules (directories in .autodoc/)
    get "/" do
      autodoc_dir = find_autodoc_dir
      modules = Dir.glob(File.join(autodoc_dir, "*")).select { |d| File.directory?(d) }.map { |d| File.basename(d) }
      index_html = "<html><body><h1>auto-doc Server</h1>"
      index_html += "<p>Serving: #{autodoc_dir}</p><ul>"
      modules.each { |m| index_html += "<li><a href='/#{m}'>#{m}</a></li>" }
      index_html += "</ul>"
      index_html += "<p><a href='/README'>README</a> | <a href='/api/stats'>Stats</a> | <a href='/api/search'>Search</a></p>"
      index_html += "</body></html>"
      index_html
    end

    # GET /README — view project README
    get "/README" do
      autodoc_dir = find_autodoc_dir
      file_path = File.join(autodoc_dir, "README.md")
      if File.exist?(file_path)
        content = File.read(file_path)
        "<html><body><pre>#{escape_html(content)}</pre></body></html>"
      else
        status 404
        "README not found in #{autodoc_dir}"
      end
    end

    # GET /:module — view AGENTS.md for a module
    get "/:module" do
      autodoc_dir = find_autodoc_dir
      file_path = File.join(autodoc_dir, params[:module], "AGENTS.md")
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
      autodoc_dir = find_autodoc_dir
      file_path = File.join(autodoc_dir, "diagrams", "#{params[:name]}.mmd")
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
      autodoc_dir = find_autodoc_dir
      json_path = File.join(autodoc_dir, "report.json")
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

      autodoc_dir = find_autodoc_dir
      results = []
      Dir.glob(File.join(autodoc_dir, "**/*.{md,mmd}")).each do |file_path|
        content = File.read(file_path)
        if content.downcase.include?(query.downcase)
          relative = Pathname.new(file_path).relative_path_from(Pathname.new(autodoc_dir)).to_s
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

    private

    def find_autodoc_dir
      # Find .autodoc/ directory starting from current dir and walking up
      dir = Dir.pwd
      while true
        autodoc = File.join(dir, ".autodoc")
        return autodoc if File.directory?(autodoc)
        parent = File.dirname(dir)
        return File.join(dir, ".autodoc") if parent == dir  # give up, return default
        dir = parent
      end
    end

    def escape_html(text)
      text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    run! if app_file == $0 && !defined?(Rack::Test)
  end
end
