# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Organizer do
  let(:organizer_class) do
    Class.new do
      include Workflow::Organizer
    end
  end

  let(:organizer) { organizer_class.new }

  describe "#with" do
    it "creates OrganizerSession with Context from hash" do
      session = organizer.with(foo: 1)
      expect(session).to be_a(Workflow::OrganizerSession)
    end

    it "works without arguments" do
      result = organizer.with.reduce([])
      expect(result).to be_success
    end
    # Kill: data.is_a?(Workflow::Context) → true — hash lacks organized_by= setter
    it "creates a working Context from hash input" do
      result = organizer.with(x: 42).reduce([])
      expect(result[:x]).to eq(42)
    end

    it "uses Context directly when given one" do
      ctx = Workflow::Context.new(foo: 1)
      session = organizer.with(ctx)
      expect(session).to be_a(Workflow::OrganizerSession)
    end

    # Kill: data.is_a?(Workflow::Context) → false/nil — Context gets re-wrapped (different object)
    it "preserves the exact Context object when given one" do
      ctx = Workflow::Context.new(x: 1)
      result = organizer.with(ctx).reduce([])
      expect(result).to equal(ctx)
    end

    it "sets ctx.organized_by to self" do
      session = organizer.with(foo: 1)
      # Access the internal context via reduce
      result = session.reduce([])
      expect(result.organized_by).to equal(organizer)
    end

    # Kill: remove ctx.organized_by = self — check immediately after with()
    it "sets organized_by on the context object" do
      ctx = Workflow::Context.new
      organizer.with(ctx)
      expect(ctx.organized_by).to equal(organizer)
    end

    it "returns OrganizerSession" do
      expect(organizer.with({})).to be_a(Workflow::OrganizerSession)
    end
  end

  describe "#reduce" do
    it "shortcut works without explicit with" do
      result = organizer.reduce(->(ctx) {
        ctx[:set] = true
        ctx
      })
      expect(result[:set]).to eq(true)
    end

    # Kill: with({}) → with — verifies reduce still produces a working context
    it "reduce with empty context passes data through steps" do
      result = organizer.reduce(->(ctx) {
        ctx[:from_reduce] = true
        ctx
      })
      expect(result[:from_reduce]).to eq(true)
      expect(result).to be_success
    end
  end

  describe "control-flow helpers" do
    it "reduce_if returns a ReduceIf step" do
      step = organizer.reduce_if(->(ctx) { true }, [])
      expect(step).to be_a(Workflow::Steps::ReduceIf)
    end

    # Kill: reduce_if constructor arg mutations — condition and steps must be wired
    it "reduce_if runs steps when condition is true" do
      step = organizer.reduce_if(->(ctx) { true }, [->(ctx) {
        ctx[:ran] = true
        ctx
      }])
      ctx = Workflow::Context.new
      step.call(ctx)
      expect(ctx[:ran]).to eq(true)
    end

    it "reduce_if skips steps when condition is false" do
      step = organizer.reduce_if(->(ctx) { false }, [->(ctx) {
        ctx[:ran] = true
        ctx
      }])
      ctx = Workflow::Context.new
      step.call(ctx)
      expect(ctx[:ran]).to be_nil
    end

    it "reduce_if_else returns a ReduceIfElse step" do
      step = organizer.reduce_if_else(->(ctx) { true }, [], [])
      expect(step).to be_a(Workflow::Steps::ReduceIfElse)
    end

    # Kill: reduce_if_else constructor arg mutations — condition, if_steps, else_steps wired
    it "reduce_if_else runs if branch when condition is true" do
      step = organizer.reduce_if_else(
        ->(ctx) { true },
        [->(ctx) {
          ctx[:branch] = :if
          ctx
        }],
        [->(ctx) {
          ctx[:branch] = :else
          ctx
        }]
      )
      ctx = Workflow::Context.new
      step.call(ctx)
      expect(ctx[:branch]).to eq(:if)
    end

    it "reduce_if_else runs else branch when condition is false" do
      step = organizer.reduce_if_else(
        ->(ctx) { false },
        [->(ctx) {
          ctx[:branch] = :if
          ctx
        }],
        [->(ctx) {
          ctx[:branch] = :else
          ctx
        }]
      )
      ctx = Workflow::Context.new
      step.call(ctx)
      expect(ctx[:branch]).to eq(:else)
    end

    it "iterate returns an Iterate step" do
      step = organizer.iterate(:items, [])
      expect(step).to be_a(Workflow::Steps::Iterate)
    end

    # Kill: iterate constructor arg mutations — collection_key and steps wired
    it "iterate runs steps for each item in the collection" do
      results = []
      step = organizer.iterate(:items, [->(ctx) {
        results << ctx[:item]
        ctx
      }])
      ctx = Workflow::Context.new(items: [:a, :b, :c])
      step.call(ctx)
      expect(results).to eq([:a, :b, :c])
    end

    it "iterate passes custom item_key" do
      step = organizer.iterate(:items, [], item_key: :element)
      ctx = Workflow::Context.new(items: [:a])
      step.call(ctx)
      expect(ctx[:element]).to eq(:a)
    end

    it "execute returns an Execute step" do
      step = organizer.execute { |ctx| ctx }
      expect(step).to be_a(Workflow::Steps::Execute)
    end

    # Kill: execute constructor arg mutations — block must be wired
    it "execute runs the given block" do
      ran = false
      step = organizer.execute { |ctx|
        ran = true
        ctx
      }
      step.call(Workflow::Context.new)
      expect(ran).to eq(true)
    end

    it "execute accepts a code block argument" do
      ran = false
      block = ->(ctx) {
        ran = true
        ctx
      }
      step = organizer.execute(block)
      step.call(Workflow::Context.new)
      expect(ran).to eq(true)
    end
  end
end
