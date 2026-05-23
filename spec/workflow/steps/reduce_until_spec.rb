# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Steps::ReduceUntil do
  it "runs steps until condition is true" do
    step = described_class.new(
      ->(ctx) { (ctx[:count] || 0) >= 3 },
      [->(ctx) {
        ctx[:count] = (ctx[:count] || 0) + 1
        ctx
      }]
    )
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx[:count]).to eq(3)
  end

  it "does not run steps if condition is already true" do
    step = described_class.new(
      ->(ctx) { true },
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
      ->(ctx) { false },
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
