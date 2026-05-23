# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Steps::ReduceIf do
  it "runs steps when condition is truthy" do
    ran = false
    step = described_class.new(->(ctx) { true }, [->(ctx) {
      ran = true
      ctx
    }])
    step.call(Workflow::Context.new)
    expect(ran).to eq(true)
  end

  it "skips steps when condition is falsy" do
    ran = false
    step = described_class.new(->(ctx) { false }, [->(ctx) {
      ran = true
      ctx
    }])
    step.call(Workflow::Context.new)
    expect(ran).to eq(false)
  end

  it "returns ctx unchanged if stop_processing?" do
    ran = false
    step = described_class.new(->(ctx) { true }, [->(ctx) {
      ran = true
      ctx
    }])
    ctx = Workflow::Context.new
    ctx.fail!
    result = step.call(ctx)
    expect(ran).to eq(false)
    expect(result).to equal(ctx)
  end

  it "resets skip_remaining on exit" do
    step = described_class.new(->(ctx) { true }, [->(ctx) {
      ctx.skip_remaining!
      ctx
    }])
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx).not_to be_skip_remaining
  end

  it "does not reset skip_remaining on failure" do
    step = described_class.new(->(ctx) { true }, [->(ctx) {
      ctx.fail!
      ctx
    }])
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx).to be_failure
  end

  it "does not reset skip_remaining when skip_all_remaining is set" do
    step = described_class.new(->(ctx) { true }, [->(ctx) {
      ctx.skip_all_remaining!
      ctx
    }])
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx).to be_skip_all_remaining
  end
end
