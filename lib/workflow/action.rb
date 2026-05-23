# frozen_string_literal: true

module Workflow
  module Action
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def expects(*keys, **options)
        if options.key?(:default)
          key = keys.fetch(0).to_sym
          workflow_metadata.expected_keys << key
          workflow_metadata.defaults[key] = options[:default]
        else
          workflow_metadata.expected_keys.concat(keys.map(&:to_sym))
        end
      end

      def promises(*keys)
        workflow_metadata.promised_keys.concat(keys.map(&:to_sym))
      end

      def workflow_metadata
        @workflow_metadata ||= ActionMetadata.new
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
