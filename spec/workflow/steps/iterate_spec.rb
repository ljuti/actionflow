# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Steps::Iterate do
  it "runs steps for each item" do
    count = 0
    step = described_class.new(:items, [->(ctx) {
      count += 1
      ctx
    }])
    ctx = Workflow::Context.new(items: [1, 2, 3])
    step.call(ctx)
    expect(count).to eq(3)
  end

  it "sets item_key from singularized collection_key" do
    item_values = []
    step = described_class.new(:items, [->(ctx) {
      item_values << ctx[:item]
      ctx
    }])
    ctx = Workflow::Context.new(items: %w[a b c])
    step.call(ctx)
    expect(item_values).to eq(%w[a b c])
  end

  it "uses custom item_key when provided" do
    item_values = []
    step = described_class.new(:items, [->(ctx) {
      item_values << ctx[:element]
      ctx
    }], item_key: :element)
    ctx = Workflow::Context.new(items: [10, 20])
    step.call(ctx)
    expect(item_values).to eq([10, 20])
  end

  it "breaks on stop_processing?" do
    count = 0
    step = described_class.new(:items, [->(ctx) {
      count += 1
      ctx.fail! if count >= 2
      ctx
    }])
    ctx = Workflow::Context.new(items: [1, 2, 3, 4])
    step.call(ctx)
    expect(count).to eq(2)
  end

  it "handles empty collection" do
    ran = false
    step = described_class.new(:items, [->(ctx) {
      ran = true
      ctx
    }])
    ctx = Workflow::Context.new(items: [])
    step.call(ctx)
    expect(ran).to eq(false)
  end
end
