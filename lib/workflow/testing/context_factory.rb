# frozen_string_literal: true

module Workflow
  module Testing
    class ContextFactory
      def initialize(organizer)
        @organizer = organizer
      end

      def self.make_from(organizer)
        new(organizer)
      end

      def before(action_or_class)
        @target = action_or_class
        self
      end

      def with(overrides = {})
        @overrides = overrides
        build
      end

      private

      def build
        # Seed context with overrides so steps have their expected keys
        ctx = Context.new(@overrides)

        steps = collect_steps(@organizer)
        steps.each do |step|
          break if matches_target?(step)

          invoke_step(step, ctx)
        end

        # Re-apply overrides so they take precedence over step outputs
        @overrides.each do |key, value|
          ctx[key] = value
        end

        ctx
      end

      def matches_target?(step)
        if @target.instance_of?(Class)
          step.is_a?(@target)
        else
          step.equal?(@target)
        end
      end

      def invoke_step(step, ctx)
        if step.respond_to?(:workflow_metadata)
          ActionRunner.default.call(step, ctx)
        else
          step.call(ctx)
        end
      end

      def collect_steps(organizer)
        # Inspect the organizer's steps by walking its instance variables.
        # This is intentionally simple — it looks for common patterns:
        # - @step_name ivars that respond to #call
        # - Arrays of steps stored directly
        steps = []
        organizer.instance_variables.each do |ivar|
          val = organizer.instance_variable_get(ivar)

          if val.respond_to?(:call)
            steps << val
          elsif val.is_a?(Array)
            steps.concat(val.flatten)
          end
        end
        steps
      end
    end
  end
end
