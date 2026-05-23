# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::OrganizerSession do
  let(:organizer) { double("organizer") }
  let(:ctx) { Workflow::Context.new(input: 1) }
  let(:session) { described_class.new(organizer, ctx) }

  it "reduce returns context" do
    result = session.reduce(->(ctx) { ctx })
    expect(result).to be_a(Workflow::Context)
  end

  it "reduce executes steps" do
    called = false
    session.reduce([->(ctx) { called = true; ctx }])
    expect(called).to eq(true)
  end

  it "before_each accumulates and applies hooks" do
    hook_called = false
    hook = ->(_action, _ctx) { hook_called = true }

    action = Class.new {
      include Workflow::Action
      expects :input
      def call(ctx); end
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
      def call(ctx); end
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
    result = nil
    s1 = ->(ctx) { ctx[:one] = true; ctx }
    s2 = ->(ctx) { ctx[:two] = true; ctx }

    result = session.reduce([[s1], [s2]])
    expect(result[:one]).to eq(true)
    expect(result[:two]).to eq(true)
  end
end
