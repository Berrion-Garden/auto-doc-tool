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

      it "parses through: option" do
        post_model = models.find { |m| m[:model] == "Post" }
        commenters_assoc = post_model[:associations].find { |a| a[:target] == "commenters" }
        expect(commenters_assoc).not_to be_nil
        expect(commenters_assoc[:options]).to include(through: :comments)
      end

      it "parses class_name: option" do
        post_model = models.find { |m| m[:model] == "Post" }
        commenters_assoc = post_model[:associations].find { |a| a[:target] == "commenters" }
        expect(commenters_assoc).not_to be_nil
        expect(commenters_assoc[:options]).to include(class_name: "User")
      end

      it "includes both belongs_to and has_many for Post model" do
        post_model = models.find { |m| m[:model] == "Post" }
        types = post_model[:associations].map { |a| a[:type] }
        expect(types).to include("belongs_to", "has_many")
      end
    end

    context "with string syntax associations" do
      it "parses has_many with string target (has_many \"items\")" do
        Dir.mktmpdir do |dir|
          FileUtils.mkdir_p(File.join(dir, "app", "models"))
          File.write(File.join(dir, "app", "models", "account.rb"), <<~RUBY)
            class Account < ApplicationRecord
              has_many "orders", dependent: :destroy
            end
          RUBY
          result = described_class.parse(dir)
          expect(result.length).to eq(1)
          account = result.first
          expect(account[:model]).to eq("Account")
          assoc = account[:associations].first
          expect(assoc[:type]).to eq("has_many")
          expect(assoc[:target]).to eq("orders")
          expect(assoc[:options]).to include(dependent: :destroy)
        end
      end

      it "parses belongs_to with string target and class_name" do
        Dir.mktmpdir do |dir|
          FileUtils.mkdir_p(File.join(dir, "app", "models"))
          File.write(File.join(dir, "app", "models", "profile.rb"), <<~RUBY)
            class Profile < ApplicationRecord
              belongs_to "account", class_name: "Account"
            end
          RUBY
          result = described_class.parse(dir)
          expect(result.length).to eq(1)
          profile = result.first
          assoc = profile[:associations].first
          expect(assoc[:type]).to eq("belongs_to")
          expect(assoc[:target]).to eq("account")
          expect(assoc[:options]).to include(class_name: "Account")
        end
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
