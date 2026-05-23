# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Testing::ContextFactory do
  before do
    stub_const("StepOne", Class.new {
      include Workflow::Action

      expects :input
      promises :step_one_result

      def call(ctx)
        ctx[:step_one_result] = ctx[:input] + 1
      end
    })

    stub_const("StepTwo", Class.new {
      include Workflow::Action

      expects :step_one_result
      promises :step_two_result

      def call(ctx)
        ctx[:step_two_result] = ctx[:step_one_result] * 10
      end
    })

    stub_const("MyWorkflow", Class.new {
      include Workflow::Organizer

      def initialize(step_one:, step_two:)
        @step_one = step_one
        @step_two = step_two
      end

      def call(input:)
        with(input: input).reduce(@step_one, @step_two)
      end
    })
  end

  it "builds context up to a specific action instance" do
    step_one = StepOne.new
    step_two = StepTwo.new
    workflow = MyWorkflow.new(step_one: step_one, step_two: step_two)

    ctx = described_class
      .make_from(workflow)
      .before(step_two)
      .with(input: 5)

    expect(ctx[:input]).to eq(5)
    expect(ctx[:step_one_result]).to eq(6)
    expect(ctx.key?(:step_two_result)).to eq(false)
  end

  it "builds context up to a specific action class" do
    step_one = StepOne.new
    step_two = StepTwo.new
    workflow = MyWorkflow.new(step_one: step_one, step_two: step_two)

    ctx = described_class
      .make_from(workflow)
      .before(StepTwo)
      .with(input: 5)

    expect(ctx[:step_one_result]).to eq(6)
  end

  it ".with overrides context values after building" do
    step_one = StepOne.new
    step_two = StepTwo.new
    workflow = MyWorkflow.new(step_one: step_one, step_two: step_two)

    ctx = described_class
      .make_from(workflow)
      .before(step_two)
      .with(input: 5, step_one_result: 99)

    expect(ctx[:step_one_result]).to eq(99)
  end

  it "works when looking up before the first action" do
    step_one = StepOne.new
    step_two = StepTwo.new
    workflow = MyWorkflow.new(step_one: step_one, step_two: step_two)

    ctx = described_class
      .make_from(workflow)
      .before(step_one)
      .with(input: 10)

    expect(ctx[:input]).to eq(10)
    expect(ctx.key?(:step_one_result)).to eq(false)
  end

  it "does not execute steps after the matched class" do
    step_one = StepOne.new
    step_two = StepTwo.new
    workflow = MyWorkflow.new(step_one: step_one, step_two: step_two)

    ctx = described_class
      .make_from(workflow)
      .before(StepTwo)
      .with(input: 5)

    expect(ctx[:step_one_result]).to eq(6)
    expect(ctx.key?(:step_two_result)).to eq(false)
  end

  it "builds context when with is called without arguments" do
    step_one = StepOne.new
    step_two = StepTwo.new
    workflow = MyWorkflow.new(step_one: step_one, step_two: step_two)

    ctx = described_class
      .make_from(workflow)
      .before(step_one)
      .with

    expect(ctx).to be_a(Workflow::Context)
    expect(ctx.key?(:step_one_result)).to eq(false)
  end

  it "invokes action steps through ActionRunner applying defaults" do
    stub_const("StepWithDefault", Class.new {
      include Workflow::Action

      expects :value, default: 10
      promises :doubled

      def call(ctx)
        ctx[:doubled] = ctx[:value] * 2
      end
    })

    stub_const("FinalStep", Class.new {
      include Workflow::Action

      expects :doubled
      promises :final

      def call(ctx)
        ctx[:final] = ctx[:doubled] + 1
      end
    })

    step = StepWithDefault.new
    final = FinalStep.new

    organizer = Class.new {
      def initialize(s, f)
        @step = s
        @final = f
      end
    }.new(step, final)

    ctx = described_class
      .make_from(organizer)
      .before(final)
      .with

    expect(ctx[:doubled]).to eq(20)
  end

  it "collects callable ivars and flattens array ivars, skipping Context and non-callable ivars" do
    callable_ran = false
    array_step_ran = false

    callable_step = ->(ctx) {
      callable_ran = true
      ctx[:from_callable] = true
    }
    array_step = ->(ctx) {
      array_step_ran = true
      ctx[:from_array] = true
    }

    context_ivar = Workflow::Context.new(unrelated: true)
    plain_string = "not a step"

    target = ->(ctx) { ctx[:target_ran] = true }

    organizer = Class.new {
      def initialize(ctx, callable, arr, plain, tgt)
        @ctx_ivar = ctx
        @callable_ivar = callable
        @array_ivar = arr
        @plain_ivar = plain
        @target_ivar = tgt
      end
    }.new(context_ivar, callable_step, [array_step], plain_string, target)

    ctx = described_class.make_from(organizer).before(target).with

    expect(callable_ran).to eq(true)
    expect(array_step_ran).to eq(true)
    expect(ctx[:from_callable]).to eq(true)
    expect(ctx[:from_array]).to eq(true)
    expect(ctx.key?(:target_ran)).to eq(false)
  end

  it "flattens nested arrays of steps" do
    inner_ran = false
    inner_step = ->(ctx) {
      inner_ran = true
      ctx[:inner] = true
    }

    target = ->(ctx) { ctx[:done] = true }

    organizer = Class.new {
      def initialize(steps, tgt)
        @steps = steps
        @target = tgt
      end
    }.new([[inner_step]], target)

    ctx = described_class.make_from(organizer).before(target).with

    expect(inner_ran).to eq(true)
    expect(ctx[:inner]).to eq(true)
  end

  it "skips Context ivars and non-callable non-array ivars" do
    target = ->(ctx) { ctx[:done] = true }

    organizer = Class.new {
      def initialize(ctx_ivar, string_ivar, number_ivar, tgt)
        @ctx = ctx_ivar
        @name = string_ivar
        @count = number_ivar
        @target = tgt
      end
    }.new(Workflow::Context.new(a: 1), "hello", 42, target)

    ctx = described_class.make_from(organizer).before(target).with

    expect(ctx.key?(:done)).to eq(false)
  end
end
