# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::Transformer::GraphDataBuilder do
  subject(:builder) { described_class }

  let(:analyses) do
    {
      "/project/app/models/user.rb" => {
        definitions: [
          { name: "User", type: :class, line: 5 }
        ],
        imports: [
          { path: "active_record", type: :require },
          { path: "Enumerable", type: :include }
        ]
      },
      "/project/lib/math_utils.rb" => {
        definitions: [
          { name: "MathUtils", type: :module, line: 6 }
        ],
        imports: [
          { path: "json", type: :require }
        ]
      }
    }
  end

  describe ".build" do
    # ── Test 1: class + module definitions ──────────────────────────────
    it "extracts class and module names into sorted nodes" do
      nodes, = builder.build(analyses)
      expect(nodes).to contain_exactly("MathUtils", "User")
    end

    # ── Test 2: imports become edges ────────────────────────────────────
    it "converts imports into edges with from, to, and type keys" do
      _, edges = builder.build(analyses)

      expect(edges).to match_array([
        { from: "user.rb", to: "active_record", type: "require" },
        { from: "user.rb", to: "Enumerable", type: "include" },
        { from: "math_utils.rb", to: "json", type: "require" }
      ])
    end

    # ── Test 3: deduplicates nodes ──────────────────────────────────────
    it "deduplicates nodes when the same name appears in multiple definitions" do
      analyses = {
        "a.rb" => { definitions: [{ name: "DupClass", type: :class }] },
        "b.rb" => { definitions: [{ name: "DupClass", type: :class }] }
      }
      nodes, = builder.build(analyses)
      expect(nodes).to eq(["DupClass"])
    end

    # ── Test 4: sorts nodes alphabetically ──────────────────────────────
    it "returns nodes in alphabetical order" do
      analyses = {
        "z.rb" => { definitions: [{ name: "Zebra", type: :class }] },
        "a.rb" => { definitions: [{ name: "Alpha", type: :class }] },
        "m.rb" => { definitions: [{ name: "ModuleB", type: :module }] }
      }
      nodes, = builder.build(analyses)
      expect(nodes).to eq(%w[Alpha ModuleB Zebra])
    end

    # ── Test 5: nested definitions with parent_modules ──────────────────
    it "handles nested definitions with parent_modules without including parent names in node" do
      analyses = {
        "nested.rb" => {
          definitions: [
            { name: "Outer", type: :module, line: 1, parent_modules: [] },
            { name: "Inner", type: :class, line: 3, parent_modules: ["Outer"] }
          ]
        }
      }
      nodes, = builder.build(analyses)
      expect(nodes).to contain_exactly("Inner", "Outer")
    end

    # ── Test 6: empty analyses hash ─────────────────────────────────────
    it "returns [[], []] when analyses is empty" do
      result = builder.build({})
      expect(result).to eq([[], []])
    end

    # ── Test 7: nil analyses ────────────────────────────────────────────
    it "returns [[], []] when analyses is nil" do
      result = builder.build(nil)
      expect(result).to eq([[], []])
    end

    # ── Test 8: definitions missing type field are skipped ──────────────
    it "skips definitions without a type field" do
      analyses = {
        "no_type.rb" => {
          definitions: [
            { name: "SkippedOne" },
            { name: "ValidClass", type: :class }
          ]
        }
      }
      nodes, = builder.build(analyses)
      expect(nodes).to contain_exactly("ValidClass")
    end

    # ── Test 9: string keys instead of symbol keys ──────────────────────
    it "extracts nodes from definitions with string keys" do
      analyses = {
        "string_keys.rb" => {
          definitions: [
            { "name" => "StringKeyClass", "type" => "class" }
          ]
        }
      }
      nodes, = builder.build(analyses)
      expect(nodes).to contain_exactly("StringKeyClass")
    end

    # ── Test 10: mixed symbol and string keys ───────────────────────────
    it "handles mixed symbol and string keys across different definitions" do
      analyses = {
        "mixed.rb" => {
          definitions: [
            { name: "SymbolClass", type: :class },
            { "name" => "StringModule", "type" => "module" }
          ]
        }
      }
      nodes, = builder.build(analyses)
      expect(nodes).to contain_exactly("StringModule", "SymbolClass")
    end

    # ── Test 11: nil analysis entry in hash ─────────────────────────────
    it "skips nil analysis entries without crashing" do
      analyses = {
        "good.rb" => { definitions: [{ name: "GoodClass", type: :class }] },
        "bad.rb" => nil
      }
      nodes, = builder.build(analyses)
      expect(nodes).to contain_exactly("GoodClass")
    end

    # ── Test 12: definitions key is nil ─────────────────────────────────
    it "handles nil definitions gracefully" do
      analyses = {
        "nil_defs.rb" => { definitions: nil }
      }
      nodes, = builder.build(analyses)
      expect(nodes).to be_empty
    end

    # ── Test 13: empty definitions array ────────────────────────────────
    it "handles empty definitions array gracefully" do
      analyses = {
        "empty_defs.rb" => { definitions: [] }
      }
      nodes, = builder.build(analyses)
      expect(nodes).to be_empty
    end

    # ── Test 14: non-Hash analyses returns empty ────────────────────────
    it "returns [[], []] when analyses is not a Hash" do
      expect(builder.build("not a hash")).to eq([[], []])
      expect(builder.build(42)).to eq([[], []])
      expect(builder.build([])).to eq([[], []])
    end

    # ── Test 15: edges use string-keyed imports ─────────────────────────
    it "handles string-keyed imports" do
      analyses = {
        "app.rb" => {
          "imports" => [
            { "path" => "json", "type" => "require" }
          ]
        }
      }
      _, edges = builder.build(analyses)
      expect(edges).to match_array([
        { from: "app.rb", to: "json", type: "require" }
      ])
    end

    # ── Test 16: string-keyed definitions with imports ──────────────────
    it "handles entirely string-keyed analysis hashes" do
      analyses = {
        "lib.rb" => {
          "definitions" => [
            { "name" => "LibClass", "type" => "class" }
          ],
          "imports" => [
            { "path" => "logger", "type" => "require" }
          ]
        }
      }
      nodes, edges = builder.build(analyses)
      expect(nodes).to contain_exactly("LibClass")
      expect(edges).to match_array([
        { from: "lib.rb", to: "logger", type: "require" }
      ])
    end
  end
end
