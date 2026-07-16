# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# Test class that includes the TemplateHelper module
class TemplateHelperTestClass
  include AutoDoc::Generator::TemplateHelper
end

RSpec.describe AutoDoc::Generator::TemplateHelper do
  subject(:helper) { TemplateHelperTestClass.new }

  let(:tmpdir) { Dir.mktmpdir("template_helper") }
  let(:template_file) { File.join(tmpdir, "test_template.erb") }

  before do
    File.write(template_file, "Hello <%= name %>!")
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe "#read_template" do
    it "returns template content" do
      content = helper.read_template(template_file)
      expect(content).to eq("Hello <%= name %>!")
    end

    it "returns UTF-8 encoded content" do
      content = helper.read_template(template_file)
      expect(content.encoding).to eq(Encoding::UTF_8)
    end

    it "raises error when file does not exist" do
      expect {
        helper.read_template("/nonexistent/template.erb")
      }.to raise_error(RuntimeError, /Template not found/)
    end

    it "error message includes file path" do
      fake_path = "/nonexistent/template.erb"
      expect {
        helper.read_template(fake_path)
      }.to raise_error(RuntimeError, /#{fake_path}/)
    end

    it "included classes can call read_template" do
      expect(helper).to respond_to(:read_template)
    end
  end
end
