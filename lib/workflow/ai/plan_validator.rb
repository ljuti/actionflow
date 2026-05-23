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
        errors = []
        available_keys = Set.new(initial_keys)
        requires_approval = false

        plan.steps.each do |step|
          case step["type"]
          when "if", "if_else"
            # Validate both branches with current key set
            if step["then"]
              branch_errors = validate_steps(step.fetch("then"), available_keys.dup)
              errors.concat(branch_errors)
            end
            if step["else"]
              branch_errors = validate_steps(step.fetch("else"), available_keys.dup)
              errors.concat(branch_errors)
            end
            # For linear flow, take the union of promised keys from both branches
            (step["then"] || []).each { |s| track_step_keys(s, available_keys) }
          when "iterate"
            if step.key?("steps")
              item_key = (step["as"] || "item").to_sym
              available_keys << item_key
              step_errors = validate_steps(step.fetch("steps"), available_keys)
              errors.concat(step_errors)
            end
          else
            # Linear step
            step_errors, new_keys, approval = validate_single_step(step, available_keys)
            errors.concat(step_errors)
            requires_approval ||= approval
            new_keys.each { |k| available_keys << k }
          end
        end

        ValidationResult.new(errors: errors, requires_approval: requires_approval)
      end

      private

      def validate_steps(steps, available_keys)
        errors = []

        steps.each do |step|
          step_errors, step_new_keys, _ = validate_single_step(step, available_keys)
          errors.concat(step_errors)
          step_new_keys.each { |k| available_keys << k }
        end

        errors
      end

      def validate_single_step(step, available_keys)
        errors = []
        new_keys = []
        approval = false

        id = step["id"]
        if id.nil?
          errors << "Step missing 'id': #{step}"
          return [errors, new_keys]
        end

        begin
          cap = @registry.fetch(id.to_sym)
        rescue KeyError
          errors << "Unknown capability: #{id}"
          return [errors, new_keys]
        end

        missing = cap.expects.reject { |k| available_keys.include?(k) }
        unless missing.empty?
          errors << "Step '#{id}' missing expected keys: #{missing}. Available: #{available_keys.to_a}"
        end

        cap.promises.each { |k| new_keys << k }

        if cap.requires_approval
          approval = true
        end

        [errors, new_keys, approval]
      end

      def track_step_keys(step, available_keys)
        id = step["id"]
        return unless id

        begin
          cap = @registry.fetch(id.to_sym)
          cap.promises.each { |k| available_keys << k }
        rescue KeyError
          # Ignore — will be caught by main validation
        end
      end
    end
  end
end
