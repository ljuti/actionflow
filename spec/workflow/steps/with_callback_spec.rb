# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Steps::WithCallback do
  it "runs steps and stores callback in context" do
    step = described_class.new(:callback, [->(ctx) {
      ctx[:prepared] = true
      ctx
    }], [])
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx[:prepared]).to eq(true)
    expect(ctx[:callback]).to respond_to(:call)
  end

  it "callback when invoked runs callback steps" do
    step = described_class.new(:callback, [], [->(ctx) {
      ctx[:callback_ran] = true
      ctx
    }])
    ctx = Workflow::Context.new
    step.call(ctx)

    ctx[:callback].call(ctx)
    expect(ctx[:callback_ran]).to eq(true)
  end
end
