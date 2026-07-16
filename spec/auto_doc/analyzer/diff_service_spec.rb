# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::Analyzer::DiffService do
  subject(:service) { described_class }

  let(:project_dir) { fixture_path("sample_ruby_project") }
  let(:since) { "HEAD~1" }

  describe ".run" do
    let(:say_spy) { double("say") }

    before do
      allow(say_spy).to receive(:call)
    end

    it "returns empty result when no files changed" do
      instance = described_class.send(:new, project_dir, since, say: say_spy)
      allow(instance).to receive(:git_changed_ruby_files).and_return([])

      result = instance.run
      expect(result).to eq({ changed_files: [], undocumented_changes: [] })
    end

    it "run returns changed files from git diff" do
      changed = ["app/models/user.rb"]
      instance = described_class.send(:new, project_dir, since, say: say_spy)
      allow(instance).to receive(:git_changed_ruby_files).and_return(changed)

      result = instance.run
      expect(result[:changed_files]).to eq(changed)
    end

    it "run finds undocumented definitions in changed files" do
      instance = described_class.send(:new, project_dir, since, say: say_spy)
      allow(instance).to receive(:git_changed_ruby_files).and_return(["lib/undocumented_helper.rb"])

      result = instance.run
      expect(result[:undocumented_changes]).not_to be_empty
      expect(result[:undocumented_changes].first).to have_key(:symbol)
      expect(result[:undocumented_changes].first).to have_key(:type)
      expect(result[:undocumented_changes].first).to have_key(:file)
    end

    it "run returns all definitions as undocumented when none have docs" do
      instance = described_class.send(:new, project_dir, since, say: say_spy)
      allow(instance).to receive(:git_changed_ruby_files).and_return(["lib/undocumented_helper.rb"])

      result = instance.run
      result[:undocumented_changes].each do |change|
        expect(change[:type]).to be_a(String)
        expect(change[:symbol]).to be_a(String)
      end
    end

    it "run excludes definitions that have docs" do
      instance = described_class.send(:new, project_dir, since, say: say_spy)
      allow(instance).to receive(:git_changed_ruby_files).and_return(["app/models/user.rb"])

      result = instance.run
      # User class is documented, so it should not appear as undocumented
      user_undocumented = result[:undocumented_changes].select { |c| c[:symbol] == "User" }
      expect(user_undocumented).to be_empty
    end

    it "run handles git diff failure gracefully" do
      instance = described_class.send(:new, project_dir, since, say: say_spy)
      # Stub the backtick call inside git_changed_ruby_files to raise
      allow(instance).to receive(:`).and_raise(StandardError.new("boom"))

      result = instance.run
      expect(result).to eq({ changed_files: [], undocumented_changes: [] })
    end

    it "run calls say callback with progress messages" do
      instance = described_class.send(:new, project_dir, since, say: say_spy)
      allow(instance).to receive(:git_changed_ruby_files).and_return([])

      expect(say_spy).to receive(:call).with("Checking for undocumented changes since '#{since}'...", :green)
      instance.run
    end
  end

  describe "#find_undocumented (private)" do
    it "returns empty array when all definitions have docs" do
      analyses = {
        "/path/to/file.rb" => {
          definitions: [
            { name: "DocdClass", type: :class, has_doc?: true },
            { name: "doc_method", type: :method, has_doc?: true }
          ]
        }
      }

      instance = described_class.send(:new, project_dir, since, say: ->(*) {})
      undocumented = instance.send(:find_undocumented, analyses)
      expect(undocumented).to eq([])
    end
  end

  describe "#git_changed_ruby_files (private)" do
    it "filters to .rb files only" do
      instance = described_class.send(:new, project_dir, since, say: ->(*) {})

      # Stub backtick to return only .rb files (the method uses -- '*.rb' globbing)
      allow(instance).to receive(:`).and_return(<<~OUTPUT)
        app/models/user.rb
        lib/utils.rb
      OUTPUT

      allow(File).to receive(:exist?).and_return(true)

      result = instance.send(:git_changed_ruby_files)
      expect(result).to contain_exactly("app/models/user.rb", "lib/utils.rb")
    end
  end
end
