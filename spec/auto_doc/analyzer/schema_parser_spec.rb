# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::Analyzer::SchemaParser do
  describe ".parse" do
    let(:rails_project) { fixture_path("rails_project") }

    context "with a valid Rails project" do
      let(:tables) { described_class.parse(rails_project) }

      it "parses all tables" do
        expect(tables).to be_an(Array)
        table_names = tables.map { |t| t[:table_name] }
        expect(table_names).to contain_exactly("users", "posts", "comments")
      end

      it "parses users table columns" do
        users_table = tables.find { |t| t[:table_name] == "users" }
        expect(users_table).not_to be_nil
        columns = users_table[:columns]

        expect(columns).to be_an(Array)
        col_names = columns.map { |c| c[:name] }
        expect(col_names).to include("name", "email", "created_at", "updated_at")
      end

      it "detects column types (string, integer, datetime, boolean, text)" do
        posts_table = tables.find { |t| t[:table_name] == "posts" }
        expect(posts_table).not_to be_nil
        columns = posts_table[:columns]

        title_col = columns.find { |c| c[:name] == "title" }
        expect(title_col[:type]).to eq("string")

        body_col = columns.find { |c| c[:name] == "body" }
        expect(body_col[:type]).to eq("text")

        user_id_col = columns.find { |c| c[:name] == "user_id" }
        expect(user_id_col[:type]).to eq("integer")

        published_col = columns.find { |c| c[:name] == "published" }
        expect(published_col[:type]).to eq("boolean")

        created_at_col = columns.find { |c| c[:name] == "created_at" }
        expect(created_at_col[:type]).to eq("datetime")
      end

      it "detects null: false constraints" do
        users_table = tables.find { |t| t[:table_name] == "users" }
        email_col = users_table[:columns].find { |c| c[:name] == "email" }
        expect(email_col[:null]).to be false

        name_col = users_table[:columns].find { |c| c[:name] == "name" }
        expect(name_col[:null]).to be true
      end

      it "detects default values" do
        posts_table = tables.find { |t| t[:table_name] == "posts" }
        published_col = posts_table[:columns].find { |c| c[:name] == "published" }
        expect(published_col[:default]).to eq("false")
      end

      it "parses index definitions" do
        comments_table = tables.find { |t| t[:table_name] == "comments" }
        expect(comments_table[:indexes]).to be_an(Array)
        index_names = comments_table[:indexes].map { |i| i[:name] }
        expect(index_names).to include("index_comments_on_post_id", "index_comments_on_user_id")
      end

      it "parses multi-column indexes" do
        posts_table = tables.find { |t| t[:table_name] == "posts" }
        indexes = posts_table[:indexes]
        multi_col = indexes.find { |i| i[:name] == "index_posts_on_user_and_published" }
        expect(multi_col).not_to be_nil
        expect(multi_col[:columns]).to eq(["user_id", "published"])
      end

      it "parses foreign key references" do
        comments_table = tables.find { |t| t[:table_name] == "comments" }
        expect(comments_table[:foreign_keys]).to be_an(Array)
        expect(comments_table[:foreign_keys].length).to eq(2)

        post_fk = comments_table[:foreign_keys].find { |fk| fk[:to_table] == "posts" }
        expect(post_fk).not_to be_nil
        expect(post_fk[:from_table]).to eq("comments")
        expect(post_fk[:column]).to eq("post_id")

        user_fk = comments_table[:foreign_keys].find { |fk| fk[:to_table] == "users" }
        expect(user_fk).not_to be_nil
        expect(user_fk[:from_table]).to eq("comments")
        expect(user_fk[:column]).to eq("user_id")
      end

      it "includes migration timestamps from migrate directory" do
        users_table = tables.find { |t| t[:table_name] == "users" }
        expect(users_table[:migration_timestamps]).to include("20240101000000")
      end
    end

    context "with empty schema.rb" do
      let(:empty_project) { fixture_path("rails_project") }

      it "returns empty array when schema.rb is empty" do
        # Create a temp dir with empty schema.rb
        Dir.mktmpdir do |dir|
          FileUtils.mkdir_p(File.join(dir, "db"))
          File.write(File.join(dir, "db", "schema.rb"), "")
          result = described_class.parse(dir)
          expect(result).to eq([])
        end
      end
    end

    context "with create_table and do |t| on next line" do
      it "handles create_table with do block on the next line" do
        Dir.mktmpdir do |dir|
          FileUtils.mkdir_p(File.join(dir, "db"))
          File.write(File.join(dir, "db", "schema.rb"), <<~SCHEMA)
            ActiveRecord::Schema[7.0].define do
              create_table "widgets", force: :cascade
                do |t|
                t.string "name", null: false
                t.integer "count"
              end
            end
          SCHEMA
          result = described_class.parse(dir)
          expect(result.length).to eq(1)
          expect(result.first[:table_name]).to eq("widgets")
          col_names = result.first[:columns].map { |c| c[:name] }
          expect(col_names).to include("name", "count")
        end
      end
    end

    context "with deeply indented end" do
      it "handles deeply indented end blocks" do
        Dir.mktmpdir do |dir|
          FileUtils.mkdir_p(File.join(dir, "db"))
          File.write(File.join(dir, "db", "schema.rb"), <<~SCHEMA)
            ActiveRecord::Schema[7.0].define do
                create_table "gadgets", force: :cascade do |t|
                    t.string "label"
                end
            end
          SCHEMA
          result = described_class.parse(dir)
          expect(result.length).to eq(1)
          expect(result.first[:table_name]).to eq("gadgets")
        end
      end
    end

    context "with missing schema.rb" do
      it "returns empty array" do
        Dir.mktmpdir do |dir|
          result = described_class.parse(dir)
          expect(result).to eq([])
        end
      end
    end
  end
end
