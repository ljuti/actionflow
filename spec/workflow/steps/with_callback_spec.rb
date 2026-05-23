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

  it "returns ctx" do
    step = described_class.new(:callback, [->(ctx) { ctx }], [])
    ctx = Workflow::Context.new
    expect(step.call(ctx)).to equal(ctx)
  end

  it "returns ctx when stop_processing?" do
    step = described_class.new(:callback, [->(ctx) {
      ctx[:ran] = true
      ctx
    }], [])
    ctx = Workflow::Context.new
    ctx.fail!
    result = step.call(ctx)
    expect(result).to equal(ctx)
    expect(ctx[:ran]).to be_nil
  end

  it "does not set callback when stop_processing?" do
    step = described_class.new(:callback, [->(ctx) { ctx }], [->(ctx) { ctx }])
    ctx = Workflow::Context.new
    ctx.fail!
    step.call(ctx)
    expect(ctx[:callback]).to be_nil
  end

  it "resets skip_remaining on scope exit" do
    step = described_class.new(:callback, [->(ctx) {
      ctx.skip_remaining!
      ctx
    }], [])
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx).not_to be_skip_remaining
  end

  it "does not reset skip_remaining on failure" do
    step = described_class.new(:callback, [->(ctx) {
      ctx.skip_remaining!
      ctx.fail!("callback error")
      ctx
    }], [])
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx).to be_failure
    expect(ctx).to be_skip_remaining
  end

  it "preserves failure message when skip_remaining is not reset" do
    step = described_class.new(:callback, [->(ctx) {
      ctx.skip_remaining!
      ctx.fail!("callback error")
      ctx
    }], [])
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx.message).to eq("callback error")
  end

  it "does not reset skip_remaining when skip_all_remaining is set" do
    step = described_class.new(:callback, [->(ctx) {
      ctx.skip_remaining!
      ctx.skip_all_remaining!
      ctx
    }], [])
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx).to be_skip_all_remaining
    expect(ctx).to be_skip_remaining
  end

  it "callback returns ctx" do
    step = described_class.new(:callback, [], [->(ctx) { ctx }])
    ctx = Workflow::Context.new
    step.call(ctx)
    result = ctx[:callback].call(ctx)
    expect(result).to equal(ctx)
  end

  it "callback resets skip_remaining on scope exit" do
    step = described_class.new(:callback, [], [->(ctx) {
      ctx.skip_remaining!
      ctx
    }])
    ctx = Workflow::Context.new
    step.call(ctx)
    ctx[:callback].call(ctx)
    expect(ctx).not_to be_skip_remaining
  end

  it "callback does not reset skip_remaining on failure" do
    step = described_class.new(:callback, [], [->(ctx) {
      ctx.skip_remaining!
      ctx.fail!("inner error")
      ctx
    }])
    ctx = Workflow::Context.new
    step.call(ctx)
    ctx[:callback].call(ctx)
    expect(ctx).to be_failure
    expect(ctx).to be_skip_remaining
  end

  it "callback preserves failure message when skip_remaining is not reset" do
    step = described_class.new(:callback, [], [->(ctx) {
      ctx.skip_remaining!
      ctx.fail!("inner error")
      ctx
    }])
    ctx = Workflow::Context.new
    step.call(ctx)
    ctx[:callback].call(ctx)
    expect(ctx.message).to eq("inner error")
  end

  it "callback does not reset skip_remaining when skip_all_remaining is set" do
    step = described_class.new(:callback, [], [->(ctx) {
      ctx.skip_remaining!
      ctx.skip_all_remaining!
      ctx
    }])
    ctx = Workflow::Context.new
    step.call(ctx)
    ctx[:callback].call(ctx)
    expect(ctx).to be_skip_all_remaining
    expect(ctx).to be_skip_remaining
  end

  it "callback returns the callback context" do
    step = described_class.new(:cb, [], [->(ctx) { ctx }])
    ctx = Workflow::Context.new
    step.call(ctx)
    callback_ctx = Workflow::Context.new
    result = ctx[:cb].call(callback_ctx)
    expect(result).to equal(callback_ctx)
  end
end
