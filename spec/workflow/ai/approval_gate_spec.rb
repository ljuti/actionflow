# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Ai::ApprovalGate do
  let(:action) { ->(ctx) { ctx } }

  let(:registry) do
    registry = Workflow::Ai::CapabilityRegistry.new
    registry.register(Workflow::Ai::Capability.new(:find_order,
      action: action, description: "Find order",
      expects: [:order_id], promises: [:order],
      risk: :low, requires_approval: false))
    registry.register(Workflow::Ai::Capability.new(:issue_refund,
      action: action, description: "Issue refund",
      expects: [:order], promises: [:refund],
      side_effects: [:money_movement], risk: :high,
      requires_approval: true))
    registry
  end

  describe "#check" do
    it "returns no approval needed for safe plan" do
      plan = Workflow::Ai::Plan.new("steps" => [{"id" => "find_order"}])
      validator = Workflow::Ai::PlanValidator.new(registry: registry)
      validation = validator.validate(plan, initial_keys: [:order_id])

      gate = described_class.new(registry: registry)
      result = gate.check(validation, plan)

      expect(result).not_to be_required
      expect(result.pending_steps).to eq([])
    end

    it "identifies steps requiring approval" do
      plan = Workflow::Ai::Plan.new("steps" => [
        {"id" => "find_order"},
        {"id" => "issue_refund"}
      ])
      validator = Workflow::Ai::PlanValidator.new(registry: registry)
      validation = validator.validate(plan, initial_keys: [:order_id])

      gate = described_class.new(registry: registry)
      result = gate.check(validation, plan)

      expect(result).to be_required
      expect(result.pending_steps).to eq([:issue_refund])
      expect(result.reason).to include("money_movement")
    end

    it "includes reason from side effects" do
      plan = Workflow::Ai::Plan.new("steps" => [{"id" => "issue_refund"}])
      validator = Workflow::Ai::PlanValidator.new(registry: registry)
      validation = validator.validate(plan, initial_keys: [:order])

      gate = described_class.new(registry: registry)
      result = gate.check(validation, plan)

      expect(result.reason).to eq("Plan includes high-risk steps: issue_refund (side effects: money_movement)")
    end

    it "returns multiple pending steps" do
      registry.register(Workflow::Ai::Capability.new(:cancel_account,
        action: action, description: "Cancel account",
        expects: [:user], promises: [],
        side_effects: [:account_deletion], risk: :high,
        requires_approval: true))

      plan = Workflow::Ai::Plan.new("steps" => [
        {"id" => "issue_refund"},
        {"id" => "cancel_account"}
      ])
      validator = Workflow::Ai::PlanValidator.new(registry: registry)
      validation = validator.validate(plan, initial_keys: [:order, :user])

      gate = described_class.new(registry: registry)
      result = gate.check(validation, plan)

      expect(result.pending_steps).to eq(%i[issue_refund cancel_account])
    end

    it "produces a hash representation" do
      plan = Workflow::Ai::Plan.new("steps" => [{"id" => "issue_refund"}])
      validator = Workflow::Ai::PlanValidator.new(registry: registry)
      validation = validator.validate(plan, initial_keys: [:order])

      gate = described_class.new(registry: registry)
      result = gate.check(validation, plan)

      h = result.to_h
      expect(h[:status]).to eq("approval_required")
      expect(h[:pending_steps]).to eq([:issue_refund])
      expect(h[:reason]).to include("high-risk")
    end

    it "produces approved hash for safe plan" do
      plan = Workflow::Ai::Plan.new("steps" => [{"id" => "find_order"}])
      validator = Workflow::Ai::PlanValidator.new(registry: registry)
      validation = validator.validate(plan, initial_keys: [:order_id])

      gate = described_class.new(registry: registry)
      result = gate.check(validation, plan)

      expect(result.to_h[:status]).to eq("approved")
    end

    it "finds approval steps inside if branches" do
      plan = Workflow::Ai::Plan.new("steps" => [
        {"type" => "if",
         "condition" => {"key" => "bad", "equals" => true},
         "then" => [{"id" => "issue_refund"}]}
      ])
      validator = Workflow::Ai::PlanValidator.new(registry: registry)
      validation = validator.validate(plan, initial_keys: [:bad, :order])

      gate = described_class.new(registry: registry)
      result = gate.check(validation, plan)

      expect(result).to be_required
      expect(result.pending_steps).to eq([:issue_refund])
    end

    it "finds approval steps inside iterate" do
      plan = Workflow::Ai::Plan.new("steps" => [
        {"type" => "iterate",
         "collection" => "orders",
         "steps" => [{"id" => "issue_refund"}]}
      ])
      validator = Workflow::Ai::PlanValidator.new(registry: registry)
      validation = validator.validate(plan, initial_keys: [:orders, :order])

      gate = described_class.new(registry: registry)
      result = gate.check(validation, plan)

      expect(result).to be_required
      expect(result.pending_steps).to eq([:issue_refund])
    end
  end
end
