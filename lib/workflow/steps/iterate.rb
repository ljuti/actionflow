# frozen_string_literal: true

module Workflow
  module Steps
    class Iterate
      def initialize(collection_key, steps, item_key: nil)
        @collection_key = collection_key
        @steps = steps
        @item_key = item_key
      end

      def call(ctx)
        collection = ctx[@collection_key]
        item_key = @item_key || singularize(@collection_key)

        collection.each do |item|
          break if ctx.stop_processing?

          ctx[item_key] = item
          scoped_reduce(ctx, @steps)
        end

        ctx
      end

      private

      def singularize(key)
        key.to_s.sub(/s\z/, "").to_sym
      end

      def scoped_reduce(ctx, steps)
        runner = ActionRunner.default
        reducer = Reducer.new(action_runner: runner)
        reducer.reduce(ctx, steps)
      end
    end
  end
end
