# frozen_string_literal: true

module Workflow
  module Ai
    class CapabilityRegistry
      def initialize
        @capabilities = {}
      end

      def register(capability)
        @capabilities[capability.id] = capability
      end

      def fetch(id)
        @capabilities.fetch(id)
      end

      def descriptions
        @capabilities.values.map(&:to_description)
      end
    end
  end
end
