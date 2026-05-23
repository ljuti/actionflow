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

  it "passes action_runner to Step subclasses" do
    received_runner = nil
    step = Class.new(Workflow::Step) do
      private

      def execute(ctx, action_runner:)
        ctx[:stepped] = true
      end
    end.new

    # Override call to capture the runner
    step.define_singleton_method(:call) do |ctx, action_runner:|
      received_runner = action_runner
      super(ctx, action_runner: action_runner)
    end

    ctx = reducer.reduce(Workflow::Context.new, [step])
    expect(ctx[:stepped]).to eq(true)
    expect(received_runner).to equal(runner)
  end

  it "passes action_runner through Step to scoped_reduce" do
    hook_log = []
    before_hook = ->(action, ctx) { hook_log << action.class.name }

    hooked_runner = Workflow::ActionRunner.new(before_hooks: [before_hook])
    hooked_reducer = described_class.new(action_runner: hooked_runner)

    stub_const("NestedAction", Class.new do
      include Workflow::Action

      promises :done

      def call(ctx)
        ctx[:done] = true
      end
    end)

    step = Workflow::Steps::ReduceIf.new(->(ctx) { true }, [NestedAction.new])

    ctx = hooked_reducer.reduce(Workflow::Context.new, [step])
    expect(ctx[:done]).to eq(true)
    expect(hook_log).to eq(["NestedAction"])
  end

  describe "rollback" do
    # Lightweight step double that responds to :call and :rollback
    def rollback_step(name, on_call: nil, on_rollback: nil)
      step = Object.new
      step.define_singleton_method(:call) do |ctx|
        on_call&.call(ctx)
        ctx
      end
      step.define_singleton_method(:rollback) { |ctx| on_rollback&.call(ctx) }
      step
    end

    it "calls rollback on executed steps when FailWithRollback is raised" do
      rolled_back = []

      s1 = rollback_step("s1", on_rollback: ->(ctx) { rolled_back << :s1 })
      s2 = Object.new
      s2.define_singleton_method(:call) { |ctx| ctx.fail_with_rollback!("boom") }
      s2.define_singleton_method(:rollback) { |ctx| rolled_back << :s2 }

      reducer.reduce(Workflow::Context.new, [s1, s2])
      expect(rolled_back).to eq([:s2, :s1])
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

    it "only rolls back executed steps" do
      rolled_back = []

      s1 = rollback_step("s1",
        on_call: ->(ctx) { ctx[:step1] = true },
        on_rollback: ->(ctx) { rolled_back << :s1 })
      s2 = Object.new
      s2.define_singleton_method(:call) { |ctx| ctx.fail_with_rollback!("boom") }
      s2.define_singleton_method(:rollback) { |ctx| rolled_back << :s2 }
      s3 = ->(ctx) {
        ctx[:step3] = true
        ctx
      }

      reducer.reduce(Workflow::Context.new, [s1, s2, s3])
      expect(rolled_back).to eq([:s2, :s1])
    end

    # Kill: executed_steps.reverse → executed_steps
    it "rolls back steps in reverse execution order" do
      rolled_back_steps = []

      s1 = rollback_step("s1",
        on_call: ->(ctx) { ctx[:a] = 1 },
        on_rollback: ->(ctx) { rolled_back_steps << :s1 })
      s2 = rollback_step("s2",
        on_call: ->(ctx) { ctx[:b] = 2 },
        on_rollback: ->(ctx) { rolled_back_steps << :s2 })
      s3 = Object.new
      s3.define_singleton_method(:call) { |ctx| ctx.fail_with_rollback!("boom") }
      s3.define_singleton_method(:rollback) { |ctx| rolled_back_steps << :s3 }

      reducer.reduce(Workflow::Context.new, [s1, s2, s3])
      expect(rolled_back_steps).to eq([:s3, :s2, :s1])
    end

    # Kill: remove rescue FailWithRollback
    it "catches FailWithRollback without propagating" do
      step = ->(ctx) { ctx.fail_with_rollback!("boom") }
      expect {
        reducer.reduce(Workflow::Context.new, [step])
      }.not_to raise_error
    end

    it "skips steps without rollback method" do
      rolled_back = []

      s1 = ->(ctx) { ctx }
      s2 = Object.new
      s2.define_singleton_method(:call) { |ctx| ctx.fail_with_rollback!("boom") }
      s2.define_singleton_method(:rollback) { |ctx| rolled_back << :s2 }

      reducer.reduce(Workflow::Context.new, [s1, s2])
      expect(rolled_back).to eq([:s2])
    end

    it "passes the original context to rollback" do
      received_ctx = nil

      s1 = Object.new
      s1.define_singleton_method(:call) do |ctx|
        ctx[:marker] = true
        ctx
      end
      s1.define_singleton_method(:rollback) { |ctx| received_ctx = ctx }

      s2 = Object.new
      s2.define_singleton_method(:call) { |ctx| ctx.fail_with_rollback!("boom") }

      input = Workflow::Context.new
      reducer.reduce(input, [s1, s2])

      expect(received_ctx).to equal(input)
      expect(received_ctx[:marker]).to eq(true)
    end

    it "breaks immediately after rollback, not on next iteration" do
      invocations_after_rollback = 0

      s1 = Object.new
      s1.define_singleton_method(:call) { |ctx| ctx.fail_with_rollback!("boom") }

      s2 = ->(ctx) {
        invocations_after_rollback += 1
        ctx
      }

      reducer.reduce(Workflow::Context.new, [s1, s2])
      expect(invocations_after_rollback).to eq(0)
    end
  end
end
