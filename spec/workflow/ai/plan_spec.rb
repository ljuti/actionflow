# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Ai::Plan do
  it "parses a linear plan from hash" do
    raw = {
      "name" => "test_workflow",
      "input" => {"order_id" => "ord_123"},
      "steps" => [
        {"id" => "find_order"},
        {"id" => "validate_order"}
      ]
    }

    plan = described_class.new(raw)
    expect(plan.name).to eq("test_workflow")
    expect(plan.input).to eq({"order_id" => "ord_123"})
    expect(plan.steps.length).to eq(2)
    expect(plan.steps[0]).to eq({"id" => "find_order"})
  end

  it "parses a conditional step" do
    raw = {
      "name" => "conditional",
      "steps" => [
        {"type" => "if", "condition" => {"key" => "eligible", "equals" => true}, "then" => [{"id" => "process"}]}
      ]
    }

    plan = described_class.new(raw)
    step = plan.steps[0]
    expect(step["type"]).to eq("if")
    expect(step["then"]).to eq([{"id" => "process"}])
  end

  it "parses an iteration step" do
    raw = {
      "name" => "iter",
      "steps" => [
        {"type" => "iterate", "collection" => "orders", "as" => "order", "steps" => [{"id" => "process"}]}
      ]
    }

    plan = described_class.new(raw)
    step = plan.steps[0]
    expect(step["type"]).to eq("iterate")
    expect(step["collection"]).to eq("orders")
  end

  it "raises on plan without steps" do
    expect { described_class.new({"name" => "empty"}) }.to raise_error(ArgumentError)
  end

  it "raises on non-hash input" do
    expect { described_class.new("not a hash") }.to raise_error(ArgumentError)
  end
end
