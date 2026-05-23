# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Ai::CapabilityRegistry do
  let(:action) { ->(ctx) { ctx } }

  it "registers and fetches by id" do
    registry = described_class.new
    cap = Workflow::Ai::Capability.new(:find_order, action: action, description: "Find", expects: [], promises: [])
    registry.register(cap)
    expect(registry.fetch(:find_order)).to equal(cap)
  end

  it "raises on unknown id" do
    registry = described_class.new
    expect { registry.fetch(:unknown) }.to raise_error(KeyError)
  end

  it "descriptions returns all sanitized descriptions" do
    registry = described_class.new
    cap1 = Workflow::Ai::Capability.new(:find_order, action: action, description: "Find order", expects: [:order_id], promises: [:order], side_effects: [], risk: :low)
    cap2 = Workflow::Ai::Capability.new(:issue_refund, action: action, description: "Issue refund", expects: [:order], promises: [:refund], side_effects: [:money_movement], risk: :high)

    registry.register(cap1)
    registry.register(cap2)

    descs = registry.descriptions
    expect(descs.length).to eq(2)
    expect(descs.all? { |d| d.is_a?(Hash) }).to eq(true)
    expect(descs.none? { |d| d.key?(:action) }).to eq(true)
  end

  it "duplicate id overwrites previous registration" do
    registry = described_class.new
    cap1 = Workflow::Ai::Capability.new(:find, action: action, description: "First", expects: [], promises: [])
    cap2 = Workflow::Ai::Capability.new(:find, action: action, description: "Second", expects: [], promises: [])

    registry.register(cap1)
    registry.register(cap2)

    expect(registry.fetch(:find).description).to eq("Second")
  end
end
