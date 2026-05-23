# frozen_string_literal: true

module Workflow
  module Steps
    class AddAliases
      def initialize(aliases)
        @aliases = aliases
      end

      def call(ctx)
        ctx.assign_aliases(@aliases)
        ctx
      end
    end
  end
end
