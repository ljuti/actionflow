# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Context do
  describe "initialization" do
    it "initializes with hash data" do
      ctx = described_class.new(foo: "bar")
      expect(ctx[:foo]).to eq("bar")
    end

    it "initializes with empty hash" do
      ctx = described_class.new
      expect(ctx.keys).to eq([])
    end

    it "symbolizes string keys on init" do
      ctx = described_class.new("foo" => 1)
      expect(ctx[:foo]).to eq(1)
    end

    it "initializes skip_remaining as exactly false" do
      ctx = described_class.new
      expect(ctx.skip_remaining?).to be(false)
    end

    it "initializes skip_all_remaining as exactly false" do
      ctx = described_class.new
      expect(ctx.skip_all_remaining?).to be(false)
    end

    it "initializes message as nil" do
      ctx = described_class.new
      expect(ctx.message).to be_nil
    end

    it "initializes error_code as nil" do
      ctx = described_class.new
      expect(ctx.error_code).to be_nil
    end

    it "converts non-hash input via to_h" do
      struct = Struct.new(:a).new(1)
      ctx = described_class.new(struct)
      expect(ctx[:a]).to eq(1)
    end

    it "is not stop_processing on fresh context" do
      ctx = described_class.new
      expect(ctx).not_to be_stop_processing
    end
  end

  describe "[]" do
    it "reads a value by symbol key" do
      ctx = described_class.new(a: 1)
      expect(ctx[:a]).to eq(1)
    end

    it "returns nil for missing keys" do
      ctx = described_class.new
      expect(ctx[:missing]).to be_nil
    end

    it "resolves aliases when reading" do
      ctx = described_class.new(original: 42)
      ctx.assign_aliases(alias: :original)
      expect(ctx[:alias]).to eq(42)
    end
  end

  describe "[]=" do
    it "writes a value" do
      ctx = described_class.new
      ctx[:x] = 42
      expect(ctx[:x]).to eq(42)
    end
  end

  describe "#key?" do
    it "returns true for a present key" do
      ctx = described_class.new(foo: 1)
      expect(ctx.key?(:foo)).to eq(true)
    end

    it "returns false for an absent key" do
      ctx = described_class.new
      expect(ctx.key?(:missing)).to eq(false)
    end

    it "resolves aliases" do
      ctx = described_class.new(original: 1)
      ctx.assign_aliases(alias: :original)
      expect(ctx.key?(:alias)).to eq(true)
    end

    it "coerces string keys to symbols" do
      ctx = described_class.new(foo: 1)
      expect(ctx.key?("foo")).to eq(true)
    end
  end

  describe "#keys" do
    it "returns all symbol keys" do
      ctx = described_class.new(a: 1, b: 2)
      expect(ctx.keys).to contain_exactly(:a, :b)
    end
  end

  describe "#to_h" do
    it "returns a shallow copy of data" do
      ctx = described_class.new(a: 1)
      h = ctx.to_h
      expect(h).to eq({a: 1})
      expect(h).not_to equal(ctx.instance_variable_get(:@data))
    end

    it "modifying returned hash does not affect context" do
      ctx = described_class.new(a: 1)
      ctx.to_h[:a] = 999
      expect(ctx[:a]).to eq(1)
    end
  end

  describe "#success? / #failure?" do
    it "new context is successful" do
      ctx = described_class.new
      expect(ctx).to be_success
      expect(ctx).not_to be_failure
    end
  end

  describe "#fail!" do
    it "marks context as failed" do
      ctx = described_class.new
      ctx.fail!("boom")
      expect(ctx).to be_failure
      expect(ctx).not_to be_success
    end

    it "sets the message" do
      ctx = described_class.new
      ctx.fail!("boom")
      expect(ctx.message).to eq("boom")
    end

    it "sets the error_code" do
      ctx = described_class.new
      ctx.fail!("boom", error_code: :timeout)
      expect(ctx.error_code).to eq(:timeout)
    end

    it "works without arguments" do
      ctx = described_class.new
      ctx.fail!
      expect(ctx.message).to be_nil
      expect(ctx.error_code).to be_nil
    end

    it "makes stop_processing? true" do
      ctx = described_class.new
      ctx.fail!
      expect(ctx).to be_stop_processing
    end

    it "passes options to localization adapter" do
      adapter = instance_double(Workflow::Localization::NullAdapter)
      allow(adapter).to receive(:failure).with("boom", nil, {scope: :payment}).and_return("translated")
      allow(Workflow.configuration).to receive(:localization_adapter).and_return(adapter)

      ctx = described_class.new
      ctx.fail!("boom", scope: :payment)
      expect(ctx.message).to eq("translated")
    end
  end

  describe "#succeed!" do
    it "sets success and message" do
      ctx = described_class.new
      ctx.succeed!("ok")
      expect(ctx).to be_success
      expect(ctx.message).to eq("ok")
    end

    it "works without arguments" do
      ctx = described_class.new
      ctx.succeed!
      expect(ctx).to be_success
      expect(ctx.message).to be_nil
    end

    it "restores success from failure state" do
      ctx = described_class.new
      ctx.fail!("bad")
      expect(ctx).to be_failure
      ctx.succeed!("ok")
      expect(ctx).to be_success
    end
  end

  describe "#skip_remaining!" do
    it "sets the message" do
      ctx = described_class.new
      ctx.skip_remaining!("skip")
      expect(ctx.message).to eq("skip")
    end

    it "does not mark failure" do
      ctx = described_class.new
      ctx.skip_remaining!
      expect(ctx).to be_success
    end

    it "makes stop_processing? true via skip_remaining?" do
      ctx = described_class.new
      ctx.skip_remaining!
      expect(ctx).to be_skip_remaining
      expect(ctx).to be_stop_processing
    end
  end

  describe "#skip_all_remaining!" do
    it "makes stop_processing? true via skip_all_remaining?" do
      ctx = described_class.new
      ctx.skip_all_remaining!("all done")
      expect(ctx).to be_skip_all_remaining
      expect(ctx).to be_stop_processing
      expect(ctx.message).to eq("all done")
    end

    it "does not mark failure" do
      ctx = described_class.new
      ctx.skip_all_remaining!
      expect(ctx).to be_success
    end
  end

  describe "#reset_skip_remaining!" do
    it "clears skip_remaining flag" do
      ctx = described_class.new
      ctx.skip_remaining!
      ctx.reset_skip_remaining!
      expect(ctx).not_to be_skip_remaining
    end

    it "clears message" do
      ctx = described_class.new
      ctx.skip_remaining!("msg")
      ctx.reset_skip_remaining!
      expect(ctx.message).to be_nil
    end

    it "does not change success" do
      ctx = described_class.new
      ctx.skip_remaining!
      ctx.reset_skip_remaining!
      expect(ctx).to be_success
    end

    it "does not clear skip_all_remaining" do
      ctx = described_class.new
      ctx.skip_all_remaining!
      ctx.reset_skip_remaining!
      expect(ctx).to be_skip_all_remaining
    end
  end

  describe "#assign_aliases" do
    it "maps alias key to original key for reading" do
      ctx = described_class.new(original: 42)
      ctx.assign_aliases(alias: :original)
      expect(ctx[:alias]).to eq(42)
    end

    it "maps alias key to original key for writing" do
      ctx = described_class.new
      ctx.assign_aliases(alias: :original)
      ctx[:alias] = 99
      expect(ctx[:original]).to eq(99)
    end

    it "resolves aliases in key?" do
      ctx = described_class.new(original: 1)
      ctx.assign_aliases(alias: :original)
      expect(ctx.key?(:alias)).to eq(true)
    end

    it "symbolizes string keys and values" do
      ctx = described_class.new
      ctx.assign_aliases("alias" => "original")
      ctx[:alias] = 42
      expect(ctx[:original]).to eq(42)
    end
  end

  describe "#fail_with_rollback!" do
    it "raises FailWithRollback" do
      ctx = described_class.new
      expect { ctx.fail_with_rollback!("Payment failed") }.to raise_error(Workflow::FailWithRollback)
    end

    it "marks failure and sets message" do
      ctx = described_class.new
      begin
        ctx.fail_with_rollback!("Payment failed")
      rescue
        nil
      end
      expect(ctx).to be_failure
      expect(ctx.message).to eq("Payment failed")
    end

    it "sets error_code" do
      ctx = described_class.new
      begin
        ctx.fail_with_rollback!("err", error_code: :gateway_timeout)
      rescue
        nil
      end
      expect(ctx.error_code).to eq(:gateway_timeout)
    end

    it "works without arguments" do
      ctx = described_class.new
      expect { ctx.fail_with_rollback! }.to raise_error(Workflow::FailWithRollback)
      expect(ctx).to be_failure
      expect(ctx.message).to be_nil
    end
  end

  describe "metadata accessors" do
    it "has nil current_step by default" do
      ctx = described_class.new
      expect(ctx.current_step).to be_nil
    end

    it "allows setting current_step" do
      ctx = described_class.new
      step = double("step")
      ctx.current_step = step
      expect(ctx.current_step).to eq(step)
    end

    it "has nil organized_by by default" do
      ctx = described_class.new
      expect(ctx.organized_by).to be_nil
    end

    it "allows setting organized_by" do
      ctx = described_class.new
      organizer = double("organizer")
      ctx.organized_by = organizer
      expect(ctx.organized_by).to eq(organizer)
    end
  end
end
