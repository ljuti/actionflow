# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Ai::AuditTrail do
  let(:action) { ->(ctx) { ctx } }

  describe "recording execution" do
    it "records agent_id and user_id" do
      audit = described_class.new(agent_id: "agent_123", user_id: "user_456")
      record = audit.finalize(plan: nil, validation: nil, result: nil)

      expect(record[:agent_id]).to eq("agent_123")
      expect(record[:user_id]).to eq("user_456")
    end

    it "records plan steps" do
      plan = Workflow::Ai::Plan.new("steps" => [{"id" => "find_order"}])
      audit = described_class.new(agent_id: "a", user_id: "u")
      record = audit.finalize(plan: plan, validation: nil, result: nil)

      expect(record[:plan]).to eq(plan)
    end

    it "records validation result" do
      registry = Workflow::Ai::CapabilityRegistry.new
      registry.register(Workflow::Ai::Capability.new(:find_order,
        action: action, description: "Find",
        expects: [], promises: [:order]))
      plan = Workflow::Ai::Plan.new("steps" => [{"id" => "find_order"}])
      validator = Workflow::Ai::PlanValidator.new(registry: registry)
      validation = validator.validate(plan)

      audit = described_class.new(agent_id: "a", user_id: "u")
      record = audit.finalize(plan: plan, validation: validation, result: nil)

      expect(record[:validation_result]).to eq(validation)
    end

    it "records the execution result" do
      result = Workflow::Context.new(order_id: 1)
      audit = described_class.new(agent_id: "a", user_id: "u")
      record = audit.finalize(plan: nil, validation: nil, result: result)

      expect(record[:result]).to eq(result)
    end

    it "tracks executed steps" do
      audit = described_class.new(agent_id: "a", user_id: "u")
      audit.record_step(:find_order, :executed)
      audit.record_step(:issue_refund, :executed)

      record = audit.finalize(plan: nil, validation: nil, result: nil)
      expect(record[:executed_steps]).to eq(%i[find_order issue_refund])
    end

    it "tracks skipped steps" do
      audit = described_class.new(agent_id: "a", user_id: "u")
      audit.record_step(:send_email, :skipped)

      record = audit.finalize(plan: nil, validation: nil, result: nil)
      expect(record[:skipped_steps]).to eq([:send_email])
    end

    it "tracks failed steps" do
      audit = described_class.new(agent_id: "a", user_id: "u")
      audit.record_step(:charge_card, :failed)

      record = audit.finalize(plan: nil, validation: nil, result: nil)
      expect(record[:failures]).to eq([:charge_card])
    end

    it "tracks approvals" do
      audit = described_class.new(agent_id: "a", user_id: "u")
      audit.record_approval(:issue_refund, approved_by: "admin_1")

      record = audit.finalize(plan: nil, validation: nil, result: nil)
      expect(record[:approvals]).to eq([{step: :issue_refund, approved_by: "admin_1"}])
    end

    it "produces a complete record with timestamps" do
      audit = described_class.new(agent_id: "a", user_id: "u")
      record = audit.finalize(plan: nil, validation: nil, result: nil)

      expect(record[:started_at]).to be_a(Time)
      expect(record[:finished_at]).to be_a(Time)
      expect(record[:finished_at]).to be >= record[:started_at]
    end

    it "returns independent copies of tracked arrays" do
      audit = described_class.new(agent_id: "a", user_id: "u")
      audit.record_step(:step_1, :executed)
      audit.record_step(:step_1b, :skipped)
      audit.record_step(:step_2, :failed)
      audit.record_approval(:step_3, approved_by: "admin")

      record = audit.finalize(plan: nil, validation: nil, result: nil)
      record[:executed_steps] << :extra
      record[:skipped_steps] << :extra
      record[:failures] << :extra
      record[:approvals] << {step: :extra, approved_by: "nobody"}

      record2 = audit.finalize(plan: nil, validation: nil, result: nil)
      expect(record2[:executed_steps]).to eq([:step_1])
      expect(record2[:skipped_steps]).to eq([:step_1b])
      expect(record2[:failures]).to eq([:step_2])
      expect(record2[:approvals]).to eq([{step: :step_3, approved_by: "admin"}])
    end
  end
end
