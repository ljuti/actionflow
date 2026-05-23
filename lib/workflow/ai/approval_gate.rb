# frozen_string_literal: true

module Workflow
  module Ai
    class ApprovalGate
      class Result
        attr_reader :pending_steps, :reason

        def initialize(required:, pending_steps: [], reason: nil)
          @required = required
          @pending_steps = pending_steps
          @reason = reason
        end

        def required?
          @required
        end

        def to_h
          {
            status: @required ? "approval_required" : "approved",
            pending_steps: @pending_steps,
            reason: @reason
          }
        end
      end

      def initialize(registry:)
        @registry = registry
      end

      def check(validation_result, plan)
        return Result.new(required: false) unless validation_result.requires_approval?

        pending = collect_approval_steps(plan.steps)
        reason = build_reason(pending)

        Result.new(required: true, pending_steps: pending, reason: reason)
      end

      private

      def collect_approval_steps(steps, list = [])
        steps.each do |step|
          case step["type"]
          when "if", "if_else"
            collect_approval_steps(step["then"] || [], list)
            collect_approval_steps(step["else"] || [], list) if step["type"] == "if_else"
          when "iterate"
            collect_approval_steps(step["steps"] || [], list)
          else
            id = step["id"]&.to_sym
            next unless id

            cap = begin
              @registry.fetch(id)
            rescue KeyError
              next
            end
            list << id if cap.requires_approval
          end
        end
        list
      end

      def build_reason(pending)
        return nil if pending.empty?

        details = pending.map do |id|
          cap = @registry.fetch(id)
          effects = cap.side_effects.empty? ? "none" : cap.side_effects.join(", ")
          "#{id} (side effects: #{effects})"
        end.join("; ")

        "Plan includes high-risk steps: #{details}"
      end
    end
  end
end
