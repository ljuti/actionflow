# frozen_string_literal: true

module Workflow
  module Steps
    class WithCallback
      def initialize(callback_key, steps, callback_steps)
        @callback_key = callback_key
        @steps = steps
        @callback_steps = callback_steps
      end

      def call(ctx)
        return ctx if ctx.stop_processing?

        scoped_reduce(ctx, @steps)

        ctx[@callback_key] = ->(callback_ctx) {
          scoped_reduce(callback_ctx, @callback_steps)
          callback_ctx
        }

        ctx
      end

      private

      def scoped_reduce(ctx, steps)
        ctx.reset_skip_remaining! unless ctx.failure?

        runner = ActionRunner.default
        reducer = Reducer.new(action_runner: runner)
        reducer.reduce(ctx, steps)

        ctx.reset_skip_remaining! unless ctx.failure? || ctx.skip_all_remaining?
        ctx
      end
    end
  end
end
