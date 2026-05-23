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
    it "triggers rollback on FailWithRollback" do
      rollback_spy = instance_spy(Workflow::RollbackStrategy)
      allow(rollback_spy).to receive(:rollback)

      r = described_class.new(action_runner: runner, rollback_strategy: rollback_spy)
      step = ->(ctx) { ctx.fail_with_rollback!("boom") }

      r.reduce(Workflow::Context.new, [step])

      expect(rollback_spy).to have_received(:rollback)
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

    it "only rolled-back steps are passed to strategy" do
      rolled_back = nil

      custom_strategy = instance_double(Workflow::RollbackStrategy)
      allow(custom_strategy).to receive(:rollback) { |ctx, steps|
        rolled_back = steps
        ctx
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
  end
end
