# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Ai::DryRunRunner do
  let(:action) { ->(ctx) { ctx } }

  let(:registry) do
    registry = Workflow::Ai::CapabilityRegistry.new
    registry.register(Workflow::Ai::Capability.new(:find_order,
      action: action, description: "Find order",
      expects: [:order_id], promises: [:order],
      side_effects: [:db_read], risk: :low,
      rollback_available: true))
    registry.register(Workflow::Ai::Capability.new(:issue_refund,
      action: action, description: "Issue refund",
      expects: [:order], promises: [:refund],
      side_effects: [:money_movement], risk: :high,
      requires_approval: true, rollback_available: true))
    registry.register(Workflow::Ai::Capability.new(:send_email,
      action: action, description: "Send email",
      expects: [:email_address], promises: [],
      side_effects: [:email], risk: :low,
      requires_approval: false, rollback_available: false))
    registry
  end

  let(:plan) { Workflow::Ai::Plan.new("steps" => steps) }

  describe "#analyze" do
    context "valid linear plan" do
      let(:steps) do
        [{"id" => "find_order"}, {"id" => "issue_refund"}]
      end

      it "lists all steps with their metadata" do
        runner = described_class.new(registry: registry)
        report = runner.analyze(plan, initial_keys: [:order_id])

        expect(report[:steps].length).to eq(2)
        expect(report[:steps][0][:id]).to eq(:find_order)
        expect(report[:steps][1][:id]).to eq(:issue_refund)
      end

      it "reports side effects across all steps" do
        runner = described_class.new(registry: registry)
        report = runner.analyze(plan, initial_keys: [:order_id])

        expect(report[:side_effects]).to include(:db_read, :money_movement)
      end

      it "reports risks" do
        runner = described_class.new(registry: registry)
        report = runner.analyze(plan, initial_keys: [:order_id])

        expect(report[:risks]).to include(:low, :high)
      end

      it "reports approval requirements" do
        runner = described_class.new(registry: registry)
        report = runner.analyze(plan, initial_keys: [:order_id])

        expect(report[:approvals_required]).to eq([:issue_refund])
      end

      it "reports rollback availability" do
        runner = described_class.new(registry: registry)
        report = runner.analyze(plan, initial_keys: [:order_id])

        expect(report[:rollback_available]).to eq([:find_order, :issue_refund])
      end

      it "reports empty missing_keys" do
        runner = described_class.new(registry: registry)
        report = runner.analyze(plan, initial_keys: [:order_id])

        expect(report[:missing_keys]).to be_empty
      end
    end

    context "plan with missing keys" do
      let(:steps) do
        [{"id" => "find_order"}]
      end

      it "reports missing keys" do
        runner = described_class.new(registry: registry)
        report = runner.analyze(plan, initial_keys: [])

        expect(report[:missing_keys]).to include(
          hash_including(step: :find_order, missing: [:order_id])
        )
      end
    end

    context "plan with unknown capability" do
      let(:steps) do
        [{"id" => "nonexistent"}]
      end

      it "reports unknown capabilities as errors" do
        runner = described_class.new(registry: registry)
        report = runner.analyze(plan)

        expect(report[:errors]).to include(/Unknown capability: nonexistent/)
      end
    end

    context "plan with control flow" do
      let(:steps) do
        [{"type" => "if", "condition" => {"key" => "order", "equals" => "bad"},
          "then" => [{"id" => "issue_refund"}]}]
      end

      it "analyzes nested steps" do
        runner = described_class.new(registry: registry)
        report = runner.analyze(plan, initial_keys: [:order_id])

        expect(report[:steps].length).to eq(1)
        expect(report[:side_effects]).to include(:money_movement)
      end
    end

    context "empty plan" do
      let(:steps) { [] }

      it "returns empty report" do
        runner = described_class.new(registry: registry)
        report = runner.analyze(plan)

        expect(report[:steps]).to eq([])
        expect(report[:side_effects]).to eq([])
        expect(report[:risks]).to eq([])
        expect(report[:approvals_required]).to eq([])
        expect(report[:rollback_available]).to eq([])
        expect(report[:missing_keys]).to eq([])
        expect(report[:errors]).to eq([])
      end
    end

    context "if_else branching" do
      let(:steps) do
        [{"type" => "if_else",
          "condition" => {"key" => "status", "equals" => "bad"},
          "then" => [{"id" => "issue_refund"}],
          "else" => [{"id" => "find_order"}]}]
      end

      it "analyzes both branches" do
        runner = described_class.new(registry: registry)
        report = runner.analyze(plan, initial_keys: [:order_id, :order])

        expect(report[:steps].length).to eq(2)
        expect(report[:side_effects]).to include(:money_movement, :db_read)
      end
    end

    context "iterate" do
      let(:steps) do
        [{"type" => "iterate",
          "collection" => "orders",
          "as" => "item",
          "steps" => [{"id" => "find_order"}]}]
      end

      it "provides item key to inner steps" do
        runner = described_class.new(registry: registry)
        report = runner.analyze(plan, initial_keys: [:orders])

        # find_order expects :order_id, but we only gave :orders and item key :item
        expect(report[:missing_keys].length).to eq(1)
        expect(report[:missing_keys][0][:step]).to eq(:find_order)
        expect(report[:missing_keys][0][:missing]).not_to include(:item)
      end
    end

    context "step without rollback" do
      it "does not list step in rollback_available" do
        runner = described_class.new(registry: registry)
        plan = Workflow::Ai::Plan.new("steps" => [{"id" => "send_email"}])
        report = runner.analyze(plan, initial_keys: [:email_address])

        expect(report[:rollback_available]).not_to include(:send_email)
      end
    end

    context "nested control flow" do
      let(:steps) do
        [{"type" => "if",
          "condition" => {"key" => "needs_refund", "equals" => true},
          "then" => [
            {"type" => "iterate",
             "collection" => "refunds",
             "steps" => [{"id" => "issue_refund"}]}
          ]}]
      end

      it "analyzes deeply nested steps" do
        runner = described_class.new(registry: registry)
        report = runner.analyze(plan, initial_keys: [:needs_refund, :refunds, :order])

        expect(report[:steps].length).to eq(1)
        expect(report[:approvals_required]).to eq([:issue_refund])
      end
    end
  end
end
