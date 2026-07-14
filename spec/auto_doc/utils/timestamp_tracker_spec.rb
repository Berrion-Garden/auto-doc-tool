# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe AutoDoc::Utils::TimestampTracker do
  subject(:tracker) { described_class }

  describe ".stale_files" do
    it "returns all Ruby files when no manifest exists" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a.rb"), "")
        File.write(File.join(dir, "b.rb"), "")
        FileUtils.mkdir_p(File.join(dir, "sub"))
        File.write(File.join(dir, "sub", "c.rb"), "")

        result = tracker.stale_files(dir)

        expect(result).to contain_exactly("a.rb", "b.rb", "sub/c.rb")
      end
    end

    it "returns only changed files when manifest exists and one file's mtime changed" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a.rb"), "")
        File.write(File.join(dir, "b.rb"), "")

        tracker.save_manifest(dir, %w[a.rb b.rb])
        sleep(1)

        File.write(File.join(dir, "a.rb"), "updated")

        result = tracker.stale_files(dir)

        expect(result).to contain_exactly("a.rb")
      end
    end

    it "returns empty array when no files changed" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a.rb"), "")
        File.write(File.join(dir, "b.rb"), "")

        tracker.save_manifest(dir, %w[a.rb b.rb])
        result = tracker.stale_files(dir)

        expect(result).to be_empty
      end
    end

    it "returns new file when it was not in manifest" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a.rb"), "")

        tracker.save_manifest(dir, %w[a.rb])

        File.write(File.join(dir, "b.rb"), "")

        result = tracker.stale_files(dir)

        expect(result).to contain_exactly("b.rb")
      end
    end
  end

  describe ".save_manifest" do
    it "creates .autodoc/ and writes correct JSON" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a.rb"), "")

        result = tracker.save_manifest(dir, %w[a.rb])
        expect(result).to be true

        manifest_path = File.join(dir, ".autodoc", "generation_manifest.json")
        expect(File).to exist(manifest_path)

        manifest = JSON.parse(File.read(manifest_path))
        expect(manifest).to have_key("generated_at")
        expect(manifest).to have_key("files")
        expect(manifest["files"]).to have_key("a.rb")
        expect(manifest["files"]["a.rb"]).to be_a(Integer)
      end
    end

    it "updates existing manifest on second call" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a.rb"), "")

        tracker.save_manifest(dir, %w[a.rb])
        manifest_path = File.join(dir, ".autodoc", "generation_manifest.json")
        first_manifest = JSON.parse(File.read(manifest_path))
        first_generated_at = first_manifest["generated_at"]

        sleep(1)
        File.write(File.join(dir, "b.rb"), "")
        tracker.save_manifest(dir, %w[a.rb b.rb])

        updated_manifest = JSON.parse(File.read(manifest_path))
        expect(updated_manifest["generated_at"]).not_to eq(first_generated_at)
        expect(updated_manifest["files"]).to have_key("a.rb")
        expect(updated_manifest["files"]).to have_key("b.rb")
      end
    end

    it "returns false on permission error" do
      dir = File.join(Dir.tmpdir, "nonexistent_should_not_exist_#{Process.pid}")

      result = tracker.save_manifest(dir, %w[a.rb])

      expect(result).to be false
    end
  end
end
