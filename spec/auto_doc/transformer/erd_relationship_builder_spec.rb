# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::Transformer::ERDRelationshipBuilder do
  subject(:builder) { described_class }

  let(:models_with_associations) do
    [
      {
        table: "users",
        associations: [
          { type: "has_many", target: "posts", target_table: "posts" },
          { type: "belongs_to", target: "organizations", target_table: "organizations" }
        ]
      },
      {
        table: "posts",
        associations: [
          { type: "belongs_to", target: "users", target_table: "users" },
          { type: "has_one", target: "cover_image", target_table: "cover_images" }
        ]
      }
    ]
  end

  describe ".build" do
    it "returns empty array when models is nil" do
      expect(builder.build(nil)).to eq([])
    end

    it "returns empty array when models is empty" do
      expect(builder.build([])).to eq([])
    end

    it "returns relationships for has_many associations" do
      result = builder.build(models_with_associations)
      has_many_rels = result.select { |r| r[:label] == "has_many" }
      expect(has_many_rels).not_to be_empty
      expect(has_many_rels.first[:from]).to eq("users")
      expect(has_many_rels.first[:to]).to eq("posts")
    end

    it "returns relationships for belongs_to associations" do
      result = builder.build(models_with_associations)
      belongs_to_rels = result.select { |r| r[:label] == "belongs_to" }
      expect(belongs_to_rels).not_to be_empty
    end

    it "returns relationships for has_one associations" do
      result = builder.build(models_with_associations)
      has_one_rels = result.select { |r| r[:label] == "has_one" }
      expect(has_one_rels).not_to be_empty
      expect(has_one_rels.first[:from]).to eq("posts")
      expect(has_one_rels.first[:to]).to eq("cover_images")
    end

    it "sets correct cardinality for belongs_to (many-to-one)" do
      result = builder.build(models_with_associations)
      belongs_to_rel = result.find { |r| r[:label] == "belongs_to" && r[:from] == "posts" }
      expect(belongs_to_rel[:cardinality_from]).to eq("many")
      expect(belongs_to_rel[:cardinality_to]).to eq("one")
    end

    it "sets correct cardinality for has_many (one-to-many)" do
      result = builder.build(models_with_associations)
      has_many_rel = result.find { |r| r[:label] == "has_many" }
      expect(has_many_rel[:cardinality_from]).to eq("one")
      expect(has_many_rel[:cardinality_to]).to eq("many")
    end

    it "includes association type as label" do
      result = builder.build(models_with_associations)
      result.each do |rel|
        expect(%w[has_many belongs_to has_one]).to include(rel[:label])
      end
    end

    it "handles models with no associations" do
      models = [{ table: "users", associations: [] }]
      result = builder.build(models)
      expect(result).to eq([])
    end

    it "handles target_table as lowercase of target" do
      models = [
        {
          table: "users",
          associations: [
            { type: "has_many", target: "Post", target_table: nil }
          ]
        }
      ]
      # When target_table is nil, it should fall back to target.downcase
      result = builder.build(models)
      expect(result.first[:to]).to eq("post")
    end
  end
end
