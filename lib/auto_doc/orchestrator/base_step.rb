# frozen_string_literal: true

module AutoDoc
  class Orchestrator
    class BaseStep
      def run(context)
        raise NotImplementedError, "#{self.class} must implement #run"
      end

      protected

      def say(context, msg, color = nil)
        context[:say]&.call(msg, color)
      end
    end
  end
end
