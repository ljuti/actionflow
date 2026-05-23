# frozen_string_literal: true

module Workflow
  module Steps
    class ReduceWhile < Step
      def initialize(condition, steps)
        @condition = condition
        @steps = steps
      end

      private

      def execute(ctx, action_runner:)
        while @condition.call(ctx)
          break if ctx.stop_processing?

          scoped_reduce(ctx, @steps, action_runner: action_runner)
        end
      end
    end
  end
end
