# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe AutoDoc::Analyzer::GenericScanner do
  describe ".parse_file" do
    it "extracts functions from Python files" do
      path = fixture_path("sample_python_project", "app.py")
      result = described_class.parse_file(path)

      hello = result.find { |d| d[:name] == "hello" && d[:type] == :function }
      expect(hello).not_to be_nil
      expect(hello[:line]).to eq(1)

      helper = result.find { |d| d[:name] == "helper_func" && d[:type] == :function }
      expect(helper).not_to be_nil
    end

    it "extracts classes from Python files" do
      path = fixture_path("sample_python_project", "app.py")
      result = described_class.parse_file(path)

      names = result.select { |d| d[:type] == :class }.map { |d| d[:name] }
      expect(names).to include("Greeter", "Calculator")
    end

    it "extracts functions and classes from JavaScript files" do
      path = fixture_path("sample_python_project", "utils.js")
      result = described_class.parse_file(path)

      names = result.map { |d| d[:name] }
      expect(names).to include("doSomething", "UserManager")
    end

    it "returns empty array for non-existent file" do
      result = described_class.parse_file("/nonexistent/path/file.py")
      expect(result).to eq([])
    end

    it "returns empty array for unsupported extension" do
      result = described_class.parse_file(fixture_path("sample_python_project", ".autodoc"))
      expect(result).to eq([])
    end
  end

  describe ".detect_language" do
    it "detects :typescript from .ts extension" do
      result = described_class.detect_language("file.ts")
      expect(result).to eq(:typescript)
    end

    it "detects :python from .py extension" do
      result = described_class.detect_language("file.py")
      expect(result).to eq(:python)
    end

    it "detects :python from python3 shebang" do
      result = described_class.detect_language("file", "#!/usr/bin/env python3\n")
      expect(result).to eq(:python)
    end

    it "detects :bash from bash shebang" do
      result = described_class.detect_language("file", "#!/bin/bash\n")
      expect(result).to eq(:bash)
    end

    it "returns :unknown for unknown extension and no shebang" do
      result = described_class.detect_language("file.xyz")
      expect(result).to eq(:unknown)
    end

    it "detects :go from .go extension" do
      result = described_class.detect_language("server.go")
      expect(result).to eq(:go)
    end

    it "detects :ruby from .rb extension" do
      result = described_class.detect_language("script.rb")
      expect(result).to eq(:ruby)
    end

    it "detects :javascript from .js extension" do
      result = described_class.detect_language("app.js")
      expect(result).to eq(:javascript)
    end

    it "returns :unknown when extension is missing and no shebang" do
      result = described_class.detect_language("Makefile")
      expect(result).to eq(:unknown)
    end
  end

  describe "with Go content" do
    it "parses Go file and extracts functions and types" do
      file = Tempfile.new(["test", ".go"])
      begin
        file.write(<<~GO)
          package main

          func main() {
              println("Hello")
          }

          type Server struct {
              Port int
          }

          type Handler interface {
              Serve()
          }
        GO
        file.close

        result = described_class.parse_file(file.path)

        func_names = result.select { |d| d[:type] == :function }.map { |d| d[:name] }
        expect(func_names).to include("main")

        type_names = result.select { |d| d[:type] == :class }.map { |d| d[:name] }
        expect(type_names).to include("Server", "Handler")
      ensure
        file.unlink
      end
    end
  end

  describe ".enrich_with_llm" do
    it "returns nil when client returns nil" do
      client = instance_double(AutoDoc::LLM::Client, chat: nil)
      result = described_class.enrich_with_llm("def foo: pass", :python, client)
      expect(result).to be_nil
    end

    it "returns response string from client" do
      client = instance_double(AutoDoc::LLM::Client, chat: "This file defines a function foo.")
      result = described_class.enrich_with_llm("def foo: pass", :python, client)
      expect(result).to eq("This file defines a function foo.")
    end

    it "calls client.chat with a user message" do
      client = instance_double(AutoDoc::LLM::Client)
      expect(client).to receive(:chat).with(
        [{ role: "user", content: "Analyze this python source file. What classes, functions, methods, and imports does it define? What is its purpose?" }]
      ).and_return("analysis result")
      result = described_class.enrich_with_llm("def foo: pass", :python, client)
      expect(result).to eq("analysis result")
    end
  end
end
