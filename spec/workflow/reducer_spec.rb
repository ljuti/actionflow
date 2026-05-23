# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Reducer do
  let(:runner) { Workflow::ActionRunner.new }
  let(:reducer) { described_class.new(action_runner: runner) }

  def make_action(expected: [], promised: [], &body)
    action = double("action")
    metadata = Workflow::ActionMetadata.new(
      expected_keys: expected,
      promised_keys: promised
    )
    allow(action).to receive(:workflow_metadata).and_return(metadata)
    allow(action).to receive(:call) { |ctx| body&.call(ctx) || ctx }
    action
  end

  it "executes steps in order" do
    order = []
    s1 = ->(ctx) {
      order << 1
      ctx
    }
    s2 = ->(ctx) {
      order << 2
      ctx
    }

    ctx = reducer.reduce(Workflow::Context.new, [s1, s2])
    expect(order).to eq([1, 2])
    expect(ctx).to be_success
  end

  it "returns ctx" do
    ctx = Workflow::Context.new
    expect(reducer.reduce(ctx, [])).to equal(ctx)
  end

  it "breaks on ctx.stop_processing?" do
    order = []
    s1 = ->(ctx) {
      order << 1
      ctx.fail!
      ctx
    }
    s2 = ->(ctx) {
      order << 2
      ctx
    }

    reducer.reduce(Workflow::Context.new, [s1, s2])
    expect(order).to eq([1])
  end

  it "dispatches workflow actions through ActionRunner" do
    action = make_action { |ctx| ctx[:ran] = true }
    ctx = reducer.reduce(Workflow::Context.new, [action])
    expect(ctx[:ran]).to eq(true)
  end

  it "calls plain callables directly" do
    called = false
    step = ->(ctx) {
      called = true
      ctx
    }
    reducer.reduce(Workflow::Context.new, [step])
    expect(called).to eq(true)
  end

  # Kill: workflow_action? → false/nil — ActionRunner validates expected keys
  it "routes workflow actions through ActionRunner for key validation" do
    action = make_action(expected: [:missing_key]) { |ctx| ctx }
    expect {
      reducer.reduce(Workflow::Context.new, [action])
    }.to raise_error(Workflow::ExpectedKeysMissing)
  end

  # Kill: Array(steps) → [steps] — Array(nil) → [] but [nil] → [nil].call raises
  it "handles nil steps gracefully" do
    ctx = Workflow::Context.new
    expect(reducer.reduce(ctx, nil)).to equal(ctx)
  end

  # Kill: Array(steps) — exercise with bare non-array step
  it "accepts a single step without array wrapping" do
    called = false
    reducer.reduce(Workflow::Context.new, ->(ctx) {
      called = true
      ctx
    })
    expect(called).to eq(true)
  end

  it "flattens nested step arrays" do
    order = []
    s1 = ->(ctx) {
      order << 1
      ctx
    }
    s2 = ->(ctx) {
      order << 2
      ctx
    }

    reducer.reduce(Workflow::Context.new, [[s1], [s2]])
    expect(order).to eq([1, 2])
  end

  it "handles empty steps" do
    ctx = Workflow::Context.new
    expect(reducer.reduce(ctx, [])).to equal(ctx)
  end

  describe "rollback" do
    it "triggers rollback on FailWithRollback with correct context" do
      rollback_spy = instance_spy(Workflow::RollbackStrategy)
      allow(rollback_spy).to receive(:rollback) { |ctx, _steps| ctx }

      r = described_class.new(action_runner: runner, rollback_strategy: rollback_spy)
      step = ->(ctx) { ctx.fail_with_rollback!("boom") }
      input_ctx = Workflow::Context.new

      r.reduce(input_ctx, [step])

      expect(rollback_spy).to have_received(:rollback).with(input_ctx, any_args)
    end

    it "stops executing after rollback" do
      order = []
      s1 = ->(ctx) {
        order << 1
        ctx.fail_with_rollback!("boom")
      }
      s2 = ->(ctx) {
        order << 2
        ctx
      }

      reducer.reduce(Workflow::Context.new, [s1, s2])
      expect(order).to eq([1])
    end

    # Kill: break after rollback → nil — steps after rollback must not execute
    it "does not execute steps after rollback via break" do
      order = []
      s1 = ->(ctx) { ctx.fail_with_rollback!("boom") }
      s2 = ->(ctx) {
        order << 2
        ctx
      }
      reducer.reduce(Workflow::Context.new, [s1, s2])
      expect(order).to eq([])
    end

    it "only rolled-back steps are passed to strategy" do
      rolled_back = nil

      custom_strategy = instance_double(Workflow::RollbackStrategy)
      allow(custom_strategy).to receive(:rollback) { |ctx, steps|
        rolled_back = steps
      }

      r = described_class.new(action_runner: runner, rollback_strategy: custom_strategy)
      s1 = ->(ctx) {
        ctx[:step1] = true
        ctx
      }
      s2 = ->(ctx) { ctx.fail_with_rollback!("boom") }
      s3 = ->(ctx) {
        ctx[:step3] = true
        ctx
      }

      r.reduce(Workflow::Context.new, [s1, s2, s3])
      expect(rolled_back.length).to eq(2)
    end

    # Kill: executed_steps.reverse → executed_steps
    it "passes steps to rollback in reverse execution order" do
      rolled_back_steps = nil
      custom_strategy = instance_double(Workflow::RollbackStrategy)
      allow(custom_strategy).to receive(:rollback) { |ctx, steps|
        rolled_back_steps = steps
        ctx
      }

      r = described_class.new(action_runner: runner, rollback_strategy: custom_strategy)
      s1 = ->(ctx) {
        ctx[:a] = 1
        ctx
      }
      s2 = ->(ctx) {
        ctx[:b] = 2
        ctx
      }
      s3 = ->(ctx) { ctx.fail_with_rollback!("boom") }

      r.reduce(Workflow::Context.new, [s1, s2, s3])
      expect(rolled_back_steps).to eq([s3, s2, s1])
    end

    # Kill: remove rescue FailWithRollback
    it "catches FailWithRollback without propagating" do
      step = ->(ctx) { ctx.fail_with_rollback!("boom") }
      expect {
        reducer.reduce(Workflow::Context.new, [step])
      }.not_to raise_error
    end
  end
end
