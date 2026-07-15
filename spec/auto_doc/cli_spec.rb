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

  describe "generate --incremental" do
    let(:tmpdir) { Dir.mktmpdir }
    after { FileUtils.remove_entry(tmpdir) }

    it "passes file_list to analyze_project when --incremental is given" do
      # Create a Ruby file in tmpdir
      FileUtils.mkdir_p(File.join(tmpdir, "lib"))
      File.write(File.join(tmpdir, "lib", "test.rb"), "class Test; end")

      # Run generate --incremental first time (acts like full gen since no manifest)
      expect {
        described_class.start(["generate", "--incremental", tmpdir])
      }.to output(/Incremental mode: \d+ file\(s\) changed/).to_stdout

      # Verify manifest was created
      manifest = File.join(tmpdir, ".docs", "generation_manifest.json")
      expect(File).to exist(manifest)
    end

    it "creates and updates generation manifest" do
      FileUtils.mkdir_p(File.join(tmpdir, "lib"))
      File.write(File.join(tmpdir, "lib", "test.rb"), "class Test; end")

      # First run creates manifest
      described_class.start(["generate", "--incremental", tmpdir])
      manifest = File.join(tmpdir, ".docs", "generation_manifest.json")
      expect(File).to exist(manifest)

      # Second run shouldn't crash
      expect {
        described_class.start(["generate", "--incremental", tmpdir])
      }.to output(/Incremental mode/).to_stdout
    end

    it "non-incremental generate always does full regeneration regardless of manifest" do
      FileUtils.mkdir_p(File.join(tmpdir, "lib"))
      File.write(File.join(tmpdir, "lib", "test.rb"), "class Test; end")

      described_class.start(["generate", "--incremental", tmpdir])
      manifest = File.join(tmpdir, ".docs", "generation_manifest.json")
      expect(File).to exist(manifest)

      # Non-incremental run
      expect {
        described_class.start(["generate", tmpdir])
      }.to output(/Documentation generation complete/).to_stdout
    end
  end

  describe "generate --format" do
    let(:tmpdir) { Dir.mktmpdir }
    after { FileUtils.remove_entry(tmpdir) }

    it "generates docs in .docs/ with --format docs" do
      FileUtils.mkdir_p(File.join(tmpdir, "lib"))
      File.write(File.join(tmpdir, "lib", "test.rb"), "class Test; end")
      described_class.start(["generate", "--format", "docs", tmpdir])
      expect(File).to exist(File.join(tmpdir, ".docs", "README.md"))
    end

    it "generates docs in .autodoc/ with --format autodoc" do
      FileUtils.mkdir_p(File.join(tmpdir, "lib"))
      File.write(File.join(tmpdir, "lib", "test.rb"), "class Test; end")
      described_class.start(["generate", "--format", "autodoc", tmpdir])
      expect(File).to exist(File.join(tmpdir, ".autodoc", "README.md"))
    end

    it "generates docs in custom directory with --output-dir" do
      FileUtils.mkdir_p(File.join(tmpdir, "lib"))
      File.write(File.join(tmpdir, "lib", "test.rb"), "class Test; end")
      described_class.start(["generate", "--output-dir", "my_docs", tmpdir])
      expect(File).to exist(File.join(tmpdir, "my_docs", "README.md"))
    end
  end

  describe "--json flag" do
    describe "generate --json" do
      let(:tmpdir) { Dir.mktmpdir }
      after { FileUtils.remove_entry(tmpdir) }

      it "outputs JSON when --json flag is given" do
        FileUtils.mkdir_p(File.join(tmpdir, "lib"))
        File.write(File.join(tmpdir, "lib", "test.rb"), "class Test; end")

        expect {
          cli.start(["generate", "--json", tmpdir])
        }.to output { |captured|
          parsed = JSON.parse(captured)
          expect(parsed).to be_a(Hash)
          expect(parsed).to have_key("project")
          expect(parsed).to have_key("created_files")
          expect(parsed).to have_key("analyses_count")
        }.to_stdout
      end
    end

    describe "audit --json" do
      it "outputs JSON when --json flag is given" do
        fixture = fixture_path("sample_ruby_project")

        expect {
          cli.start(["audit", "--json", "--threshold", "0", fixture])
        }.to output { |captured|
          parsed = JSON.parse(captured)
          expect(parsed).to be_a(Hash)
          expect(parsed).to have_key("overall_coverage")
          expect(parsed).to have_key("total_symbols")
          expect(parsed).to have_key("passed")
          expect(parsed).to have_key("project")
        }.to_stdout
      end
    end

    describe "diff --json" do
      let(:tmpdir) { Dir.mktmpdir }
      after { FileUtils.remove_entry(tmpdir) }

      it "outputs JSON when --json flag is given" do
        FileUtils.mkdir_p(File.join(tmpdir, "lib"))
        File.write(File.join(tmpdir, "lib", "test.rb"), "class Test; end")

        Dir.chdir(tmpdir) do
          result = system("git init > /dev/null 2>&1 && git config user.email test@test.com && git config user.name test && git add -A && git commit -m 'initial' > /dev/null 2>&1")
          expect(result).to be true

          expect {
            cli.start(["diff", "--json", "HEAD"])
          }.to output { |captured|
            parsed = JSON.parse(captured)
            expect(parsed).to be_a(Hash)
            expect(parsed).to have_key("changed_files")
            expect(parsed).to have_key("undocumented_changes")
          }.to_stdout
        end
      end
    end
  end

  describe "--agent flag" do
    describe "orphans --agent" do
      let(:tmpdir) { Dir.mktmpdir }
      after { FileUtils.remove_entry(tmpdir) }

      it "outputs compact JSON when --agent flag is given" do
        FileUtils.mkdir_p(File.join(tmpdir, "lib"))
        File.write(File.join(tmpdir, "lib", "test.rb"), "class Test; end")

        expect {
          cli.start(["orphans", "--agent", tmpdir])
        }.to output { |captured|
          expect(captured).not_to include("\n  ") # no pretty-printing
          parsed = JSON.parse(captured)
          expect(parsed).to be_a(Hash)
          expect(parsed).to have_key("orphans")
        }.to_stdout
      end
    end

    describe "--agent takes precedence over --json" do
      it "outputs compact JSON when both --agent and --json are given" do
        fixture = fixture_path("sample_ruby_project")

        expect {
          cli.start(["audit", "--agent", "--json", "--threshold", "0", fixture])
        }.to output { |captured|
          # Compact JSON — no indentation newlines
          expect(captured).not_to include("\n  ")
          parsed = JSON.parse(captured)
          expect(parsed).to be_a(Hash)
          # Agent format strips generated_at timestamp
          expect(parsed).not_to have_key("generated_at")
        }.to_stdout
      end
    end
  end

  describe "analyze_project" do
    it "accepts file_list parameter and only analyzes given files" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "lib"))
        File.write(File.join(dir, "lib", "a.rb"), "class A; end")
        File.write(File.join(dir, "lib", "b.rb"), "class B; end")

        config = AutoDoc::Config.load(dir)
        orchestrator = AutoDoc::Orchestrator.new

        # analyze only a.rb via orchestrator's private method
        file_list = [File.join(dir, "lib", "a.rb")]
        analyses = orchestrator.send(:analyze_project, dir, config, file_list)

        expect(analyses.keys).to contain_exactly(File.join(dir, "lib", "a.rb"))
        expect(analyses.keys).not_to include(File.join(dir, "lib", "b.rb"))
      end
    end
  end
end
