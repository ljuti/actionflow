# frozen_string_literal: true

module Workflow
  module Steps
    class ReduceUntil
      def initialize(condition, steps)
        @condition = condition
        @steps = steps
      end

      def call(ctx)
        return ctx if ctx.stop_processing?

        until @condition.call(ctx)
          break if ctx.stop_processing?

          scoped_reduce(ctx, @steps)
        end

        ctx
      end

      private

      def scoped_reduce(ctx, steps)
        runner = ActionRunner.default
        reducer = Reducer.new(action_runner: runner)
        reducer.reduce(ctx, steps)

        ctx.reset_skip_remaining! unless ctx.failure? || ctx.skip_all_remaining?
      end
    end
  end
end
