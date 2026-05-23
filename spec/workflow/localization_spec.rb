# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Localization do
  describe Workflow::Localization::NullAdapter do
    it "passes messages through unchanged" do
      adapter = described_class.new
      expect(adapter.failure("Card declined", nil, {})).to eq("Card declined")
    end

    it "returns nil for nil message" do
      adapter = described_class.new
      expect(adapter.failure(nil, nil, {})).to be_nil
    end
    it "returns the exact same object as the input message" do
      adapter = described_class.new
      msg = "Card declined"
      expect(adapter.failure(msg, :an_action, {key: "val"})).to equal(msg)
    end
  end

  describe Workflow::Localization::HashAdapter do
    let(:catalog) do
      {
        "charge_card.failures.card_declined" => "Your card was declined",
        "charge_card.failures.gateway_timeout" => "Payment gateway timed out"
      }
    end

    it "resolves a known key" do
      adapter = described_class.new(catalog)
      expect(adapter.failure("charge_card.failures.card_declined", nil, {})).to eq("Your card was declined")
    end

    it "falls back to raw message for unknown key" do
      adapter = described_class.new(catalog)
      expect(adapter.failure("some.unknown.key", nil, {})).to eq("some.unknown.key")
    end

    it "returns nil for nil message" do
      adapter = described_class.new(catalog)
      expect(adapter.failure(nil, nil, {})).to be_nil
    end

    it "defaults catalog to empty hash when no argument given" do
      adapter = described_class.new
      expect(adapter.failure("any_key", nil, {})).to eq("any_key")
    end

    it "returns nil for nil message even when catalog has nil key" do
      adapter = described_class.new({nil => "not_this"})
      expect(adapter.failure(nil, nil, {})).to be_nil
    end

    it "returns known message from catalog" do
      adapter = described_class.new({"a" => "b"})
      expect(adapter.failure("a", nil, {})).to eq("b")
    end

    it "returns unknown message unchanged" do
      adapter = described_class.new({"a" => "b"})
      expect(adapter.failure("c", nil, {})).to eq("c")
    end
  end

  describe "configuration integration" do
    after do
      Workflow.instance_variable_set(:@configuration, nil)
    end

    it "configuration sets localization_adapter" do
      adapter = Workflow::Localization::HashAdapter.new({})
      Workflow.configure do |c|
        c.localization_adapter = adapter
      end
      expect(Workflow.configuration.localization_adapter).to equal(adapter)
    end
  end

  describe "fail! integration with localization" do
    before do
      Workflow.configure do |c|
        c.localization_adapter = Workflow::Localization::HashAdapter.new({
          "charge_card.failures.card_declined" => "Your card was declined"
        })
      end
    end

    after do
      Workflow.instance_variable_set(:@configuration, nil)
    end

    it "fail! translates message through adapter when configured" do
      ctx = Workflow::Context.new
      ctx.fail!("charge_card.failures.card_declined")
      expect(ctx.message).to eq("Your card was declined")
    end

    it "fail! passes through when adapter is nil" do
      Workflow.configure { |c| c.localization_adapter = nil }
      ctx = Workflow::Context.new
      ctx.fail!("Card declined")
      expect(ctx.message).to eq("Card declined")
    end
  end
end
