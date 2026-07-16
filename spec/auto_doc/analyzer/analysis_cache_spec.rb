# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe AutoDoc::Analyzer::AnalysisCache do
  subject(:cache) { described_class }

  let(:project_dir) { Dir.mktmpdir("cache_spec") }
  let(:config) { instance_double(AutoDoc::Config, exclude_patterns: []) }
  let(:block_called) { -> { { result: "fresh" } } }

  before do
    # Start with a clean cache before each test
    described_class.clear!
  end

  after do
    FileUtils.rm_rf(project_dir)
  end

  describe ".fetch" do
    it "returns block result on first call" do
      result = cache.fetch(project_dir, config) { { data: "fresh" } }
      expect(result).to eq({ data: "fresh" })
    end

    it "returns cached result on second call with same project" do
      call_count = 0

      2.times do
        cache.fetch(project_dir, config) { call_count += 1 }
      end

      expect(call_count).to eq(1)
    end

    it "returns fresh result when project_dir changes" do
      dir2 = Dir.mktmpdir("cache_spec2")
      call_count = 0

      cache.fetch(project_dir, config) { call_count += 1 }
      cache.fetch(dir2, config) { call_count += 1 }

      expect(call_count).to eq(2)
      FileUtils.rm_rf(dir2)
    end

    it "runs block when exclude_patterns change" do
      config1 = instance_double(AutoDoc::Config, exclude_patterns: ["spec"])
      config2 = instance_double(AutoDoc::Config, exclude_patterns: ["bin"])
      call_count = 0

      cache.fetch(project_dir, config1) { call_count += 1 }
      cache.fetch(project_dir, config2) { call_count += 1 }

      expect(call_count).to eq(2)
    end

    it "does not cache incremental analyses when file_list is provided" do
      call_count = 0

      2.times do
        cache.fetch(project_dir, config, file_list: ["a.rb"]) { call_count += 1 }
      end

      expect(call_count).to eq(2)
    end

    it "raises ArgumentError when no block given" do
      expect { cache.fetch(project_dir, config) }.to raise_error(ArgumentError, "Block required")
    end
  end

  describe ".clear!" do
    it "resets the cache" do
      cache.fetch(project_dir, config) { "data" }
      cache.clear!
      expect(cache.size).to eq(0)
    end
  end

  describe ".size" do
    it "returns number of cached entries" do
      expect(cache.size).to eq(0)
      cache.fetch(project_dir, config) { "data" }
      expect(cache.size).to eq(1)
    end
  end

  describe ".compute_fingerprint" do
    it "includes project_dir and excludes" do
      fp = cache.send(:compute_fingerprint, project_dir, config)
      expect(fp).to include(project_dir)
      expect(fp).to include("|")
    end
  end

  describe ".latest_ruby_mtime" do
    it "returns mtime of newest file" do
      File.write(File.join(project_dir, "a.rb"), "# a")
      File.write(File.join(project_dir, "b.rb"), "# b")

      mtime_a = File.mtime(File.join(project_dir, "a.rb")).to_i
      mtime_b = File.mtime(File.join(project_dir, "b.rb")).to_i

      result = cache.send(:latest_ruby_mtime, project_dir, "")
      expect(result).to eq([mtime_a, mtime_b].max)
    end

    it "returns 0 for empty directory" do
      result = cache.send(:latest_ruby_mtime, project_dir, "")
      expect(result).to eq(0)
    end
  end

  describe "fingerprint changes when file mtime changes" do
    it "produces different fingerprints after file modification" do
      fp1 = cache.send(:compute_fingerprint, project_dir, config)

      File.write(File.join(project_dir, "new.rb"), "# new")
      # Sleep to ensure mtime differs
      sleep 0.1
      File.write(File.join(project_dir, "new.rb"), "# modified")

      fp2 = cache.send(:compute_fingerprint, project_dir, config)
      expect(fp2).not_to eq(fp1)
    end
  end
end
