# frozen_string_literal: true

module Workflow
  module Ai
    class AuditTrail
      attr_reader :agent_id, :user_id

      def initialize(agent_id:, user_id:)
        @agent_id = agent_id
        @user_id = user_id
        @executed_steps = []
        @skipped_steps = []
        @failures = []
        @approvals = []
        @started_at = Time.now
      end

      def record_step(step_id, status)
        case status
        when :executed
          @executed_steps << step_id
        when :skipped
          @skipped_steps << step_id
        when :failed
          @failures << step_id
        end
      end

      def record_approval(step_id, approved_by:)
        @approvals << {step: step_id, approved_by: approved_by}
      end

      def finalize(plan:, validation:, result:)
        {
          agent_id: @agent_id,
          user_id: @user_id,
          plan: plan,
          validation_result: validation,
          result: result,
          executed_steps: @executed_steps.dup,
          skipped_steps: @skipped_steps.dup,
          failures: @failures.dup,
          approvals: @approvals.dup,
          started_at: @started_at,
          finished_at: Time.now
        }
      end
    end
  end
end
