# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::Analyzer::ModelAssociationParser do
  describe ".parse" do
    let(:rails_project) { fixture_path("rails_project") }

    context "with a valid Rails project" do
      let(:models) { described_class.parse(rails_project) }

      it "parses all model files" do
        expect(models).to be_an(Array)
        model_names = models.map { |m| m[:model] }
        expect(model_names).to contain_exactly("User", "Post", "Comment")
      end

      it "infers correct table names from class names" do
        user_model = models.find { |m| m[:model] == "User" }
        expect(user_model[:table]).to eq("users")

        post_model = models.find { |m| m[:model] == "Post" }
        expect(post_model[:table]).to eq("posts")

        comment_model = models.find { |m| m[:model] == "Comment" }
        expect(comment_model[:table]).to eq("comments")
      end

      it "extracts belongs_to associations" do
        comment_model = models.find { |m| m[:model] == "Comment" }
        belongs_to = comment_model[:associations].select { |a| a[:type] == "belongs_to" }
        expect(belongs_to.length).to eq(2)

        targets = belongs_to.map { |a| a[:target] }
        expect(targets).to include("post", "user")
      end

      it "extracts has_many associations" do
        user_model = models.find { |m| m[:model] == "User" }
        has_many = user_model[:associations].select { |a| a[:type] == "has_many" }
        expect(has_many.length).to eq(2)

        targets = has_many.map { |a| a[:target] }
        expect(targets).to include("posts", "comments")
      end

      it "parses association options" do
        user_model = models.find { |m| m[:model] == "User" }
        posts_assoc = user_model[:associations].find { |a| a[:target] == "posts" }
        expect(posts_assoc[:options]).to include(dependent: :destroy)
      end

      it "includes both belongs_to and has_many for Post model" do
        post_model = models.find { |m| m[:model] == "Post" }
        types = post_model[:associations].map { |a| a[:type] }
        expect(types).to include("belongs_to", "has_many")
      end
    end

    context "with empty models directory" do
      it "returns empty array" do
        Dir.mktmpdir do |dir|
          FileUtils.mkdir_p(File.join(dir, "app", "models"))
          result = described_class.parse(dir)
          expect(result).to eq([])
        end
      end
    end

    context "with non-existent app/models directory" do
      it "returns empty array" do
        Dir.mktmpdir do |dir|
          result = described_class.parse(dir)
          expect(result).to eq([])
        end
      end
    end
  end
end
