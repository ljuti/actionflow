# frozen_string_literal: true

module Workflow
  module Localization
    class NullAdapter
      def failure(message, _action, _options)
        message
      end
    end

    class HashAdapter
      def initialize(catalog = {})
        @catalog = catalog
      end

      def failure(message, _action, _options)
        return nil if message.nil?

        @catalog.fetch(message, message)
      end
    end
  end
end
