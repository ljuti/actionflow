# frozen_string_literal: true

module Workflow
  module Steps
    class ReduceIfElse
      def initialize(condition, if_steps, else_steps)
        @condition = condition
        @if_steps = if_steps
        @else_steps = else_steps
      end

      def call(ctx)
        return ctx if ctx.stop_processing?

        if @condition.call(ctx)
          scoped_reduce(ctx, @if_steps)
        else
          scoped_reduce(ctx, @else_steps)
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
