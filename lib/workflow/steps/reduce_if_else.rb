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

      def execute(ctx, action_runner:)
        if @condition.call(ctx)
          scoped_reduce(ctx, @if_steps, action_runner: action_runner)
        else
          scoped_reduce(ctx, @else_steps, action_runner: action_runner)
        end
      end
    end
  end
end
