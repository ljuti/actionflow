# frozen_string_literal: true

module Workflow
  module Steps
    class AddToContext
      def initialize(**pairs)
        @pairs = pairs
      end

      def call(ctx)
        @pairs.each do |key, value|
          ctx[key] = value
        end
        ctx
      end
    end
  end
end
