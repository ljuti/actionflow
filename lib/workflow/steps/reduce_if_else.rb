# frozen_string_literal: true

module Workflow
  module Steps
    class ReduceIfElse < Step
      def initialize(condition, if_steps, else_steps)
        @condition = condition
        @if_steps = if_steps
        @else_steps = else_steps
      end

      private

      def execute(ctx)
        if @condition.call(ctx)
          scoped_reduce(ctx, @if_steps)
        else
          scoped_reduce(ctx, @else_steps)
        end
      end
    end
  end
end
