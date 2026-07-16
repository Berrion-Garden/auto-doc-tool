# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::LLM::Enricher do
  subject(:enricher) { described_class }

  let(:analyses) do
    {
      "/project/app/controllers/users_controller.rb" => {
        definitions: [
          { name: "UsersController", type: "class", has_doc?: true },
          { name: "index", type: "method", has_doc?: true }
        ],
        docs: []
      },
      "/project/app/models/user.rb" => {
        definitions: [
          { name: "User", type: "class", has_doc?: true },
          { name: "validates", type: "method", has_doc?: false }
        ],
        docs: []
      },
      "/project/lib/services/user_service.rb" => {
        definitions: [
          { name: "UserService", type: "module", has_doc?: true }
        ],
        docs: []
      }
    }
  end

  describe ".enrich_analyses" do
    context "when LLM is primary and configured" do
      let(:config) do
        config = primary_llm_config
        allow(config).to receive(:module_roots).and_return(%w[app lib])
        config
      end

      before do
        mock_llm_client({
          "app" => "UsersController: Handles HTTP requests\nUser: Represents user data and authentication\nindex: Returns a paginated list of users\nvalidates: Validates user attributes before save",
          "lib" => "UserService: Orchestrates user-related business logic"
        })
      end

      it "populates docs arrays with summary entries" do
        result = enricher.enrich_analyses(analyses, config)

        # users_controller.rb should have 2 docs
        users_controller_docs = result["/project/app/controllers/users_controller.rb"][:docs]
        expect(users_controller_docs.size).to eq(2)

        # user.rb should have 2 docs
        user_docs = result["/project/app/models/user.rb"][:docs]
        expect(user_docs.size).to eq(2)

        # user_service.rb should have 1 doc
        user_service_docs = result["/project/lib/services/user_service.rb"][:docs]
        expect(user_service_docs.size).to eq(1)
      end

      it "includes target_name, target_type, and summary in each doc entry" do
        result = enricher.enrich_analyses(analyses, config)
        entry = result["/project/app/controllers/users_controller.rb"][:docs].first

        expect(entry).to have_key(:target_name)
        expect(entry).to have_key(:target_type)
        expect(entry).to have_key(:summary)
      end

      it "assigns correct summary text to each symbol" do
        result = enricher.enrich_analyses(analyses, config)
        users_controller_docs = result["/project/app/controllers/users_controller.rb"][:docs]

        users_controller_entry = users_controller_docs.find { |d| d[:target_name] == "UsersController" }
        expect(users_controller_entry[:summary]).to eq("Handles HTTP requests")

        index_entry = users_controller_docs.find { |d| d[:target_name] == "index" }
        expect(index_entry[:summary]).to eq("Returns a paginated list of users")
      end

      it "assigns summaries to the correct files across module roots" do
        result = enricher.enrich_analyses(analyses, config)

        # UserService belongs to the lib module — its summary should come from the lib response
        user_service_docs = result["/project/lib/services/user_service.rb"][:docs]
        expect(user_service_docs.size).to eq(1)
        expect(user_service_docs.first[:target_name]).to eq("UserService")
        expect(user_service_docs.first[:summary]).to eq("Orchestrates user-related business logic")
      end

      it "returns the same analyses hash (object identity preserved)" do
        result = enricher.enrich_analyses(analyses, config)
        expect(result.object_id).to eq(analyses.object_id)
      end

      it "does not modify files that don't belong to any module root" do
        analyses_with_extra = analyses.merge(
          "/project/vendor/gem/lib/foo.rb" => {
            definitions: [
              { name: "Foo", type: "class", has_doc?: true }
            ],
            docs: []
          }
        )

        result = enricher.enrich_analyses(analyses_with_extra, config)
        expect(result["/project/vendor/gem/lib/foo.rb"][:docs]).to be_empty
      end
    end

    context "when config.llm_primary? is false" do
      let(:config) do
        config = standard_llm_config
        allow(config).to receive(:module_roots).and_return(%w[app lib])
        config
      end

      it "returns analyses unchanged" do
        result = enricher.enrich_analyses(analyses, config)

        result.each_value do |analysis|
          expect(analysis[:docs]).to be_empty
        end
      end

      it "does not call Client.build_if_configured" do
        enricher.enrich_analyses(analyses, config)
        expect(AutoDoc::LLM::Client).not_to have_received(:build_if_configured)
      end
    end

    context "when Client.build_if_configured returns nil" do
      let(:config) do
        config = primary_llm_config
        allow(config).to receive(:module_roots).and_return(%w[app lib])
        config
      end

      # spec_helper already stubs build_if_configured to return nil in before(:each)

      it "returns analyses unchanged" do
        result = enricher.enrich_analyses(analyses, config)

        result.each_value do |analysis|
          expect(analysis[:docs]).to be_empty
        end
      end
    end

    context "when LLM returns nil for a module" do
      let(:config) do
        config = primary_llm_config
        allow(config).to receive(:module_roots).and_return(%w[app lib])
        config
      end

      before do
        # Only "app" returns nil; "lib" returns valid data
        mock_llm_client({
          "app" => nil,
          "lib" => "UserService: Orchestrates user-related business logic"
        })
      end

      it "logs a warning for the nil module and continues processing other modules" do
        expect($stderr).to receive(:puts).with(/Enricher.*nil.*app/)

        result = enricher.enrich_analyses(analyses, config)

        # The lib module should still be processed successfully
        user_service_docs = result["/project/lib/services/user_service.rb"][:docs]
        expect(user_service_docs.size).to eq(1)
        expect(user_service_docs.first[:target_name]).to eq("UserService")

        # The app module files should have no docs (nil LLM response)
        expect(result["/project/app/controllers/users_controller.rb"][:docs]).to be_empty
        expect(result["/project/app/models/user.rb"][:docs]).to be_empty
      end
    end

    context "when LLM returns empty response" do
      let(:config) do
        config = primary_llm_config
        allow(config).to receive(:module_roots).and_return(%w[app])
        config
      end

      before do
        mock_llm_client({
          "app" => ""
        })
      end

      it "does not modify docs arrays" do
        result = enricher.enrich_analyses(analyses, config)

        result.each_value do |analysis|
          expect(analysis[:docs]).to be_empty
        end
      end
    end

    context "with symbols that have namespaced names" do
      let(:analyses_with_namespaced) do
        {
          "/project/lib/services/payment.rb" => {
            definitions: [
              { name: "Payment::Processor", type: "class", has_doc?: true },
              { name: "Payment::Validator", type: "class", has_doc?: true }
            ],
            docs: []
          }
        }
      end

      let(:config) do
        config = primary_llm_config
        allow(config).to receive(:module_roots).and_return(%w[lib])
        config
      end

      before do
        mock_llm_client({
          "lib" => "Payment::Processor: Processes payments via external gateway\nPayment::Validator: Validates payment parameters"
        })
      end

      it "handles :: in symbol names by converting to underscores in entry_id" do
        result = enricher.enrich_analyses(analyses_with_namespaced, config)
        docs = result["/project/lib/services/payment.rb"][:docs]

        expect(docs.size).to eq(2)

        processor = docs.find { |d| d[:target_name] == "Payment::Processor" }
        expect(processor[:summary]).to eq("Processes payments via external gateway")

        validator = docs.find { |d| d[:target_name] == "Payment::Validator" }
        expect(validator[:summary]).to eq("Validates payment parameters")
      end
    end
  end
end
