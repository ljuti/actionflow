# Actionflow

Actionflow is a Ruby workflow orchestration gem that combines
LightService-style context pipelines with explicit object composition and
constructor dependency injection. Build composable, testable business
workflows from ordinary Ruby objects.

## Installation

Add to your Gemfile:

```ruby
gem "actionflow"
```

Or install directly:

```bash
gem install actionflow
```

The gem is published on [Gemfury](https://gemfury.com). To use it with Bundler,
add Gemfury as a source in your Gemfile:

```ruby
source "https://gem.fury.io/ljuti/" do
  gem "actionflow"
end
```

Or configure it globally for all gems from this account:

```bash
bundle config gem.fury.io TOKEN_HERE
```

## Usage

### Define an action

```ruby
class ChargeCard
  include Workflow::Action

  expects :user, :amount
  promises :charge

  def initialize(payment_gateway:)
    @payment_gateway = payment_gateway
  end

  def call(ctx)
    ctx.charge = @payment_gateway.charge(ctx.user, ctx.amount)
  end
end
```

### Compose with an organizer

```ruby
class Checkout
  include Workflow::Organizer

  def initialize(charge_card:, send_receipt:)
    @charge_card = charge_card
    @send_receipt = send_receipt
  end

  def call(cart:, user:, amount:)
    with(cart: cart, user: user, amount: amount).reduce(
      @charge_card,
      @send_receipt
    )
  end
end
```

### Run it

```ruby
checkout = Checkout.new(
  charge_card: ChargeCard.new(payment_gateway: StripeGateway.new),
  send_receipt: SendReceipt.new(mailer: ReceiptMailer)
)

result = checkout.call(cart: cart, user: user, amount: 100)

if result.success?
  puts result[:charge]
else
  puts result.message
end
```

### Control flow

```ruby
with(input).reduce(
  fetch_items,
  reduce_if(->(ctx) { ctx.items.empty? }, [
    NotifyEmpty.new
  ]),
  iterate(:items, [
    ProcessItem.new
  ])
)
```

## Documentation

- [Developer Guide](docs/developer-guide.md) — full API reference
- [Architecture](docs/ARCHITECTURE.md) — system design and component relationships
- [Abstractions](docs/ABSTRACTIONS.md) — core domain types and invariants

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then
run `rake spec` to run the tests. You can also run `bin/console` for an
interactive prompt.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/ljuti/actionflow.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
