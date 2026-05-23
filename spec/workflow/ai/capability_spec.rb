# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Ai::Capability do
  let(:action) do
    Class.new {
      include Workflow::Action

      expects :order_id
      promises :order

      def call(ctx)
        ctx[:order] = {id: ctx[:order_id]}
      end
    }.new
  end

  it "wraps action with metadata" do
    cap = described_class.new(
      :find_order,
      action: action,
      description: "Finds an order by ID",
      expects: [:order_id],
      promises: [:order],
      side_effects: [],
      risk: :low
    )

    expect(cap.id).to eq(:find_order)
    expect(cap.description).to eq("Finds an order by ID")
    expect(cap.expects).to eq([:order_id])
    expect(cap.promises).to eq([:order])
    expect(cap.side_effects).to eq([])
    expect(cap.risk).to eq(:low)
  end

  it "exposes requires_approval and rollback_available" do
    cap = described_class.new(
      :issue_refund,
      action: action,
      description: "Issues a refund",
      expects: [:order],
      promises: [:refund],
      side_effects: [:money_movement],
      requires_approval: true,
      rollback_available: true,
      risk: :high
    )

    expect(cap.requires_approval).to eq(true)
    expect(cap.rollback_available).to eq(true)
  end

  it "defaults side_effects to empty array" do
    cap = described_class.new(
      :find_order,
      action: action,
      description: "Find",
      expects: [],
      promises: []
    )

    expect(cap.side_effects).to eq([])
  end

  it "defaults risk to :low" do
    cap = described_class.new(
      :find_order,
      action: action,
      description: "Find",
      expects: [],
      promises: []
    )

    expect(cap.risk).to eq(:low)
  end

  it "defaults requires_approval to false" do
    cap = described_class.new(
      :find_order,
      action: action,
      description: "Find",
      expects: [],
      promises: []
    )

    expect(cap.requires_approval).to eq(false)
  end

  it "defaults rollback_available to false" do
    cap = described_class.new(
      :find_order,
      action: action,
      description: "Find",
      expects: [],
      promises: []
    )

    expect(cap.rollback_available).to eq(false)
  end

  it "to_description returns sanitized JSON-safe hash" do
    cap = described_class.new(
      :find_order,
      action: action,
      description: "Finds an order",
      expects: [:order_id],
      promises: [:order],
      side_effects: [],
      risk: :low
    )

    desc = cap.to_description
    expect(desc).to eq({
      id: :find_order,
      description: "Finds an order",
      expects: [:order_id],
      promises: [:order],
      side_effects: [],
      risk: :low,
      requires_approval: false,
      rollback_available: false
    })

    # Action object must not leak
    expect(desc).not_to have_key(:action)
  end

  it "to_description includes all fields with non-default values" do
    cap = described_class.new(
      :refund,
      action: action,
      description: "Refund order",
      expects: [:order],
      promises: [:refund],
      side_effects: [:money_movement],
      risk: :high,
      requires_approval: true,
      rollback_available: true
    )

    desc = cap.to_description
    expect(desc[:id]).to eq(:refund)
    expect(desc[:description]).to eq("Refund order")
    expect(desc[:expects]).to eq([:order])
    expect(desc[:promises]).to eq([:refund])
    expect(desc[:side_effects]).to eq([:money_movement])
    expect(desc[:risk]).to eq(:high)
    expect(desc[:requires_approval]).to eq(true)
    expect(desc[:rollback_available]).to eq(true)
  end

  it "stores action exactly as given" do
    cap = described_class.new(
      :find_order,
      action: action,
      description: "Find",
      expects: [],
      promises: []
    )

    expect(cap.action).to equal(action)
  end
end
