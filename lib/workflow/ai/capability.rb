# frozen_string_literal: true

module Workflow
  module Ai
    class Capability
      attr_reader :id, :action, :description, :expects, :promises,
                  :side_effects, :risk, :requires_approval, :rollback_available

      def initialize(id, action:, description:, expects:, promises:,
                     side_effects: [], risk: :low, requires_approval: false,
                     rollback_available: false)
        @id = id
        @action = action
        @description = description
        @expects = expects
        @promises = promises
        @side_effects = side_effects
        @risk = risk
        @requires_approval = requires_approval
        @rollback_available = rollback_available
      end

      def to_description
        {
          id: @id,
          description: @description,
          expects: @expects,
          promises: @promises,
          side_effects: @side_effects,
          risk: @risk,
          requires_approval: @requires_approval,
          rollback_available: @rollback_available
        }
      end
    end
  end
end
