# frozen_string_literal: true

module Workflow
  module Ai
    class PlanValidator
      class ValidationResult
        attr_reader :errors

        def initialize(errors: [], requires_approval: false)
          @errors = errors
          @requires_approval = requires_approval
        end

        def safe?
          @errors.empty?
        end

        def requires_approval?
          @requires_approval
        end
      end

      def initialize(registry:)
        @registry = registry
      end

      def validate(plan, initial_keys: nil)
        base_keys = Set.new(initial_keys)
        errors, _result_keys, requires_approval = validate_step_list(plan.steps, base_keys)

        ValidationResult.new(errors: errors, requires_approval: requires_approval)
      end

      private

      # Returns [errors, result_key_set, requires_approval]
      # Does not mutate base_keys — branch isolation is free via immutability.
      def validate_step_list(steps, base_keys)
        errors = []
        requires_approval = false
        current_keys = base_keys

        steps.each do |step|
          case step["type"]
          when "if", "if_else"
            then_steps = step["then"]
            then_result_keys = current_keys
            if then_steps
              then_errors, then_result_keys, then_approval = validate_step_list(then_steps, current_keys)
              errors.concat(then_errors)
              requires_approval ||= then_approval
            end

            else_steps = step["else"]
            else_result_keys = current_keys
            if else_steps
              else_errors, else_result_keys, else_approval = validate_step_list(else_steps, current_keys)
              errors.concat(else_errors)
              requires_approval ||= else_approval
            end

            # Union: keys available after either branch
            current_keys = then_result_keys | else_result_keys
          when "iterate"
            iter_steps = step["steps"]
            if iter_steps
              item_key = (step["as"] || "item").to_sym
              iter_base = current_keys | [item_key]
              iter_errors, iter_result_keys, iter_approval = validate_step_list(iter_steps, iter_base)
              errors.concat(iter_errors)
              requires_approval ||= iter_approval
              current_keys = iter_result_keys
            end
          else
            step_errors, step_new_keys, approval = validate_single_step(step, current_keys)
            errors.concat(step_errors)
            requires_approval ||= approval
            current_keys |= step_new_keys
          end
        end

        [errors, current_keys, requires_approval]
      end

      def validate_single_step(step, available_keys)
        errors = []
        new_keys = []

        id = step["id"]
        if id.nil?
          errors << "Step missing 'id': #{step}"
          return [errors, new_keys]
        end

        cap = begin
          @registry.fetch(id.to_sym)
        rescue KeyError
          errors << "Unknown capability: #{id}"
          return [errors, new_keys]
        end

        missing = cap.expects.reject { |k| available_keys.include?(k) }
        unless missing.empty?
          errors << "Step '#{id}' missing expected keys: #{missing}. Available: #{available_keys.to_a}"
        end

        cap.promises.each { |k| new_keys << k }

        [errors, new_keys, cap.requires_approval]
      end
    end
  end
end
