# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Ai::DynamicOrganizer do
  it "executes compiled steps" do
    organizer = described_class.new(steps: [
      ->(ctx) {
        ctx[:step1] = true
        ctx
      },
      ->(ctx) {
        ctx[:step2] = true
        ctx
      }
    ])

    result = organizer.call(x: 1)
    expect(result[:step1]).to eq(true)
    expect(result[:step2]).to eq(true)
  end

  it "applies hooks" do
    hook_called = false
    hook = ->(_action, _ctx) { hook_called = true }

    action = Class.new {
      include Workflow::Action

      expects :x
      def call(ctx)
      end
    }.new

    organizer = described_class.new(
      steps: [action],
      before_hooks: [hook]
    )

    organizer.call(x: 1)
    expect(hook_called).to eq(true)
  end

  it "returns context" do
    organizer = described_class.new(steps: [])
    result = organizer.call
    expect(result).to be_a(Workflow::Context)
    expect(result).to be_success
  end

  it "can be called without arguments" do
    organizer = described_class.new(steps: [])
    result = organizer.call
    expect(result).to be_a(Workflow::Context)
    expect(result).to be_success
  end

  it "applies after_hooks" do
    after_hook_called = false
    after_hook = ->(_action, _ctx) { after_hook_called = true }

    action = Class.new {
      include Workflow::Action

      expects :x
      def call(ctx)
      end
    }.new

    organizer = described_class.new(
      steps: [action],
      after_hooks: [after_hook]
    )

    organizer.call(x: 1)
    expect(after_hook_called).to eq(true)
  end

  it "applies around_hooks" do
    around_hook_called = false
    around_hook = lambda { |_action, _ctx, &blk|
      around_hook_called = true
      blk.call
    }

    action = Class.new {
      include Workflow::Action

      expects :x
      def call(ctx)
      end
    }.new

    organizer = described_class.new(
      steps: [action],
      around_hooks: [around_hook]
    )

    organizer.call(x: 1)
    expect(around_hook_called).to eq(true)
  end

  it "runs all steps in order" do
    order = []
    organizer = described_class.new(steps: [
      ->(ctx) { order << 1; ctx },
      ->(ctx) { order << 2; ctx },
      ->(ctx) { order << 3; ctx }
    ])

    organizer.call
    expect(order).to eq([1, 2, 3])
  end

  it "passes input to the session" do
    organizer = described_class.new(steps: [
      ->(ctx) { ctx }
    ])

    result = organizer.call(key: "value")
    expect(result[:key]).to eq("value")
  end
end
