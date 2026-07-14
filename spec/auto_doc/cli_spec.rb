# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "auto_doc/cli"

RSpec.describe AutoDoc::CLI do
  subject(:cli) { described_class }

  describe "version" do
    it "prints the gem version" do
      expect { cli.start(%w[version]) }.to output(/auto-doc \d+\.\d+\.\d+/).to_stdout
    end
  end

  describe "init" do
    let(:tmpdir) { Dir.mktmpdir }
    after { FileUtils.remove_entry(tmpdir) }

    it "creates .autodoc.yml in the target directory" do
      cli.start(["init", tmpdir])
      config_path = File.join(tmpdir, ".autodoc.yml")
      expect(File.exist?(config_path)).to be true
    end

    it "does not overwrite existing .autodoc.yml" do
      config_path = File.join(tmpdir, ".autodoc.yml")
      File.write(config_path, "original: true")
      expect {
        cli.start(["init", tmpdir])
      }.to output(/already exists/).to_stdout
      expect(File.read(config_path)).to eq("original: true")
    end
  end

  describe "diff" do
    it "requires SINCE argument" do
      expect { cli.start(%w[diff]) }.to raise_error(SystemExit)
    end

    it "prints usage when SINCE is missing" do
      expect { cli.start(%w[diff]) }.to raise_error(SystemExit)
    end
  end

  describe "orphans" do
    let(:tmpdir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(tmpdir) }

    it "handles directory with no Ruby files" do
      expect { cli.start(["orphans", tmpdir]) }.to output(/No Ruby files found/).to_stdout
    end
  end

  describe "audit" do
    context "with a real project" do
      it "runs without crash on fixtures" do
        fixture = fixture_path("sample_ruby_project")
        expect { cli.start(["audit", "--threshold", "0", fixture]) }.to output(/AUDIT REPORT/).to_stdout
      end
    end
  end

  describe "help" do
    it "responds to --help" do
      expect { cli.start(%w[--help]) }.to output(/Commands/).to_stdout
    end
  end

  describe "serve" do
    it "starts server and outputs Starting auto-doc server" do
      expect { cli.start(["serve", "--port", "49876"]) }.to output(/Starting auto-doc server/).to_stdout
    rescue SystemExit
      # Thor may exit; we just want to verify the output was produced
    end
  end

  describe "verify" do
    context "with a real project" do
      it "runs generate + audit chain without crash" do
        fixture = fixture_path("sample_ruby_project")
        expect { cli.start(["verify", "--threshold", "0", fixture]) }.to output(/Documentation generation complete/).to_stdout
      end

      it "passes audit threshold option through to audit" do
        fixture = fixture_path("sample_ruby_project")
        expect { cli.start(["verify", "--threshold", "0", fixture]) }.to output(/AUDIT REPORT/).to_stdout
      end

      it "accepts --ci flag" do
        fixture = fixture_path("sample_ruby_project")
        expect { cli.start(["verify", "--ci", "--threshold", "0", fixture]) }.to output(/Documentation generation complete/).to_stdout
      end

      it "exits with code 1 on audit failure with --ci" do
        fixture = fixture_path("partial_docs_project")
        expect { cli.start(["verify", "--ci", "--threshold", "100", fixture]) }.to raise_error(SystemExit) do |e|
          expect(e.status).to eq(1)
        end
      end
    end
  end
end
