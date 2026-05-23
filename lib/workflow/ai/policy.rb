# frozen_string_literal: true

module Workflow
  module Ai
    class Policy
      def initialize(policy_or_list = nil, &block)
        @policies = case policy_or_list
        when Array
          policy_or_list
        when nil
          block ? [from_block(block)] : []
        else
          [policy_or_list]
        end
      end

      def allowed?(agent:, action:, context:)
        @policies.all? { |p| p.allowed?(agent: agent, action: action, context: context) }
      end

      def self.deny_all
        new(DenyAllPolicy.new)
      end

      def self.allow_all
        new
      end

      private

      def from_block(block)
        BlockPolicy.new(block)
      end

      class BlockPolicy
        def initialize(block)
          @block = block
        end

        def allowed?(**kwargs)
          @block.call(**kwargs)
        end
      end

      class DenyAllPolicy
        def allowed?(**)
          false
        end
      end
    end
  end
end
