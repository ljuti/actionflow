# frozen_string_literal: true

module Workflow
  module Testing
    module RSpecMatchers
      def expect_keys(*keys)
        ExpectKeysMatcher.new(keys)
      end

      def promise_keys(*keys)
        PromiseKeysMatcher.new(keys)
      end

      def have_context_value(key)
        HaveContextValueMatcher.new(key)
      end
    end

    class ContractMatcher
      def initialize(expected, label, key_accessor)
        @expected = expected
        @label = label
        @key_accessor = key_accessor
      end

      def matches?(actual)
        metadata = extract_metadata(actual)
        actual_keys = metadata.send(@key_accessor)
        @missing = @expected - actual_keys
        @extra = actual_keys - @expected
        @missing.empty? && @extra.empty?
      end

      def failure_message
        msg = "expected action to #{@label} #{@expected.inspect}"
        msg += "\n  missing: #{@missing.inspect}" unless @missing.empty?
        msg += "\n  extra: #{@extra.inspect}" unless @extra.empty?
        msg
      end

      def description
        "#{@label} #{@expected.inspect}"
      end

      private

      def extract_metadata(actual)
        if actual.respond_to?(:workflow_metadata)
          actual.workflow_metadata
        elsif actual.is_a?(Class) && actual.respond_to?(:workflow_metadata)
          actual.workflow_metadata
        else
          raise ArgumentError, "expected an action, got #{actual.inspect}"
        end
      end
    end

    class ExpectKeysMatcher < ContractMatcher
      def initialize(expected)
        super(expected, "expect keys", :expected_keys)
      end
    end

    class PromiseKeysMatcher < ContractMatcher
      def initialize(expected)
        super(expected, "promise keys", :promised_keys)
      end
    end

    class HaveContextValueMatcher
      def initialize(expected_key)
        @expected_key = expected_key
      end

      def matches?(actual)
        @actual = actual
        actual.key?(@expected_key)
      end

      def failure_message
        "expected context to have key :#{@expected_key}, got keys: #{@actual.keys.inspect}"
      end

      def description
        "have context value :#{@expected_key}"
      end
    end
  end
end
