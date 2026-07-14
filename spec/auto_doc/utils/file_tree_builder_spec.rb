# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe AutoDoc::Utils::FileTreeBuilder do
  subject(:builder) { described_class }

  # Can't use fixtures/sample_ruby_project because it's root-owned, so build fresh temp dirs

  describe ".build" do
    it "returns formatted tree for a directory with files" do
      dir = Dir.mktmpdir
      File.write(File.join(dir, "a.rb"), "")
      File.write(File.join(dir, "b.rb"), "")
      FileUtils.mkdir_p(File.join(dir, "sub"))
      File.write(File.join(dir, "sub", "c.rb"), "")

      result = builder.build(dir)
      expect(result).to include("a.rb")
      expect(result).to include("b.rb")
      expect(result).to include("sub")
      expect(result).to include("└──")
      expect(result).to include("├──")
      FileUtils.remove_entry(dir)
    end

    it "returns empty string for empty directory" do
      dir = Dir.mktmpdir
      result = builder.build(dir)
      expect(result).to eq("")
      FileUtils.remove_entry(dir)
    end

    it "excludes files matching exclude patterns" do
      dir = Dir.mktmpdir
      File.write(File.join(dir, "keep.rb"), "")
      FileUtils.mkdir_p(File.join(dir, "spec"))
      File.write(File.join(dir, "spec", "test.rb"), "")

      result = builder.build(dir, ["spec/test.rb"])
      expect(result).to include("keep.rb")
      expect(result).to include("spec")
      expect(result).not_to include("test.rb")
      FileUtils.remove_entry(dir)
    end

    it "handles deeply nested directory structure" do
      dir = Dir.mktmpdir
      FileUtils.mkdir_p(File.join(dir, "a", "b", "c"))
      File.write(File.join(dir, "a", "b", "c", "deep.rb"), "")
      File.write(File.join(dir, "a", "top.rb"), "")

      result = builder.build(dir)
      expect(result).to include("a")
      expect(result).to include("b")
      expect(result).to include("c")
      expect(result).to include("deep.rb")
      expect(result).to include("top.rb")
      FileUtils.remove_entry(dir)
    end

    it "skips dotfiles and dotdirs" do
      dir = Dir.mktmpdir
      File.write(File.join(dir, "visible.rb"), "")
      File.write(File.join(dir, ".hidden.rb"), "")
      FileUtils.mkdir_p(File.join(dir, ".config"))

      result = builder.build(dir)
      expect(result).to include("visible.rb")
      expect(result).not_to include(".hidden")
      expect(result).not_to include(".config")
      FileUtils.remove_entry(dir)
    end

    it "sorts entries alphabetically" do
      dir = Dir.mktmpdir
      File.write(File.join(dir, "z.rb"), "")
      File.write(File.join(dir, "a.rb"), "")

      result = builder.build(dir)
      a_pos = result.index("a.rb")
      z_pos = result.index("z.rb")
      expect(a_pos).to be < z_pos if a_pos && z_pos
      FileUtils.remove_entry(dir)
    end
  end
end
