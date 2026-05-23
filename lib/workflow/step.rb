# frozen_string_literal: true

module Workflow
  class Step
    def call(ctx)
      return ctx if ctx.stop_processing?

      execute(ctx)
      ctx
    end

    private

    def execute(_ctx)
      raise NotImplementedError, "#{self.class} must implement #execute"
    end

    def scoped_reduce(ctx, steps)
      runner = ActionRunner.default
      reducer = Reducer.new(action_runner: runner)
      reducer.reduce(ctx, steps)

      ctx.reset_skip_remaining! unless ctx.failure? || ctx.skip_all_remaining?
    end
  end
end
