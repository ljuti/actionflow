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
end
