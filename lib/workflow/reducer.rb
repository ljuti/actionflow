# frozen_string_literal: true

module Workflow
  class Reducer
    def initialize(action_runner:, rollback_strategy: RollbackStrategy.new)
      @action_runner = action_runner
      @rollback_strategy = rollback_strategy
    end

    def reduce(ctx, steps)
      executed_steps = []

      Array(steps).flatten.each do |step|
        break if ctx.stop_processing?

        executed_steps << step
        invoke(step, ctx)
      rescue FailWithRollback
        @rollback_strategy.rollback(ctx, executed_steps.reverse)
      end

      ctx
    end

    private

    def invoke(step, ctx)
      if workflow_action?(step)
        @action_runner.call(step, ctx)
      else
        step.call(ctx)
      end
    end

    def workflow_action?(step)
      step.respond_to?(:workflow_metadata)
    end
  end
end
