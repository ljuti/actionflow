# frozen_string_literal: true

module Workflow
  module Steps
    class Iterate < Step
      def initialize(collection_key, steps, item_key: nil)
        @collection_key = collection_key
        @steps = steps
        @item_key = item_key
      end

      private

      def execute(ctx, action_runner:)
        collection = ctx[@collection_key]
        item_key = @item_key || singularize(@collection_key)

        collection.each do |item|
          break if ctx.stop_processing?

          ctx[item_key] = item
          scoped_reduce(ctx, @steps, action_runner: action_runner)
        end
      end

      def singularize(key)
        key.to_s.sub(/s\z/, "")
      end
    end
  end
end
