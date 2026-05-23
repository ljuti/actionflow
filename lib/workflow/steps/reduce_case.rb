# frozen_string_literal: true

module Workflow
  module Steps
    class ReduceCase
      def initialize(value_fn, branches)
        @value_fn = value_fn
        @branches = branches
      end

      def call(ctx)
        return ctx if ctx.stop_processing?

        value = @value_fn.call(ctx)
        matching_steps = @branches[value]

        if matching_steps
          scoped_reduce(ctx, matching_steps)
        end

        ctx
      end

      private

      def scoped_reduce(ctx, steps)
        ctx.reset_skip_remaining!

        runner = ActionRunner.default
        reducer = Reducer.new(action_runner: runner)
        reducer.reduce(ctx, steps)

        ctx.reset_skip_remaining! unless ctx.failure? || ctx.skip_all_remaining?
        ctx
      end
    end
  end
end
