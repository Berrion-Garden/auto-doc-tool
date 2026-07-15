# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::Analyzer::OrphansService do
  describe ".run" do
    subject(:result) { described_class.run(project_dir, options: options, say: ->(*) {}) }

    context "with a non-Rails project" do
      let(:project_dir) { fixture_path("sample_ruby_project") }
      let(:options) { {} }

      it "returns orphans" do
        expect(result[:orphans]).not_to be_empty
        expect(result[:by_directory]).to be_a(Hash)
      end
    end

    context "with a Rails project and rails mode" do
      let(:project_dir) { fixture_path("rails_project") }
      let(:options) { { rails: true } }

      it "excludes autoloaded Rails paths" do
        expect(result[:orphans]).not_to include(a_string_matching("app/models"))
        expect(result[:orphans]).not_to include(a_string_matching("app/controllers"))
        expect(result[:orphans]).not_to include(a_string_matching("app/serializers"))
        expect(result[:orphans]).not_to include(a_string_matching("app/jobs"))
        expect(result[:orphans]).not_to include(a_string_matching("app/mailers"))
        expect(result[:orphans]).not_to include(a_string_matching("app/helpers"))
        expect(result[:orphans]).not_to include(a_string_matching("app/services"))
        expect(result[:orphans]).to include(a_string_matching("lib/some_helper.rb"))
        expect(result[:orphans]).to include(a_string_matching("bin/custom_script.rb"))
      end

      it "produces a directory breakdown that includes non-app directories" do
        expect(result[:by_directory]).to have_key("lib")
        expect(result[:by_directory]).to have_key("bin")
        expect(result[:by_directory]["lib"]).to eq(1)
        expect(result[:by_directory]["bin"]).to eq(1)
      end
    end

    context "with a Rails project and no rails mode" do
      let(:project_dir) { fixture_path("rails_project") }
      let(:options) { {} }

      it "includes autoloaded Rails paths" do
        expect(result[:orphans]).to include(a_string_matching("app/models"))
      end
    end
  end
end
