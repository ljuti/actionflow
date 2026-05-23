# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::ActionRunner do
  let(:runner) { described_class.new }

  def make_action(expected: [], promised: [], defaults: {}, &body)
    action = double("action")
    metadata = Workflow::ActionMetadata.new(
      expected_keys: expected,
      promised_keys: promised,
      defaults: defaults
    )
    allow(action).to receive(:workflow_metadata).and_return(metadata)
    allow(action).to receive(:call) { |ctx| body&.call(ctx) || ctx }
    action
  end

  it "calls action's #call with the context" do
    called = false
    action = make_action { |ctx|
      called = true
      ctx
    }
    runner.call(action, Workflow::Context.new)
    expect(called).to eq(true)
  end

  it "returns the context" do
    action = make_action
    ctx = Workflow::Context.new
    expect(runner.call(action, ctx)).to equal(ctx)
  end

  it "returns ctx unchanged if stop_processing?" do
    action = make_action
    ctx = Workflow::Context.new
    ctx.fail!
    result = runner.call(action, ctx)
    expect(action).not_to have_received(:call)
    expect(result).to equal(ctx)
  end

  it "sets ctx.current_step to action before calling" do
    action = make_action
    ctx = Workflow::Context.new
    runner.call(action, ctx)
    expect(ctx.current_step).to equal(action)
  end

  describe "defaults" do
    it "applies defaults from metadata" do
      action = make_action(expected: [:flag], defaults: {flag: true})
      ctx = Workflow::Context.new
      runner.call(action, ctx)
      expect(ctx[:flag]).to eq(true)
    end

    it "applies callable defaults" do
      action = make_action(expected: [:flag], defaults: {flag: ->(ctx) { ctx[:base] + 1 }})
      ctx = Workflow::Context.new(base: 10)
      runner.call(action, ctx)
      expect(ctx[:flag]).to eq(11)
    end

    it "does not overwrite existing keys with defaults" do
      action = make_action(expected: [:flag], defaults: {flag: true})
      ctx = Workflow::Context.new(flag: false)
      runner.call(action, ctx)
      expect(ctx[:flag]).to eq(false)
    end
    it "applies remaining defaults independently when an earlier key already exists" do
      action = make_action(defaults: {a: 1, b: 2, c: 3})
      ctx = Workflow::Context.new(a: 99)
      runner.call(action, ctx)
      expect(ctx[:a]).to eq(99)
      expect(ctx[:b]).to eq(2)
      expect(ctx[:c]).to eq(3)
    end
  end

  describe "expected keys verification" do
    it "raises ExpectedKeysMissing when keys are absent" do
      action = make_action(expected: [:user, :amount])
      ctx = Workflow::Context.new
      expect { runner.call(action, ctx) }.to raise_error(Workflow::ExpectedKeysMissing)
    end

    it "error message includes inspected missing keys" do
      action = make_action(expected: [:user])
      ctx = Workflow::Context.new
      expect { runner.call(action, ctx) }.to raise_error(Workflow::ExpectedKeysMissing, a_string_matching(/\[:user\]/))
    end

    it "does not raise when all expected keys are present" do
      action = make_action(expected: [:user])
      ctx = Workflow::Context.new(user: "Alice")
      expect { runner.call(action, ctx) }.not_to raise_error
    end
  end

  describe "promised keys verification" do
    it "raises PromisedKeysMissing when keys are absent after call" do
      action = make_action(promised: [:charge])
      ctx = Workflow::Context.new
      expect { runner.call(action, ctx) }.to raise_error(Workflow::PromisedKeysMissing)
    end
    it "promised error message includes inspected missing keys" do
      action = make_action(promised: [:charge])
      ctx = Workflow::Context.new
      expect { runner.call(action, ctx) }.to raise_error(Workflow::PromisedKeysMissing, a_string_matching(/\[:charge\]/))
    end

    it "does not verify promised keys on failure" do
      action = make_action(promised: [:charge]) { |ctx| ctx.fail! }
      ctx = Workflow::Context.new
      expect { runner.call(action, ctx) }.not_to raise_error
    end

    it "does not raise when all promised keys are present" do
      action = make_action(promised: [:charge]) { |ctx| ctx[:charge] = 100 }
      ctx = Workflow::Context.new
      expect { runner.call(action, ctx) }.not_to raise_error
    end
  end

  describe ".default" do
    it "returns a new ActionRunner" do
      expect(described_class.default).to be_a(described_class)
    end
  end
  it "stores the provided logger" do
    logger = double("logger")
    r = described_class.new(logger: logger)
    expect(r.instance_variable_get(:@logger)).to equal(logger)
  end

  describe "hooks" do
    it "runs before hooks in order" do
      order = []
      h1 = ->(_action, _ctx) { order << :before1 }
      h2 = ->(_action, _ctx) { order << :before2 }
      r = described_class.new(before_hooks: [h1, h2])
      action = make_action
      r.call(action, Workflow::Context.new)
      expect(order).to eq(%i[before1 before2])
    end
    it "passes the action to before hooks" do
      received = nil
      hook = ->(action, _ctx) { received = action }
      r = described_class.new(before_hooks: [hook])
      action = make_action
      r.call(action, Workflow::Context.new)
      expect(received).to equal(action)
    end

    it "passes the context to before hooks" do
      received = nil
      hook = ->(_action, ctx) { received = ctx }
      r = described_class.new(before_hooks: [hook])
      action = make_action
      ctx = Workflow::Context.new
      r.call(action, ctx)
      expect(received).to equal(ctx)
    end

    it "runs after hooks in order" do
      order = []
      h1 = ->(_action, _ctx) { order << :after1 }
      h2 = ->(_action, _ctx) { order << :after2 }
      r = described_class.new(after_hooks: [h1, h2])
      action = make_action
      r.call(action, Workflow::Context.new)
      expect(order).to eq(%i[after1 after2])
    end
    it "passes the action to after hooks" do
      received = nil
      hook = ->(action, _ctx) { received = action }
      r = described_class.new(after_hooks: [hook])
      action = make_action
      r.call(action, Workflow::Context.new)
      expect(received).to equal(action)
    end

    it "passes the context to after hooks" do
      received = nil
      hook = ->(_action, ctx) { received = ctx }
      r = described_class.new(after_hooks: [hook])
      action = make_action
      ctx = Workflow::Context.new
      r.call(action, ctx)
      expect(received).to equal(ctx)
    end

    it "runs around hooks wrapping action.call" do
      order = []
      around = ->(_action, _ctx, &blk) {
        order << :around_before
        result = blk.call
        order << :around_after
        result
      }
      r = described_class.new(around_hooks: [around])
      action = make_action { |ctx|
        order << :action
        ctx
      }
      r.call(action, Workflow::Context.new)
      expect(order).to eq(%i[around_before action around_after])
    end
    it "passes the action to around hooks" do
      received = nil
      hook = ->(action, _ctx, &blk) {
        received = action
        blk.call
      }
      r = described_class.new(around_hooks: [hook])
      action = make_action
      r.call(action, Workflow::Context.new)
      expect(received).to equal(action)
    end

    it "passes the context to around hooks" do
      received = nil
      hook = ->(_action, ctx, &blk) {
        received = ctx
        blk.call
      }
      r = described_class.new(around_hooks: [hook])
      action = make_action
      ctx = Workflow::Context.new
      r.call(action, ctx)
      expect(received).to equal(ctx)
    end

    it "composes multiple around hooks correctly" do
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
      r = described_class.new(around_hooks: [outer, inner])
      action = make_action { |ctx|
        order << :action
        ctx
      }
      r.call(action, Workflow::Context.new)
      expect(order).to eq(%i[outer_before inner_before action inner_after outer_after])
    end

    it "works with no hooks" do
      r = described_class.new
      action = make_action
      ctx = Workflow::Context.new
      expect { r.call(action, ctx) }.not_to raise_error
    end
  end

  describe "logging" do
    it "logs action execution via logger" do
      log_messages = []
      logger = ->(msg) { log_messages << msg }
      r = described_class.new(logger: logger)

      action = make_action { |ctx| ctx }
      r.call(action, Workflow::Context.new)

      expect(log_messages).not_to be_empty
      expect(log_messages.first).to match(/executing/)
    end

    it "includes action class name in log" do
      log_messages = []
      logger = ->(msg) { log_messages << msg }
      r = described_class.new(logger: logger)

      action = make_action { |ctx| ctx }
      r.call(action, Workflow::Context.new)

      expect(log_messages.first).to match(/Double/)
    end

    it "does not log when no logger configured" do
      r = described_class.new(logger: nil)
      action = make_action { |ctx| ctx }
      expect { r.call(action, Workflow::Context.new) }.not_to raise_error
    end

    it "logs the action class name, not the class object" do
      log_messages = []
      logger = ->(msg) { log_messages << msg }
      r = described_class.new(logger: logger)

      action = Class.new do
        include Workflow::Action

        def call(ctx)
        end

        def self.name
          "MyAction"
        end
      end.new

      r.call(action, Workflow::Context.new)

      expect(log_messages.first).to eq("[Workflow] executing MyAction")
    end
  end

  describe "capture_exceptions" do
    it "converts exceptions to failed contexts when enabled" do
      runner = described_class.new(capture_exceptions: true)
      action = make_action(expected: [], promised: []) { |_ctx|
        raise "Something went wrong"
      }

      ctx = runner.call(action, Workflow::Context.new)
      expect(ctx).to be_failure
      expect(ctx.message).to eq("Something went wrong")
    end

    it "lets exceptions bubble up when disabled" do
      runner = described_class.new(capture_exceptions: false)
      action = make_action(expected: [], promised: []) { |_ctx|
        raise "Something went wrong"
      }

      expect {
        runner.call(action, Workflow::Context.new)
      }.to raise_error(RuntimeError, "Something went wrong")
    end

    it "lets exceptions bubble up by default" do
      runner = described_class.new
      action = make_action(expected: [], promised: []) { |_ctx|
        raise "Something went wrong"
      }

      expect {
        runner.call(action, Workflow::Context.new)
      }.to raise_error(RuntimeError, "Something went wrong")
    end

    it "preserves exception class name as error_code" do
      runner = described_class.new(capture_exceptions: true)
      action = make_action(expected: [], promised: []) { |_ctx|
        raise KeyError, "missing key"
      }

      ctx = runner.call(action, Workflow::Context.new)
      expect(ctx.error_code).to eq(:KeyError)
    end

    it "does not capture FailWithRollback" do
      runner = described_class.new(capture_exceptions: true)
      action = make_action(expected: [], promised: []) { |ctx|
        ctx.fail_with_rollback!("boom")
      }

      expect {
        runner.call(action, Workflow::Context.new)
      }.to raise_error(Workflow::FailWithRollback)
    end

    it "runs around hooks with correct action when capturing exceptions" do
      received_action = nil
      received_ctx = nil
      hook = ->(action, ctx, &blk) {
        received_action = action
        received_ctx = ctx
        blk.call
      }
      runner = described_class.new(capture_exceptions: true, around_hooks: [hook])
      action = make_action(expected: [], promised: []) { |_ctx|
        raise "boom"
      }
      ctx = Workflow::Context.new

      runner.call(action, ctx)
      expect(received_action).to eq(action)
      expect(received_ctx).to eq(ctx)
    end
  end
end
