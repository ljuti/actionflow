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

  it "raises on plan without steps with descriptive message" do
    expect { described_class.new({"name" => "empty"}) }.to raise_error(ArgumentError, "Plan must have steps")
  end

  it "raises on plan without steps" do
    expect { described_class.new({"name" => "empty"}) }.to raise_error(ArgumentError)
  end

  it "raises on non-hash input with descriptive message" do
    expect { described_class.new("not a hash") }.to raise_error(ArgumentError, "Plan must be a Hash")
  end

  it "raises on non-hash input" do
    expect { described_class.new("not a hash") }.to raise_error(ArgumentError)
  end

  it "accepts Hash subclass because is_a? includes subclasses" do
    custom_hash = Class.new(Hash) {
      def initialize
        super
        self["steps"] = [{"id" => "a"}]
      end
    }.new

    plan = described_class.new(custom_hash)
    expect(plan.steps).to eq([{"id" => "a"}])
  end

  it "defaults input to empty hash when input key is absent" do
    raw = {"steps" => [{"id" => "a"}]}
    plan = described_class.new(raw)
    expect(plan.input).to eq({})
  end

  it "preserves input value when present" do
    raw = {"steps" => [{"id" => "a"}], "input" => {"key" => "val"}}
    plan = described_class.new(raw)
    expect(plan.input).to eq({"key" => "val"})
  end

  it "sets name to nil when name key is absent" do
    raw = {"steps" => [{"id" => "a"}]}
    plan = described_class.new(raw)
    expect(plan.name).to be_nil
  end

  it "sets name to value when present" do
    raw = {"name" => "my_plan", "steps" => [{"id" => "a"}]}
    plan = described_class.new(raw)
    expect(plan.name).to eq("my_plan")
  end

  it "returns steps as the exact object from raw hash" do
    steps = [{"id" => "find_order"}]
    raw = {"steps" => steps}
    plan = described_class.new(raw)
    expect(plan.steps).to equal(steps)
  end
end
