# frozen_string_literal: true

module Workflow
  class Step
    def call(ctx, action_runner: ActionRunner.default)
      return ctx if ctx.stop_processing?

      execute(ctx, action_runner: action_runner)
      ctx
    end

    private

    def execute(_ctx, action_runner:)
      raise NotImplementedError, "#{self.class} must implement #execute"
    end

    def scoped_reduce(ctx, steps, action_runner:)
      reducer = Reducer.new(action_runner: action_runner)
      reducer.reduce(ctx, steps)

      ctx.reset_skip_remaining! unless ctx.failure? || ctx.skip_all_remaining?
    end
  end
end
