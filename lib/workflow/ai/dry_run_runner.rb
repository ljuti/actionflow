# frozen_string_literal: true

module Workflow
  module Ai
    class DryRunRunner
      def initialize(registry:)
        @registry = registry
      end

      def analyze(plan, initial_keys: nil)
        steps = []
        side_effects = []
        risks = []
        approvals_required = []
        rollback_available = []
        missing_keys_list = []
        errors = []

        walk_steps(plan.steps, Set.new(initial_keys),
          steps:, side_effects:, risks:,
          approvals_required:, rollback_available:,
          missing_keys_list:, errors:)

        {
          steps: steps,
          side_effects: side_effects.uniq,
          risks: risks.uniq,
          approvals_required: approvals_required,
          rollback_available: rollback_available,
          missing_keys: missing_keys_list,
          errors: errors
        }
      end

      private

      def walk_steps(step_list, available_keys, acc)
        current_keys = available_keys

        step_list.each do |step|
          case step["type"]
          when "if", "if_else"
            then_steps = step["then"] || []
            walk_steps(then_steps, current_keys, acc)
            current_keys |= promised_keys_from(then_steps)

            else_steps = step["else"] || []
            walk_steps(else_steps, current_keys, acc) if step["type"] == "if_else"
          when "iterate"
            item_key = (step["as"] || "item").to_sym
            walk_steps(step["steps"] || [], current_keys | [item_key], acc)
          else
            analyze_single_step(step, current_keys, acc)
            current_keys |= promised_keys_for(step)
          end
        end
      end

      def analyze_single_step(step, available_keys, acc)
        id = step["id"]
        if id.nil?
          acc[:errors] << "Step missing 'id': #{step}"
          return
        end

        cap = begin
          @registry.fetch(id.to_sym)
        rescue KeyError
          acc[:errors] << "Unknown capability: #{id}"
          return
        end

        acc[:steps] << {id: id.to_sym}

        missing = cap.expects.reject { |k| available_keys.include?(k) }
        unless missing.empty?
          acc[:missing_keys_list] << {step: id.to_sym, missing: missing}
        end

        acc[:side_effects].concat(cap.side_effects)
        acc[:risks] << cap.risk
        acc[:approvals_required] << id.to_sym if cap.requires_approval
        acc[:rollback_available] << id.to_sym if cap.rollback_available
      end

      def promised_keys_for(step)
        id = step["id"]&.to_sym
        return Set.new unless id

        begin
          Set.new(@registry.fetch(id).promises)
        rescue KeyError
          Set.new
        end
      end

      def promised_keys_from(step_list)
        step_list.each_with_object(Set.new) do |step, keys|
          keys.merge(promised_keys_for(step))
        end
      end
    end
  end
end
