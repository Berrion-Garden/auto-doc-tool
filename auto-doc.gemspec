# frozen_string_literal: true

require_relative "lib/auto_doc/version"
require "date"

Gem::Specification.new do |spec|
  spec.name          = "auto-doc"
  spec.version       = AutoDoc::VERSION
  spec.authors       = ["Auto-Doc Contributors"]
  spec.email         = []

  spec.summary       = "Automated documentation generator for Ruby projects"
  spec.description   = "Analyzes Ruby source files to generate AGENTS.md, README.md, and dependency DAG diagrams. Extracts classes, modules, methods, constants, imports, and doc comments — no external dependencies."
  spec.homepage      = "https://github.com/pik-ai/auto-doc"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["source_code_uri"] = "https://github.com/pik-ai/auto-doc"
  spec.metadata["changelog_uri"] = "https://github.com/pik-ai/auto-doc/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match?(%r{\A(?:test|spec|features)/}) }
  rescue # rubocop:disable Style/RescueStandardError
    # Fallback for non-git environments
    %w[lib exe bin templates].flat_map do |dir|
      Dir.glob("#{dir}/**/*").reject { |f| File.directory?(f) }
    end + %w[Rakefile Gemfile README.md .autodoc.yml.example]
  end

  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.bindir      = "exe"
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.0"
  spec.add_dependency "sinatra", "~> 4.0"

  spec.add_development_dependency "rake", "~> 13.0"
end
