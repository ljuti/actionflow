# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Steps::ReduceIfElse do
  it "runs if-steps when condition is truthy" do
    if_ran = false
    else_ran = false
    step = described_class.new(
      ->(ctx) { true },
      [->(ctx) {
        if_ran = true
        ctx
      }],
      [->(ctx) {
        else_ran = true
        ctx
      }]
    )
    step.call(Workflow::Context.new)
    expect(if_ran).to eq(true)
    expect(else_ran).to eq(false)
  end

  it "runs else-steps when condition is falsy" do
    if_ran = false
    else_ran = false
    step = described_class.new(
      ->(ctx) { false },
      [->(ctx) {
        if_ran = true
        ctx
      }],
      [->(ctx) {
        else_ran = true
        ctx
      }]
    )
    step.call(Workflow::Context.new)
    expect(if_ran).to eq(false)
    expect(else_ran).to eq(true)
  end

  it "returns ctx unchanged if stop_processing?" do
    if_ran = false
    step = described_class.new(
      ->(ctx) { true },
      [->(ctx) {
        if_ran = true
        ctx
      }],
      []
    )
    ctx = Workflow::Context.new
    ctx.fail!
    result = step.call(ctx)
    expect(if_ran).to eq(false)
    expect(result).to equal(ctx)
  end

  it "returns ctx when condition is true" do
    step = described_class.new(->(ctx) { true }, [->(ctx) { ctx }], [])
    ctx = Workflow::Context.new
    expect(step.call(ctx)).to equal(ctx)
  end

  it "returns ctx when condition is false" do
    step = described_class.new(->(ctx) { false }, [], [->(ctx) { ctx }])
    ctx = Workflow::Context.new
    expect(step.call(ctx)).to equal(ctx)
  end

  it "resets skip_remaining on scope exit in if-branch" do
    step = described_class.new(
      ->(ctx) { true },
      [->(ctx) {
        ctx.skip_remaining!
        ctx
      }],
      []
    )
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx).not_to be_skip_remaining
  end

  it "resets skip_remaining on scope exit in else-branch" do
    step = described_class.new(
      ->(ctx) { false },
      [],
      [->(ctx) {
        ctx.skip_remaining!
        ctx
      }]
    )
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx).not_to be_skip_remaining
  end

  it "does not reset skip_remaining on failure in if-branch" do
    step = described_class.new(
      ->(ctx) { true },
      [->(ctx) {
        ctx.skip_remaining!
        ctx.fail!("error")
        ctx
      }],
      []
    )
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx).to be_failure
    expect(ctx).to be_skip_remaining
  end

  it "does not reset skip_remaining on failure in else-branch" do
    step = described_class.new(
      ->(ctx) { false },
      [],
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
        ctx.fail!("bad thing")
        ctx
      }],
      []
    )
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx.message).to eq("bad thing")
  end

  it "does not reset skip_remaining when skip_all_remaining is set" do
    step = described_class.new(
      ->(ctx) { true },
      [->(ctx) {
        ctx.skip_remaining!
        ctx.skip_all_remaining!
        ctx
      }],
      []
    )
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx).to be_skip_all_remaining
    expect(ctx).to be_skip_remaining
  end

  it "condition receives the context" do
    step = described_class.new(
      ->(ctx) { ctx[:x] > 0 },
      [->(ctx) {
        ctx[:ran] = true
        ctx
      }],
      []
    )
    ctx = Workflow::Context.new(x: 5)
    step.call(ctx)
    expect(ctx[:ran]).to eq(true)
  end
  it "does not evaluate condition when ctx is already stopped" do
    condition_called = false
    step = described_class.new(
      ->(_ctx) { condition_called = true },
      [->(ctx) { ctx }],
      [->(ctx) { ctx }]
    )
    ctx = Workflow::Context.new
    ctx.fail!
    step.call(ctx)
    expect(condition_called).to eq(false)
  end


  it "runs action steps through ActionRunner" do
    action = Class.new do
      include Workflow::Action
      promises :done
      def call(ctx)
        ctx[:done] = true
      end
    end.new
    step = described_class.new(->(_ctx) { true }, [action], [])
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx[:done]).to eq(true)
  end
end
