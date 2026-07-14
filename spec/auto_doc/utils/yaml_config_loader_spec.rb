# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "yaml"

RSpec.describe AutoDoc::Utils::YamlConfigLoader do
  subject(:loader) { described_class }

  let(:tmpdir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(tmpdir) }

  describe ".load" do
    it "loads valid YAML and returns a hash with symbol keys" do
      File.write(File.join(tmpdir, "config.yml"), <<~YAML)
        module_roots:
          - app
          - lib
        audit:
          min_doc_coverage: 85
      YAML

      result = loader.load(File.join(tmpdir, "config.yml"))
      expect(result).to be_a(Hash)
      expect(result[:module_roots]).to eq(%w[app lib])
      expect(result.dig(:audit, :min_doc_coverage)).to eq(85)
    end

    it "returns empty hash when file does not exist" do
      result = loader.load("/nonexistent/path.yml")
      expect(result).to eq({})
    end

    it "returns empty hash when file is empty" do
      File.write(File.join(tmpdir, "empty.yml"), "")
      result = loader.load(File.join(tmpdir, "empty.yml"))
      expect(result).to eq({})
    end

    it "converts string keys to symbols" do
      File.write(File.join(tmpdir, "string_keys.yml"), <<~YAML)
        module_roots:
          - lib
        output:
          directory: ".docs"
      YAML

      result = loader.load(File.join(tmpdir, "string_keys.yml"))
      expect(result).to have_key(:module_roots)
      expect(result).to have_key(:output)
      expect(result.dig(:output, :directory)).to eq(".docs")
    end

    it "converts nested keys recursively" do
      File.write(File.join(tmpdir, "nested.yml"), <<~YAML)
        output:
          directory: test
          format: json
      YAML

      result = loader.load(File.join(tmpdir, "nested.yml"))
      expect(result[:output]).to be_a(Hash)
      expect(result.dig(:output, :directory)).to eq("test")
      expect(result.dig(:output, :format)).to eq("json")
    end
  end
end
