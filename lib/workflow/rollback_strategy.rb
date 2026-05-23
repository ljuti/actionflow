# frozen_string_literal: true

module Workflow
  class RollbackStrategy
    def rollback(ctx, steps)
      steps.reverse_each do |step|
        step.rollback(ctx) if step.respond_to?(:rollback)
      end

      ctx
    end
  end
end
