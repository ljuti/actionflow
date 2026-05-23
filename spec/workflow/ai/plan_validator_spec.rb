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
    registry.register(Workflow::Ai::Capability.new(
      :notify, action: ->(ctx) { ctx },
      description: "Notify", expects: [:order], promises: [:notified],
      side_effects: [], risk: :low
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

  it "defaults initial_keys to empty when not provided" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "find_order"}]
    })

    result = validator.validate(plan)
    # find_order expects :order_id which is not in the empty default key set
    expect(result).not_to be_safe
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

  it "does not require approval when all steps are low risk" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"id" => "find_order"},
        {"id" => "validate_order"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result.requires_approval?).to eq(false)
  end

  it "returns exact error message for missing id" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"type" => "linear"}]
    })

    result = validator.validate(plan, initial_keys: [])
    expect(result.errors).to include("Step missing 'id': {\"type\" => \"linear\"}")
  end

  it "returns exact error message for unknown capability" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "nonexistent"}]
    })

    result = validator.validate(plan, initial_keys: [])
    expect(result.errors).to include("Unknown capability: nonexistent")
  end

  it "returns exact error message for missing expected keys" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "find_order"}]
    })

    result = validator.validate(plan, initial_keys: [])
    expect(result.errors).to include(a_string_matching(/Step 'find_order' missing expected keys: \[:order_id\]\. Available:/))
  end

  it "validates if branch steps" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if",
         "condition" => {"key" => "valid", "equals" => true},
         "then" => [{"id" => "validate_order"}]}
      ]
    })

    # validate_order expects :order, which is not available
    result = validator.validate(plan, initial_keys: [])
    expect(result).not_to be_safe
    expect(result.errors).to include(a_string_matching(/validate_order/))
  end

  it "validates if_else both branches" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if_else",
         "condition" => {"key" => "valid", "equals" => true},
         "then" => [{"id" => "validate_order"}],
         "else" => [{"id" => "notify"}]}
      ]
    })

    # Both branches have missing keys
    result = validator.validate(plan, initial_keys: [])
    expect(result).not_to be_safe
    expect(result.errors.length).to be >= 2
  end

  it "validates iterate steps" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "iterate",
         "collection" => "orders",
         "as" => "order",
         "steps" => [{"id" => "validate_order"}]}
      ]
    })

    # iterate adds :order to available keys via 'as', so validate_order should pass
    result = validator.validate(plan, initial_keys: [])
    expect(result).to be_safe
  end

  it "iterate uses default item key when as is absent" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "iterate",
         "collection" => "orders",
         "steps" => [{"id" => "find_order"}]}
      ]
    })

    # Default item key is :item; find_order expects :order_id, not available
    result = validator.validate(plan, initial_keys: [])
    expect(result).not_to be_safe
  end

  it "track_step_keys adds promised keys from then branch to available keys" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if",
         "condition" => {"key" => "valid", "equals" => true},
         "then" => [{"id" => "find_order"}]},
        {"id" => "validate_order"}
      ]
    })

    # find_order in if branch promises :order, which should become available
    # for the subsequent validate_order step
    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result).to be_safe
  end

  it "sets requires_approval to false when no high-risk steps" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "find_order"}]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result.requires_approval?).to eq(false)
  end

  it "ValidationResult safe? returns false when errors present" do
    result = Workflow::Ai::PlanValidator::ValidationResult.new(errors: ["some error"])
    expect(result.safe?).to eq(false)
  end

  it "ValidationResult safe? returns true when errors empty" do
    result = Workflow::Ai::PlanValidator::ValidationResult.new(errors: [])
    expect(result.safe?).to eq(true)
  end

  it "ValidationResult defaults errors to empty and requires_approval to false" do
    result = Workflow::Ai::PlanValidator::ValidationResult.new
    expect(result.errors).to eq([])
    expect(result.requires_approval?).to eq(false)
  end
end
