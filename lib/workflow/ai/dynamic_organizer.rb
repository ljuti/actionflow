# frozen_string_literal: true

module Workflow
  module Ai
    class DynamicOrganizer
      include Workflow::Organizer

      def initialize(steps:, before_hooks: [], after_hooks: [], around_hooks: [])
        @steps = steps
        @before_hooks = before_hooks
        @after_hooks = after_hooks
        @around_hooks = around_hooks
      end

      def call(input = {})
        session = with(input)

        @before_hooks.each { |hook| session.before_each(hook) }
        @after_hooks.each { |hook| session.after_each(hook) }
        @around_hooks.each { |hook| session.around_each(hook) }

        session.reduce(@steps)
      end
    end
  end
end
