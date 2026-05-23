# frozen_string_literal: true

module Workflow
  class OrganizerSession
    def initialize(ctx)
      @ctx = ctx
      @before_hooks = []
      @after_hooks = []
      @around_hooks = []
    end

    def around_each(hook)
      @around_hooks << hook
      self
    end

    def before_each(hook)
      @before_hooks << hook
      self
    end

    def after_each(hook)
      @after_hooks << hook
      self
    end

    def reduce(*steps)
      runner = ActionRunner.new(
        before_hooks: @before_hooks,
        after_hooks: @after_hooks,
        around_hooks: @around_hooks,
        logger: Workflow.configuration.logger
      )

      reducer = Reducer.new(action_runner: runner)
      reducer.reduce(@ctx, steps)
    end
  end
end
