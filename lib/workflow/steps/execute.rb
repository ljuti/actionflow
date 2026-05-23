# frozen_string_literal: true

module Workflow
  module Steps
    class Execute
      def initialize(block)
        @block = block
      end

      def call(ctx)
        @block.call(ctx)
        ctx
      end
    end
  end
end
