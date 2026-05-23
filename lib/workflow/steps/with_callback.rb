# frozen_string_literal: true

module Workflow
  module Steps
    class WithCallback < Step
      def initialize(callback_key, steps, callback_steps)
        @callback_key = callback_key
        @steps = steps
        @callback_steps = callback_steps
      end

      private

      def execute(ctx)
        scoped_reduce(ctx, @steps)

        ctx[@callback_key] = ->(callback_ctx) {
          scoped_reduce(callback_ctx, @callback_steps)
          callback_ctx
        }
      end
    end
  end
end
