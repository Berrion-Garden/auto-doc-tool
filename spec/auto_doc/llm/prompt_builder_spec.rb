# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::LLM::PromptBuilder do
  let(:sample_analyses) do
    {
      "src/lib/foo/foo.rb" => {
        definitions: [
          { type: "class", name: "Foo", has_doc?: true },
          { type: "method", name: "bar", has_doc?: false }
        ]
      },
      "src/lib/baz.rb" => {
        definitions: [
          { type: "module", name: "Baz", has_doc?: true }
        ]
      },
      "src/app/controller.rb" => {
        definitions: [
          { type: "class", name: "Controller", has_doc?: false }
        ]
      }
    }
  end

  describe ".build" do
    context "with :summary type" do
      it "returns a user message prompt" do
        messages = described_class.build(:summary, "lib/foo", sample_analyses)
        expect(messages).to be_an(Array)
        expect(messages.first[:role]).to eq("user")
        expect(messages.first[:content]).to be_a(String)
      end

      it "includes the dir name in the prompt" do
        messages = described_class.build(:summary, "lib/foo", sample_analyses)
        content = messages.first[:content]
        expect(content).to include("lib/foo")
      end

      it "includes file names and class names from matching metadata" do
        messages = described_class.build(:summary, "lib/foo", sample_analyses)
        content = messages.first[:content]
        # Only paths containing "/lib/foo/" are included
        expect(content).to include("src/lib/foo/foo.rb")
        expect(content).to include("`Foo`")
        expect(content).to include("`bar`")
        # src/lib/baz.rb and src/app/controller.rb don't match /lib/foo/
        expect(content).not_to include("src/lib/baz.rb")
        expect(content).not_to include("src/app/controller.rb")
      end

      it "does NOT contain source code patterns" do
        messages = described_class.build(:summary, "lib/foo", sample_analyses)
        content = messages.first[:content]
        expect(content).not_to include("def ")
      end

      it "does NOT contain Ruby-specific language" do
        messages = described_class.build(:summary, "lib/foo", sample_analyses)
        content = messages.first[:content]
        expect(content).not_to include("Ruby")
      end
    end

    context "with :architecture type" do
      it "returns a user message prompt including the project name" do
        messages = described_class.build(:architecture, "MyProject", sample_analyses)
        expect(messages.first[:role]).to eq("user")
        expect(messages.first[:content]).to include("MyProject")
      end

      it "includes metadata from all analyses" do
        messages = described_class.build(:architecture, "MyProject", sample_analyses)
        content = messages.first[:content]
        expect(content).to include("src/lib/foo/foo.rb")
        expect(content).to include("src/lib/baz.rb")
      end

      it "does NOT contain source code patterns" do
        messages = described_class.build(:architecture, "MyProject", sample_analyses)
        expect(messages.first[:content]).not_to include("def ")
      end

      it "does NOT contain Ruby-specific language" do
        messages = described_class.build(:architecture, "MyProject", sample_analyses)
        expect(messages.first[:content]).not_to include("Ruby")
      end
    end

    context "with :components type" do
      it "returns a user message prompt grouped by top-level directory" do
        messages = described_class.build(:components, nil, sample_analyses)
        content = messages.first[:content]
        # Grouped by path.split("/").first(2).join("/")
        # src/lib/foo/foo.rb → "src/lib", src/lib/baz.rb → "src/lib"
        # src/app/controller.rb → "src/app"
        expect(content).to include("### src/lib")
        expect(content).to include("### src/app")
        expect(content).to include("src/lib/foo/foo.rb")
        expect(content).to include("`Foo`")
        expect(content).to include("src/app/controller.rb")
        expect(content).to include("`Controller`")
      end

      it "does NOT contain source code patterns" do
        messages = described_class.build(:components, nil, sample_analyses)
        expect(messages.first[:content]).not_to include("def ")
      end
    end

    context "with :architecture_full type" do
      it "returns a user message prompt including the project name" do
        messages = described_class.build(:architecture_full, "MyProject", sample_analyses)
        content = messages.first[:content]
        expect(content).to include("MyProject")
      end

      it "includes metadata from all analyses" do
        messages = described_class.build(:architecture_full, "MyProject", sample_analyses)
        content = messages.first[:content]
        expect(content).to include("src/lib/foo/foo.rb")
        expect(content).to include("src/lib/baz.rb")
      end

      it "does NOT contain source code patterns" do
        messages = described_class.build(:architecture_full, "MyProject", sample_analyses)
        expect(messages.first[:content]).not_to include("def ")
      end

      it "instructs the LLM to use markdown sections" do
        messages = described_class.build(:architecture_full, "MyProject", sample_analyses)
        content = messages.first[:content]
        expect(content).to include("markdown sections")
      end
    end

    context "with :system_context type" do
      it "includes the project name" do
        messages = described_class.build(:system_context, "MyProject", sample_analyses)
        expect(messages.first[:content]).to include("MyProject")
      end

      it "mentions external systems" do
        messages = described_class.build(:system_context, "MyProject", sample_analyses)
        expect(messages.first[:content]).to match(/external/i)
      end

      it "mentions JSON format" do
        messages = described_class.build(:system_context, "MyProject", sample_analyses)
        expect(messages.first[:content]).to match(/json/i)
      end

      it "includes metadata from all analyses" do
        messages = described_class.build(:system_context, "MyProject", sample_analyses)
        content = messages.first[:content]
        expect(content).to include("src/lib/foo/foo.rb")
      end
    end

    context "with :containers type" do
      let(:module_roots) { %w[app lib] }

      it "includes module root sections when analyses match" do
        messages = described_class.build(:containers, nil, sample_analyses, module_roots)
        content = messages.first[:content]
        # src/app/controller.rb.include?("/app/") → true
        expect(content).to include("## Module Root: app")
        expect(content).to include("src/app/controller.rb")
        # src/lib/foo/foo.rb and src/lib/baz.rb both include "/lib/"
        expect(content).to include("## Module Root: lib")
        expect(content).to include("src/lib/foo/foo.rb")
        expect(content).to include("src/lib/baz.rb")
      end

      it "filters analyses to only include files within module roots" do
        analyses = {
          "src/app/foo.rb" => { definitions: [{ type: "class", name: "Foo", has_doc?: true }] },
          "vendor/gem.rb" => { definitions: [{ type: "class", name: "Gem", has_doc?: true }] }
        }
        messages = described_class.build(:containers, nil, analyses, module_roots)
        content = messages.first[:content]
        # src/app/foo.rb.include?("/app/") → true
        expect(content).to include("src/app/foo.rb")
        # vendor/gem.rb.include?("/app/") → false, "/lib/" → false
        expect(content).not_to include("vendor/gem.rb")
      end
    end
  end
end
