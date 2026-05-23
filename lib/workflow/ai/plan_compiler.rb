# frozen_string_literal: true

module Workflow
  module Ai
    class PlanCompiler
      def initialize(registry:)
        @registry = registry
      end

      def compile(plan)
        plan.steps.map { |step| compile_step(step) }
      end

      private

      def compile_step(step)
        case step["type"]
        when "if_else"
          condition = build_condition(step.fetch("condition"))
          if_steps = (step["then"] || []).map { |s| compile_step(s) }
          else_steps = (step["else"] || []).map { |s| compile_step(s) }
          Steps::ReduceIfElse.new(condition, if_steps, else_steps)
        when "if"
          condition = build_condition(step.fetch("condition"))
          then_steps = (step["then"] || []).map { |s| compile_step(s) }
          Steps::ReduceIf.new(condition, then_steps)
        when "iterate"
          collection_key = step.fetch("collection")
          steps = (step["steps"] || []).map { |s| compile_step(s) }
          item_key = step["as"]
          Steps::Iterate.new(collection_key, steps, item_key: item_key)
        else
          # Linear step — resolve to action from registry
          @registry.fetch(step.fetch("id").to_sym).action
        end
      end

      def build_condition(condition_spec)
        key = condition_spec.fetch("key")
        expected = condition_spec.fetch("equals")

        ->(ctx) { ctx[key] == expected }
      end
    end
  end
end
