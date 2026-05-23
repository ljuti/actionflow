# frozen_string_literal: true

module Workflow
  module Steps
    class ReduceWhile < Step
      def initialize(condition, steps)
        @condition = condition
        @steps = steps
      end

      private

      def execute(ctx)
        while @condition.call(ctx)
          break if ctx.stop_processing?

          scoped_reduce(ctx, @steps)
        end
      end
    end
  end
end
