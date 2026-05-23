# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::OrganizerSession do
  let(:ctx) { Workflow::Context.new(input: 1) }
  let(:session) { described_class.new(ctx) }

  it "reduce returns context" do
    result = session.reduce(->(ctx) { ctx })
    expect(result).to be_a(Workflow::Context)
  end

  it "reduce executes steps" do
    called = false
    session.reduce([->(ctx) {
      called = true
      ctx
    }])
    expect(called).to eq(true)
  end

  it "before_each accumulates and applies hooks" do
    hook_called = false
    hook = ->(_action, _ctx) { hook_called = true }

    action = Class.new {
      include Workflow::Action

      expects :input
      def call(ctx)
      end
    }.new

    session.before_each(hook)
    session.reduce([action])
    expect(hook_called).to eq(true)
  end

  it "after_each accumulates and applies hooks" do
    hook_called = false
    hook = ->(_action, _ctx) { hook_called = true }

    action = Class.new {
      include Workflow::Action

      expects :input
      def call(ctx)
      end
    }.new

    session.after_each(hook)
    session.reduce([action])
    expect(hook_called).to eq(true)
  end

  it "around_each wraps action execution" do
    order = []
    hook = ->(_action, _ctx, &blk) {
      order << :before
      result = blk.call
      order << :after
      result
    }

    action = Class.new {
      include Workflow::Action

      expects :input
      def call(ctx)
        ctx[:ran] = true
      end
    }.new

    session.around_each(hook)
    result = session.reduce([action])
    expect(order).to eq(%i[before after])
    expect(result[:ran]).to eq(true)
  end

  it "hook methods return self for chaining" do
    hook = ->(*_args) {}
    expect(session.before_each(hook)).to equal(session)
    expect(session.after_each(hook)).to equal(session)
    expect(session.around_each(hook)).to equal(session)
  end

  it "steps are flattened" do
    s1 = ->(ctx) {
      ctx[:one] = true
      ctx
    }
    s2 = ->(ctx) {
      ctx[:two] = true
      ctx
    }

    result = session.reduce([[s1], [s2]])
    expect(result[:one]).to eq(true)
    expect(result[:two]).to eq(true)
  end

  it "applies global hooks from Configuration" do
    hook_log = []
    global_hook = ->(action, _ctx) { hook_log << :global_before }

    begin
      Workflow.configuration.before_hooks = [global_hook]

      action = Class.new {
        include Workflow::Action

        expects :input
        def call(ctx)
        end
      }.new

      session.reduce([action])
      expect(hook_log).to eq([:global_before])
    ensure
      Workflow.configuration.before_hooks = []
    end
  end

  it "applies global hooks combined with session hooks" do
    hook_log = []
    global_hook = ->(action, _ctx) { hook_log << :global }
    session_hook = ->(action, _ctx) { hook_log << :session }

    begin
      Workflow.configuration.before_hooks = [global_hook]

      action = Class.new {
        include Workflow::Action

        expects :input
        def call(ctx)
        end
      }.new

      session.before_each(session_hook)
      session.reduce([action])
      expect(hook_log).to eq(%i[global session])
    ensure
      Workflow.configuration.before_hooks = []
    end
  end

  it "applies global after_hooks from Configuration" do
    hook_log = []
    global_hook = ->(action, _ctx) { hook_log << :global_after }

    begin
      Workflow.configuration.after_hooks = [global_hook]

      action = Class.new {
        include Workflow::Action

        expects :input
        def call(ctx)
        end
      }.new

      session.reduce([action])
      expect(hook_log).to eq([:global_after])
    ensure
      Workflow.configuration.after_hooks = []
    end
  end

  it "applies global around_hooks from Configuration" do
    hook_log = []
    global_hook = ->(action, _ctx, &blk) {
      hook_log << :global_around_before
      blk.call
      hook_log << :global_around_after
    }

    begin
      Workflow.configuration.around_hooks = [global_hook]

      action = Class.new {
        include Workflow::Action

        expects :input
        def call(ctx)
        end
      }.new

      session.reduce([action])
      expect(hook_log).to eq(%i[global_around_before global_around_after])
    ensure
      Workflow.configuration.around_hooks = []
    end
  end

  it "passes configured logger to ActionRunner" do
    test_logger = Object.new
    original_logger = Workflow.configuration.logger
    Workflow.configuration.logger = test_logger

    expect(Workflow::ActionRunner).to receive(:new).with(
      hash_including(logger: test_logger)
    ).and_call_original

    session.reduce(->(ctx) { ctx })

    Workflow.configuration.logger = original_logger
  end
end
