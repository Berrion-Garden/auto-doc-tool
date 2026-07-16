# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::Transformer::FilesDataBuilder do
  subject(:builder) { described_class }

  let(:analyses) do
    {
      "/project/app/models/user.rb" => {
        definitions: [{ name: "User", type: :class }],
        imports: [{ path: "active_record", type: :require }]
      },
      "/project/lib/math_utils.rb" => {
        definitions: [{ name: "MathUtils", type: :module }],
        imports: [{ path: "json", type: :require }]
      }
    }
  end

  describe ".build" do
    it "returns sorted file records" do
      result = builder.build(analyses)
      expect(result.size).to eq(2)
      expect(result[0][:name]).to eq("math_utils.rb")
      expect(result[1][:name]).to eq("user.rb")
    end

    it "includes file basename as name" do
      result = builder.build(analyses)
      expect(result.map { |r| r[:name] }).to contain_exactly("math_utils.rb", "user.rb")
    end

    it "includes full path as path" do
      result = builder.build(analyses)
      expect(result.map { |r| r[:path] }).to contain_exactly(
        "/project/app/models/user.rb",
        "/project/lib/math_utils.rb"
      )
    end

    it "includes definitions as classes" do
      result = builder.build(analyses)
      user_record = result.find { |r| r[:name] == "user.rb" }
      expect(user_record[:classes]).to eq([{ name: "User", type: :class }])
    end

    it "includes imports" do
      result = builder.build(analyses)
      user_record = result.find { |r| r[:name] == "user.rb" }
      expect(user_record[:imports]).to eq([{ path: "active_record", type: :require }])
    end

    it "handles empty analyses" do
      expect(builder.build({})).to eq([])
    end

    it "handles analyses with no definitions" do
      analyses = { "file.rb" => { definitions: [], imports: [] } }
      result = builder.build(analyses)
      expect(result.size).to eq(1)
      expect(result.first[:classes]).to eq([])
    end

    it "handles analyses with no imports" do
      analyses = { "file.rb" => { definitions: [{ name: "Foo", type: :class }] } }
      result = builder.build(analyses)
      expect(result.first[:imports]).to eq([])
    end

    it "sorts alphabetically by filename" do
      analyses = {
        "z.rb" => { definitions: [], imports: [] },
        "a.rb" => { definitions: [], imports: [] },
        "m.rb" => { definitions: [], imports: [] }
      }
      result = builder.build(analyses)
      expect(result.map { |r| r[:name] }).to eq(%w[a.rb m.rb z.rb])
    end

    it "is case-insensitive in sorting" do
      analyses = {
        "B.rb" => { definitions: [], imports: [] },
        "a.rb" => { definitions: [], imports: [] }
      }
      result = builder.build(analyses)
      expect(result.map { |r| r[:name] }).to eq(%w[a.rb B.rb])
    end
  end
end
