# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Ai::Policy do
  let(:action) { ->(ctx) { ctx } }
  let(:ctx) { Workflow::Context.new(user_id: 1) }

  describe "block-based policy" do
    it "allows when block returns truthy" do
      policy = described_class.new { |agent:, action:, context:| true }
      expect(policy).to be_allowed(agent: "agent_1", action: action, context: ctx)
    end

    it "denies when block returns falsy" do
      policy = described_class.new { |agent:, action:, context:| false }
      expect(policy).not_to be_allowed(agent: "agent_1", action: action, context: ctx)
    end

    it "passes agent, action, and context to block" do
      received = nil
      policy = described_class.new { |**kwargs|
        received = kwargs
        true
      }
      policy.allowed?(agent: "agent_1", action: action, context: ctx)
      expect(received[:agent]).to eq("agent_1")
      expect(received[:action]).to eq(action)
      expect(received[:context]).to eq(ctx)
    end
  end

  describe "object-based policy" do
    it "calls allowed? on object that responds to it" do
      guard = Struct.new(:agents) {
        def allowed?(agent:, action:, context:)
          agents.include?(agent)
        end
      }.new(["agent_1"])

      policy = described_class.new(guard)
      expect(policy).to be_allowed(agent: "agent_1", action: action, context: ctx)
      expect(policy).not_to be_allowed(agent: "agent_2", action: action, context: ctx)
    end
  end

  describe "composite policy (AND)" do
    it "allows when all policies allow" do
      p1 = described_class.new { |agent:, **| agent == "agent_1" }
      p2 = described_class.new { |context:, **| context.key?(:user_id) }

      composite = described_class.new([p1, p2])
      expect(composite).to be_allowed(agent: "agent_1", action: action, context: ctx)
    end

    it "denies when any policy denies" do
      p1 = described_class.new { |agent:, **| agent == "agent_1" }
      p2 = described_class.new { |agent:, **| agent == "agent_2" }

      composite = described_class.new([p1, p2])
      expect(composite).not_to be_allowed(agent: "agent_1", action: action, context: ctx)
    end

    it "allows with empty policy list" do
      composite = described_class.new([])
      expect(composite).to be_allowed(agent: "agent_1", action: action, context: ctx)
    end
  end

  describe "deny_all / allow_all" do
    it "deny_all always denies" do
      policy = described_class.deny_all
      expect(policy).to be_a(described_class)
      expect(policy).not_to be_allowed(agent: "any", action: action, context: ctx)
    end

    it "allow_all always allows" do
      policy = described_class.allow_all
      expect(policy).to be_allowed(agent: "any", action: action, context: ctx)
    end

    it "deny_all returns false explicitly" do
      policy = described_class.deny_all
      expect(policy.allowed?(agent: "any", action: action, context: ctx)).to eq(false)
    end
  end

  describe "no-arg constructor" do
    it "defaults to allow-all with no policies" do
      policy = described_class.new
      expect(policy).to be_allowed(agent: "any", action: action, context: ctx)
    end
  end
end
