# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Testing::RSpecMatchers do
  include described_class

  let(:action_class) do
    Class.new do
      include Workflow::Action

      expects :user, :amount
      promises :charge

      def call(ctx)
      end
    end
  end

  describe "expect_keys" do
    it "passes when action expects all specified keys" do
      expect(action_class.new).to expect_keys(:user, :amount)
    end

    it "passes when checking against the class" do
      expect(action_class).to expect_keys(:user, :amount)
    end

    it "fails when a key is missing" do
      matcher = expect_keys(:user, :email)
      expect(matcher.matches?(action_class.new)).to be(false)
      expect(matcher.failure_message).to include("missing: [:email]")
    end

    it "fails when extra keys are expected" do
      matcher = expect_keys(:user)
      expect(matcher.matches?(action_class.new)).to be(false)
      expect(matcher.failure_message).to include("extra: [:amount]")
    end
  end

  describe "promise_keys" do
    it "passes when action promises all specified keys" do
      expect(action_class.new).to promise_keys(:charge)
    end

    it "passes when checking against the class" do
      expect(action_class).to promise_keys(:charge)
    end

    it "fails when a promised key is missing" do
      matcher = promise_keys(:charge, :receipt)
      expect(matcher.matches?(action_class.new)).to be(false)
      expect(matcher.failure_message).to include("missing: [:receipt]")
    end
  end

  describe "have_context_value" do
    it "passes when context has the key" do
      ctx = Workflow::Context.new(charge: 100)
      expect(ctx).to have_context_value(:charge)
    end

    it "fails when context lacks the key" do
      ctx = Workflow::Context.new
      matcher = have_context_value(:charge)
      expect(matcher.matches?(ctx)).to be(false)
      expect(matcher.failure_message).to include("have key :charge")
    end
  end
end
