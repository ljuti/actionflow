# frozen_string_literal: true

module Workflow
  module Action
    RESERVED_KEYS = %i[message error_code current_step organized_by].freeze

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def expects(*keys, **options)
        if options.key?(:default)
          key = keys.fetch(0).to_sym
          validate_reserved!(key, "expects")
          workflow_metadata.expected_keys << key
          workflow_metadata.defaults[key] = options[:default]
        else
          keys.map(&:to_sym).each { |k| validate_reserved!(k, "expects") }
          workflow_metadata.expected_keys.concat(keys.map(&:to_sym))
        end
      end

      def promises(*keys)
        keys.map(&:to_sym).each { |k| validate_reserved!(k, "promises") }
        workflow_metadata.promised_keys.concat(keys.map(&:to_sym))
      end

      def workflow_metadata
        @workflow_metadata ||= ActionMetadata.new
      end

      private

      def validate_reserved!(key, dsl_method)
        return unless RESERVED_KEYS.include?(key)

        raise ArgumentError, "reserved key :#{key} cannot be used in #{dsl_method}"
      end
    end

    def workflow_metadata
      self.class.workflow_metadata
    end

    def execute(ctx = Context.new)
      ActionRunner.default.call(self, ctx)
    end
  end
end
