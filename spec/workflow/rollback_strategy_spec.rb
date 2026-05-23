# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::RollbackStrategy do
  it "calls rollback on steps that respond to it" do
    step = double("step")
    allow(step).to receive(:respond_to?).with(:rollback).and_return(true)
    allow(step).to receive(:rollback)

    ctx = Workflow::Context.new
    described_class.new.rollback(ctx, [step])

    expect(step).to have_received(:rollback).with(ctx)
  end

  it "skips steps without rollback" do
    step = double("step")
    allow(step).to receive(:respond_to?).with(:rollback).and_return(false)

    ctx = Workflow::Context.new
    expect { described_class.new.rollback(ctx, [step]) }.not_to raise_error
  end

  it "iterates in reverse order" do
    order = []
    step1 = double("step1")
    allow(step1).to receive(:respond_to?).with(:rollback).and_return(true)
    allow(step1).to receive(:rollback) { order << 1 }

    step2 = double("step2")
    allow(step2).to receive(:respond_to?).with(:rollback).and_return(true)
    allow(step2).to receive(:rollback) { order << 2 }

    step3 = double("step3")
    allow(step3).to receive(:respond_to?).with(:rollback).and_return(true)
    allow(step3).to receive(:rollback) { order << 3 }

    ctx = Workflow::Context.new
    described_class.new.rollback(ctx, [step1, step2, step3])

    expect(order).to eq([3, 2, 1])
  end

  it "returns ctx" do
    ctx = Workflow::Context.new
    result = described_class.new.rollback(ctx, [])
    expect(result).to equal(ctx)
  end
end
