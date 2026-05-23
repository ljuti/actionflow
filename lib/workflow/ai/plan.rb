# frozen_string_literal: true

module Workflow
  module Ai
    class Plan
      attr_reader :name, :input, :steps

      def initialize(raw)
        raise ArgumentError, "Plan must be a Hash" unless raw.is_a?(Hash)
        raise ArgumentError, "Plan must have steps" unless raw.key?("steps")

        @name = raw["name"]
        @input = raw["input"] || {}
        @steps = raw.fetch("steps")
      end
    end
  end
end
