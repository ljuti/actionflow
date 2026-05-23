# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Steps::AddToContext do
  it "adds key-value pairs to context" do
    step = described_class.new(status: "pending", count: 0)
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx[:status]).to eq("pending")
    expect(ctx[:count]).to eq(0)
  end

  it "overwrites existing keys" do
    step = described_class.new(status: "done")
    ctx = Workflow::Context.new(status: "pending")
    step.call(ctx)
    expect(ctx[:status]).to eq("done")
  end
end
