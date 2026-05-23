# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Steps::ReduceIfElse do
  it "runs if-steps when condition is truthy" do
    if_ran = false
    else_ran = false
    step = described_class.new(
      ->(ctx) { true },
      [->(ctx) { if_ran = true; ctx }],
      [->(ctx) { else_ran = true; ctx }]
    )
    step.call(Workflow::Context.new)
    expect(if_ran).to eq(true)
    expect(else_ran).to eq(false)
  end

  it "runs else-steps when condition is falsy" do
    if_ran = false
    else_ran = false
    step = described_class.new(
      ->(ctx) { false },
      [->(ctx) { if_ran = true; ctx }],
      [->(ctx) { else_ran = true; ctx }]
    )
    step.call(Workflow::Context.new)
    expect(if_ran).to eq(false)
    expect(else_ran).to eq(true)
  end

  it "returns ctx unchanged if stop_processing?" do
    if_ran = false
    step = described_class.new(
      ->(ctx) { true },
      [->(ctx) { if_ran = true; ctx }],
      []
    )
    ctx = Workflow::Context.new
    ctx.fail!
    step.call(ctx)
    expect(if_ran).to eq(false)
  end
end
