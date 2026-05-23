# frozen_string_literal: true

require "actionflow"

RSpec.describe "Integration: full workflow" do
  before do
    stub_const("ValidateCart", Class.new do
      include Workflow::Action

      expects :cart

      def call(ctx)
        ctx.fail!("Cart is empty") if ctx[:cart].nil? || ctx[:cart].empty?
      end
    end)

    stub_const("ChargeCard", Class.new do
      include Workflow::Action

      expects :user, :amount
      promises :charge

      def initialize(payment_gateway:)
        @payment_gateway = payment_gateway
      end

      def call(ctx)
        result = @payment_gateway.charge(ctx[:user], ctx[:amount])
        if result[:success]
          ctx[:charge] = result[:charge]
        else
          ctx.fail!("Card declined", error_code: :card_declined)
        end
      end

      def rollback(ctx)
        @payment_gateway.refund(ctx[:charge]) if ctx.key?(:charge)
      end
    end)

    stub_const("SendReceipt", Class.new do
      include Workflow::Action

      expects :user, :charge
      promises :receipt_sent

      def initialize(mailer:)
        @mailer = mailer
      end

      def call(ctx)
        @mailer.send_receipt(ctx[:user], ctx[:charge])
        ctx[:receipt_sent] = true
      end
    end)

    stub_const("Checkout", Class.new do
      include Workflow::Organizer

      def initialize(validate_cart:, charge_card:, send_receipt:)
        @validate_cart = validate_cart
        @charge_card = charge_card
        @send_receipt = send_receipt
      end

      def call(cart:, user:, amount:)
        with(cart: cart, user: user, amount: amount).reduce(
          @validate_cart,
          @charge_card,
          @send_receipt
        )
      end
    end)
  end

  it "runs three actions in sequence with data flowing through" do
    gateway = double("gateway")
    allow(gateway).to receive(:charge).and_return({success: true, charge: "ch_123"})
    mailer = double("mailer")
    allow(mailer).to receive(:send_receipt)

    checkout = Checkout.new(
      validate_cart: ValidateCart.new,
      charge_card: ChargeCard.new(payment_gateway: gateway),
      send_receipt: SendReceipt.new(mailer: mailer)
    )

    result = checkout.call(cart: ["item"], user: "Alice", amount: 100)

    expect(result).to be_success
    expect(result[:charge]).to eq("ch_123")
    expect(result[:receipt_sent]).to eq(true)
    expect(mailer).to have_received(:send_receipt).with("Alice", "ch_123")
  end

  it "supports dependency-injected actions" do
    gateway = double("gateway")
    allow(gateway).to receive(:charge).and_return({success: true, charge: "ch_abc"})
    mailer = double("mailer")
    allow(mailer).to receive(:send_receipt)

    checkout = Checkout.new(
      validate_cart: ValidateCart.new,
      charge_card: ChargeCard.new(payment_gateway: gateway),
      send_receipt: SendReceipt.new(mailer: mailer)
    )

    result = checkout.call(cart: ["item"], user: "Bob", amount: 50)
    expect(gateway).to have_received(:charge).with("Bob", 50)
  end

  it "failure stops the pipeline" do
    gateway = double("gateway")
    allow(gateway).to receive(:charge)
    mailer = double("mailer")
    allow(mailer).to receive(:send_receipt)

    checkout = Checkout.new(
      validate_cart: ValidateCart.new,
      charge_card: ChargeCard.new(payment_gateway: gateway),
      send_receipt: SendReceipt.new(mailer: mailer)
    )

    result = checkout.call(cart: [], user: "Alice", amount: 100)

    expect(result).to be_failure
    expect(result.message).to eq("Cart is empty")
    expect(gateway).not_to have_received(:charge)
    expect(mailer).not_to have_received(:send_receipt)
  end

  it "fail! message propagates to result" do
    gateway = double("gateway")
    allow(gateway).to receive(:charge).and_return({success: false})

    checkout = Checkout.new(
      validate_cart: ValidateCart.new,
      charge_card: ChargeCard.new(payment_gateway: gateway),
      send_receipt: SendReceipt.new(mailer: double("mailer"))
    )

    result = checkout.call(cart: ["item"], user: "Alice", amount: 100)
    expect(result.message).to eq("Card declined")
    expect(result.error_code).to eq(:card_declined)
  end

  it "lambda as step works" do
    organizer = Class.new {
      include Workflow::Organizer
    }.new

    result = organizer.with(x: 5).reduce(
      ->(ctx) { ctx[:doubled] = ctx[:x] * 2; ctx }
    )

    expect(result[:doubled]).to eq(10)
  end

  it "nested organizer used as callable step" do
    inner_class = Class.new {
      include Workflow::Organizer

      def call(data)
        with(data).reduce(
          ->(ctx) { ctx[:from_inner] = true; ctx }
        )
      end
    }

    outer = Class.new {
      include Workflow::Organizer
    }.new

    inner = inner_class.new

    result = outer.with(x: 1).reduce(
      ->(ctx) { ctx[:x] += 1; ctx },
      ->(ctx) { inner_result = inner.call(ctx.to_h); ctx[:from_inner] = inner_result[:from_inner]; ctx }
    )

    expect(result[:x]).to eq(2)
    expect(result[:from_inner]).to eq(true)
  end
end
