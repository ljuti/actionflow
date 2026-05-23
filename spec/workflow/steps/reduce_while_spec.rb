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
    result = step.call(ctx)
    expect(ran).to eq(false)
    expect(result).to equal(ctx)
  end

  it "returns ctx" do
    step = described_class.new(
      ->(ctx) { ctx[:count] < 1 },
      [->(ctx) {
        ctx[:count] = (ctx[:count] || 0) + 1
        ctx
      }]
    )
    ctx = Workflow::Context.new(count: 0)
    expect(step.call(ctx)).to equal(ctx)
  end

  it "breaks loop when stop_processing? becomes true mid-loop" do
    count = 0
    step = described_class.new(
      ->(ctx) { true },
      [->(ctx) {
        count += 1
        ctx.fail! if count >= 2
        ctx
      }]
    )
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(count).to eq(2)
  end

  it "resets skip_remaining on scope exit" do
    iterations = 0
    step = described_class.new(
      ->(ctx) { iterations < 1 },
      [->(ctx) {
        iterations += 1
        ctx.skip_remaining!
        ctx
      }]
    )
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx).not_to be_skip_remaining
  end

  it "does not reset skip_remaining on failure" do
    step = described_class.new(
      ->(ctx) { true },
      [->(ctx) {
        ctx.skip_remaining!
        ctx.fail!("error")
        ctx
      }]
    )
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx).to be_failure
    expect(ctx).to be_skip_remaining
  end

  it "preserves failure message when skip_remaining is not reset" do
    step = described_class.new(
      ->(ctx) { true },
      [->(ctx) {
        ctx.skip_remaining!
        ctx.fail!("loop error")
        ctx
      }]
    )
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx.message).to eq("loop error")
  end

  it "does not reset skip_remaining when skip_all_remaining is set" do
    step = described_class.new(
      ->(ctx) { true },
      [->(ctx) {
        ctx.skip_remaining!
        ctx.skip_all_remaining!
        ctx
      }]
    )
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx).to be_skip_all_remaining
    expect(ctx).to be_skip_remaining
  end
end
