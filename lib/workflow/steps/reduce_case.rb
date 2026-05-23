# frozen_string_literal: true

module Workflow
  module Steps
    class ReduceCase < Step
      def initialize(value_fn, branches)
        @value_fn = value_fn
        @branches = branches
      end

      private

      def execute(ctx, action_runner:)
        scoped_reduce(ctx, @branches[@value_fn.call(ctx)], action_runner: action_runner)
      end
    end
  end
end
