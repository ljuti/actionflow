# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Steps::ReduceWhile do
  it "runs steps while condition is true" do
    step = described_class.new(
      ->(ctx) { ctx[:count] < 3 },
      [->(ctx) {
        ctx[:count] = (ctx[:count] || 0) + 1
        ctx
      }]
    )
    ctx = Workflow::Context.new(count: 0)
    step.call(ctx)
    expect(ctx[:count]).to eq(3)
  end

  it "stops when condition becomes false" do
    step = described_class.new(
      ->(ctx) { false },
      [->(ctx) {
        ctx[:ran] = true
        ctx
      }]
    )
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx[:ran]).to be_nil
  end

  it "returns ctx unchanged if stop_processing?" do
    ran = false
    step = described_class.new(
      ->(ctx) { true },
      [->(ctx) {
        ran = true
        ctx
      }]
    )
    ctx = Workflow::Context.new
    ctx.fail!
    step.call(ctx)
    expect(ran).to eq(false)
  end
end
