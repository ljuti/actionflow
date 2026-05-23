# frozen_string_literal: true

module Workflow
  module Steps
    class ReduceIf < Step
      def initialize(condition, steps)
        @condition = condition
        @steps = steps
      end

      private

      def execute(ctx)
        scoped_reduce(ctx, @steps) if @condition.call(ctx)
      end
    end
  end
end
