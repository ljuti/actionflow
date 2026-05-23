# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Steps::Execute do
  it "executes block with ctx" do
    step = described_class.new(->(ctx) {
      ctx[:computed] = ctx[:x] * 2
      ctx
    })
    ctx = Workflow::Context.new(x: 5)
    step.call(ctx)
    expect(ctx[:computed]).to eq(10)
  end

  it "returns ctx" do
    step = described_class.new(->(ctx) { ctx })
    ctx = Workflow::Context.new
    expect(step.call(ctx)).to equal(ctx)
  end

  it "block can modify ctx" do
    step = described_class.new(->(ctx) {
      ctx[:added] = true
      ctx
    })
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx[:added]).to eq(true)
  end
  it "returns ctx even when block returns a different value" do
    step = described_class.new(->(_ctx) { "not ctx" })
    ctx = Workflow::Context.new
    expect(step.call(ctx)).to equal(ctx)
  end
end
