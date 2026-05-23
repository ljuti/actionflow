# frozen_string_literal: true

module Workflow
  module Organizer
    def with(data = nil)
      ctx = data.is_a?(Context) ? data : Context.new(data)
      ctx.organized_by = self
      OrganizerSession.new(ctx)
    end

    def reduce(*steps)
      with.reduce(steps)
    end

    def reduce_if(condition, steps)
      Steps::ReduceIf.new(condition, steps)
    end

    def reduce_if_else(condition, if_steps, else_steps)
      Steps::ReduceIfElse.new(condition, if_steps, else_steps)
    end

    def iterate(collection_key, steps, item_key: nil)
      Steps::Iterate.new(collection_key, steps, item_key: item_key)
    end

    def execute(code_block = nil, &block)
      Steps::Execute.new(code_block || block)
    end
  end
end
