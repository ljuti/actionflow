# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Ai::DynamicOrganizer do
  it "executes compiled steps" do
    organizer = described_class.new(steps: [
      ->(ctx) { ctx[:step1] = true; ctx },
      ->(ctx) { ctx[:step2] = true; ctx }
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
      def call(ctx); end
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
end
