# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::ActionMetadata do
  describe "default initialization" do
    subject(:metadata) { described_class.new }

    it "has empty expected_keys" do
      expect(metadata.expected_keys).to eq([])
    end

    it "has empty promised_keys" do
      expect(metadata.promised_keys).to eq([])
    end

    it "has empty optional_keys" do
      expect(metadata.optional_keys).to eq([])
    end

    it "has empty defaults" do
      expect(metadata.defaults).to eq({})
    end
  end

  describe "initialization with keyword args" do
    subject(:metadata) do
      described_class.new(
        expected_keys: [:user, :amount],
        promised_keys: [:charge],
        optional_keys: [:note],
        defaults: {flag: true}
      )
    end

    it "returns expected_keys as an Array of Symbols" do
      expect(metadata.expected_keys).to eq(%i[user amount])
    end

    it "returns promised_keys as an Array of Symbols" do
      expect(metadata.promised_keys).to eq(%i[charge])
    end

    it "returns optional_keys as an Array of Symbols" do
      expect(metadata.optional_keys).to eq(%i[note])
    end

    it "returns defaults as a Hash" do
      expect(metadata.defaults).to eq({flag: true})
    end
  end

  describe "mutability" do
    it "allows appending to expected_keys" do
      metadata = described_class.new
      metadata.expected_keys << :order
      expect(metadata.expected_keys).to eq([:order])
    end

    it "allows appending to promised_keys" do
      metadata = described_class.new
      metadata.promised_keys << :result
      expect(metadata.promised_keys).to eq([:result])
    end

    it "allows setting defaults" do
      metadata = described_class.new
      metadata.defaults[:flag] = true
      expect(metadata.defaults[:flag]).to eq(true)
    end
  end
end
