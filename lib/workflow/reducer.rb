# frozen_string_literal: true

module Workflow
  class Reducer
    def initialize(action_runner:)
      @action_runner = action_runner
    end

    def reduce(ctx, steps)
      executed_steps = []

      Array(steps).flatten.each do |step|
        break if ctx.stop_processing?

        executed_steps << step
        invoke(step, ctx)
      rescue FailWithRollback
        rollback(ctx, executed_steps.reverse)
      end

      ctx
    end

    private

    def invoke(step, ctx)
      if workflow_action?(step)
        @action_runner.call(step, ctx)
      elsif step.is_a?(Step)
        step.call(ctx, action_runner: @action_runner)
      else
        step.call(ctx)
      end
    end

    def workflow_action?(step)
      step.respond_to?(:workflow_metadata)
    end

    def rollback(ctx, steps)
      steps.each do |step|
        step.rollback(ctx) if step.respond_to?(:rollback)
      end
    end
  end
end
