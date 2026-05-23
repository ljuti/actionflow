# frozen_string_literal: true

require "actionflow"

RSpec.describe "Integration: hooks" do
  before do
    stub_const("SimpleAction", Class.new do
      include Workflow::Action

      expects :value
      promises :result

      def call(ctx)
        ctx[:result] = ctx[:value] * 2
      end
    end)
  end

  it "before hook receives action and ctx" do
    received_action = nil
    received_ctx = nil

    hook = ->(action, ctx) {
      received_action = action
      received_ctx = ctx
    }

    organizer = Class.new { include Workflow::Organizer }.new
    action = SimpleAction.new

    organizer.with(value: 5)
      .before_each(hook)
      .reduce([action])

    expect(received_action).to equal(action)
    expect(received_ctx[:value]).to eq(5)
  end

  it "after hook receives action and ctx" do
    received_ctx = nil

    hook = ->(_action, ctx) {
      received_ctx = ctx
    }

    organizer = Class.new { include Workflow::Organizer }.new
    action = SimpleAction.new

    organizer.with(value: 5)
      .after_each(hook)
      .reduce([action])

    expect(received_ctx[:result]).to eq(10)
  end

  it "around hook wraps action.call" do
    order = []
    around_hook = ->(_action, _ctx, &blk) {
      order << :before
      result = blk.call
      order << :after
      result
    }

    organizer = Class.new { include Workflow::Organizer }.new
    action = SimpleAction.new

    organizer.with(value: 5)
      .around_each(around_hook)
      .reduce([action])

    expect(order).to eq(%i[before after])
  end

  it "multiple around hooks compose correctly" do
    order = []

    outer = ->(_action, _ctx, &blk) {
      order << :outer_before
      result = blk.call
      order << :outer_after
      result
    }

    inner = ->(_action, _ctx, &blk) {
      order << :inner_before
      result = blk.call
      order << :inner_after
      result
    }

    organizer = Class.new { include Workflow::Organizer }.new
    action = SimpleAction.new

    organizer.with(value: 5)
      .around_each(outer)
      .around_each(inner)
      .reduce([action])

    expect(order).to eq(%i[outer_before inner_before inner_after outer_after])
  end

  it "hooks work with multiple actions in sequence" do
    call_log = []

    before_hook = ->(action, _ctx) {
      call_log << :"before_#{action.class.name}"
    }

    after_hook = ->(action, _ctx) {
      call_log << :"after_#{action.class.name}"
    }

    action1 = SimpleAction.new
    # Use anonymous lambdas as second step
    step2 = ->(ctx) { ctx[:extra] = true; ctx }

    organizer = Class.new { include Workflow::Organizer }.new
    organizer.with(value: 5)
      .before_each(before_hook)
      .after_each(after_hook)
      .reduce([action1, step2])

    # Only the workflow action triggers hooks, not plain lambdas
    expect(call_log).to eq([:before_SimpleAction, :after_SimpleAction])
  end

  it "around hook with fail! inside action still completes" do
    order = []

    around_hook = ->(_action, _ctx, &blk) {
      order << :before
      result = blk.call
      order << :after
      result
    }

    failing_action = Class.new {
      include Workflow::Action
      expects :value
      def call(ctx)
        ctx.fail!("boom")
      end
    }.new

    organizer = Class.new { include Workflow::Organizer }.new
    organizer.with(value: 5)
      .around_each(around_hook)
      .reduce([failing_action])

    expect(order).to eq(%i[before after])
  end

  it "LogDuration-style around hook measures execution" do
    durations = []

    log_hook = ->(_action, _ctx, &blk) {
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = blk.call
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      durations << elapsed
      result
    }

    organizer = Class.new { include Workflow::Organizer }.new
    action = SimpleAction.new

    organizer.with(value: 5)
      .around_each(log_hook)
      .reduce([action])

    expect(durations.length).to eq(1)
    expect(durations.first).to be >= 0
  end

  it "hook sees ctx.current_step set" do
    current_step = nil

    before_hook = ->(_action, ctx) {
      current_step = ctx.current_step
    }

    organizer = Class.new { include Workflow::Organizer }.new
    action = SimpleAction.new

    organizer.with(value: 5)
      .before_each(before_hook)
      .reduce([action])

    expect(current_step).to equal(action)
  end
end
