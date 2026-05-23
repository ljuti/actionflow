# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Steps::AddAliases do
  it "registers aliases on context" do
    step = described_class.new(name: :full_name)
    ctx = Workflow::Context.new(full_name: "Alice")
    step.call(ctx)
    expect(ctx[:name]).to eq("Alice")
  end

  it "returns ctx" do
    step = described_class.new(name: :full_name)
    ctx = Workflow::Context.new(full_name: "Alice")
    expect(step.call(ctx)).to equal(ctx)
  end
end
