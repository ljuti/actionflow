# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Ai::PlanValidator do
  let(:registry) { Workflow::Ai::CapabilityRegistry.new }
  let(:validator) { described_class.new(registry: registry) }

  before do
    registry.register(Workflow::Ai::Capability.new(
      :find_order, action: ->(ctx) { ctx },
      description: "Find", expects: [:order_id], promises: [:order],
      side_effects: [], risk: :low
    ))
    registry.register(Workflow::Ai::Capability.new(
      :validate_order, action: ->(ctx) { ctx },
      description: "Validate", expects: [:order], promises: [:valid],
      side_effects: [], risk: :low
    ))
    registry.register(Workflow::Ai::Capability.new(
      :issue_refund, action: ->(ctx) { ctx },
      description: "Refund", expects: [:order], promises: [:refund],
      side_effects: [:money_movement], risk: :high, requires_approval: true
    ))
  end

  it "valid linear plan passes" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "input" => {"order_id" => "ord_123"},
      "steps" => [
        {"id" => "find_order"},
        {"id" => "validate_order"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result).to be_safe
    expect(result.errors).to be_empty
  end

  it "unknown step id fails validation" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "unknown_step"}]
    })

    result = validator.validate(plan, initial_keys: [])
    expect(result).not_to be_safe
    expect(result.errors).to include(a_string_matching(/unknown_step/))
  end

  it "missing expected keys detected" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "find_order"}]
    })

    result = validator.validate(plan, initial_keys: [])
    expect(result).not_to be_safe
    expect(result.errors).to include(a_string_matching(/order_id/))
  end

  it "promised keys added to simulated key set" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "input" => {"order_id" => "ord_123"},
      "steps" => [
        {"id" => "find_order"},
        {"id" => "validate_order"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result).to be_safe
  end

  it "high-risk step triggers approval flag" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"id" => "find_order"},
        {"id" => "issue_refund"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result.requires_approval?).to eq(true)
  end
end
