# frozen_string_literal: true

require "spec_helper"

RSpec.describe AutoDoc::Orchestrator::BaseStep do
  subject(:step) { described_class.new }

  let(:say_spy) { double("say") }
  let(:context) { { say: say_spy } }

  describe "#run" do
    it "raises NotImplementedError" do
      expect { step.run(context) }.to raise_error(NotImplementedError)
    end

    it "error message includes class name" do
      expect { step.run(context) }.to raise_error(NotImplementedError, /BaseStep/)
    end
  end

  describe "#say" do
    before do
      allow(say_spy).to receive(:call)
    end

    it "calls context[:say] with message" do
      expect(say_spy).to receive(:call).with("hello", nil)
      step.send(:say, context, "hello")
    end

    it "calls context[:say] with message and color" do
      expect(say_spy).to receive(:call).with("error", :red)
      step.send(:say, context, "error", :red)
    end

    it "does nothing when context[:say] is nil" do
      expect { step.send(:say, { say: nil }, "msg") }.not_to raise_error
    end
  end
end
