# frozen_string_literal: true

require "actionflow"

RSpec.describe "Introspection API" do
  describe "Action.describe" do
    it "returns contract metadata for an action instance" do
      action = Class.new do
        include Workflow::Action

        expects :user, :amount
        promises :charge

        def call(ctx)
        end
      end.new

      result = action.describe
      expect(result).to eq(
        name: action.class.name,
        expects: [:user, :amount],
        promises: [:charge]
      )
    end

    it "returns empty arrays for actions with no contract" do
      action = Class.new do
        include Workflow::Action

        def call(ctx)
        end
      end.new

      result = action.describe
      expect(result).to eq(
        name: action.class.name,
        expects: [],
        promises: []
      )
    end
  end

  describe "Organizer.describe" do
    let(:validate_cart) do
      Class.new do
        include Workflow::Action

        expects :cart

        def self.name
          "ValidateCart"
        end

        def call(ctx)
        end
      end.new
    end

    let(:charge_card) do
      Class.new do
        include Workflow::Action

        expects :user, :amount
        promises :charge

        def self.name
          "ChargeCard"
        end

        def call(ctx)
        end
      end.new
    end

    it "returns metadata for all steps" do
      organizer = Class.new do
        include Workflow::Organizer
      end.new

      result = organizer.describe([validate_cart, charge_card])
      expect(result).to eq([
        {name: "ValidateCart", expects: [:cart], promises: []},
        {name: "ChargeCard", expects: [:user, :amount], promises: [:charge]}
      ])
    end

    it "skips non-action callables" do
      organizer = Class.new do
        include Workflow::Organizer
      end.new

      lambda_step = ->(ctx) { ctx }

      result = organizer.describe([validate_cart, lambda_step])
      expect(result).to eq([
        {name: "ValidateCart", expects: [:cart], promises: []},
        {name: "Proc", expects: [], promises: []}
      ])
    end
  end
end
