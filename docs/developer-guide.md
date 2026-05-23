# Developer Guide

Actionflow is a Ruby workflow orchestration gem that combines context-based
pipelines with explicit object composition and constructor dependency injection.

The core idea: **context carries business data, constructors carry service
dependencies, actions are objects, organizers compose objects, and the
framework owns the execution lifecycle.**

---

## Installation

Add to your Gemfile:

```ruby
gem "actionflow"
```

Or install directly:

```bash
gem install actionflow
```

All functionality lives under the `Workflow` namespace. The gem has zero
runtime dependencies.

```ruby
require "actionflow"
```

---

## Core Concepts

### Action

An action is a plain Ruby object that includes `Workflow::Action`. It declares
what it expects from the context, what it promises to produce, and implements
`#call(ctx)` with its business logic.

```ruby
class CalculateTax
  include Workflow::Action

  expects :order
  promises :tax

  def initialize(tax_client:)
    @tax_client = tax_client
  end

  def call(ctx)
    ctx.tax = @tax_client.calculate(ctx.order)
  end
end
```

**Key rules:**

- Dependencies (services, gateways, repos) go in the constructor.
- Business data goes in the context.
- `#call(ctx)` is the raw business method.
- `#execute(ctx)` runs the full framework lifecycle (contract checks, hooks).
- Optional: define `#rollback(ctx)` for compensation logic.

### Context

Context carries all business data through a workflow. It wraps a hash with
symbolized keys and tracks pipeline status.

```ruby
ctx = Workflow::Context.new(order_id: "ord_123", user: current_user)

ctx[:total]          # read
ctx[:total] = 99.95  # write
ctx.key?(:total)     # true
ctx.keys             # [:order_id, :user, :total]
ctx.to_h             # shallow copy

ctx.success?         # true initially
ctx.failure?         # false

ctx.fail!("Out of stock", error_code: :inventory_error)
ctx.fail!            # no args is fine too

ctx.succeed!("All good")

ctx.skip_remaining!("Skip the rest of this scope")
ctx.skip_all_remaining!("Skip everything")

ctx.stop_processing?  # true if failed or skipped
```

### Organizer

An organizer composes action objects into a workflow. It is also a plain
object — dependencies are injected through the constructor.

```ruby
class Checkout
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
end
```

Usage:

```ruby
checkout = Checkout.new(
  validate_cart: ValidateCart.new,
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

---

## Contracts: expects and promises

Every action declares its contract. The framework enforces it.

### expects

Keys that must be present in the context before `#call` runs. Missing keys
raise `Workflow::ExpectedKeysMissing`.

```ruby
expects :user, :amount
```

With a default value:

```ruby
expects :allow_failure, default: true
```

With a callable default (receives the context):

```ruby
expects :discount, default: ->(ctx) { ctx.user.loyalty_discount }
```

### promises

Keys that must be present in the context after `#call` runs on success.
Missing keys raise `Workflow::PromisedKeysMissing`.

```ruby
promises :charge, :receipt_id
```

Promised keys are **not** checked when the context has failed — the action
may have bailed out before setting them.

### Instance-specific contracts

Override `#workflow_metadata` on the instance for parameterized actions:

```ruby
class NormalizeField
  include Workflow::Action

  def initialize(from:, to:)
    @from = from
    @to = to
  end

  def workflow_metadata
    Workflow::ActionMetadata.new(
      expected_keys: [@from],
      promised_keys: [@to]
    )
  end

  def call(ctx)
    ctx[@to] = ctx[@from].strip.downcase
  end
end

normalizer = NormalizeField.new(from: :name, to: :normalized_name)
```

---

## Failure and Control Flow

### Controlled failure

```ruby
def call(ctx)
  ctx.fail!("Cart is empty") if ctx.cart.empty?
end
```

`fail!` stops the pipeline. Remaining actions are not executed. The context
is marked as failed (`failure?` returns `true`). The message and optional
`error_code` are available on the result.

### Rollback

Actions can define `#rollback(ctx)` for compensation. When an action calls
`ctx.fail_with_rollback!`, the framework runs rollback on all previously
executed steps in reverse order.

```ruby
class ChargeCard
  include Workflow::Action

  expects :user, :amount
  promises :charge

  def initialize(payment_gateway:)
    @payment_gateway = payment_gateway
  end

  def call(ctx)
    result = @payment_gateway.charge(ctx.user, ctx.amount)

    if result.success?
      ctx.charge = result.charge
    else
      ctx.fail!("Card declined", error_code: :card_declined)
    end
  end

  def rollback(ctx)
    @payment_gateway.refund(ctx.charge) if ctx.key?(:charge)
  end
end
```

Trigger:

```ruby
def call(ctx)
  ctx.fail_with_rollback!("Payment gateway timeout")
end
```

This raises `Workflow::FailWithRollback` internally. The reducer catches it
and runs rollbacks.

### Skipping

```ruby
ctx.skip_remaining!   # skip rest of current scope, stay successful
ctx.skip_all_remaining!  # skip all nested scopes, stay successful
```

Useful in control-flow steps where you want to bail out of a branch without
marking the whole workflow as failed.

---

## Control-Flow Steps

Steps are first-class objects that the reducer handles uniformly. You can
create them directly or use the convenience methods on any organizer.

### ReduceIf

Run steps only when a condition is true.

```ruby
reduce_if(->(ctx) { ctx.items.empty? }, [
  NotifyEmptyResult.new
])
```

### ReduceIfElse

Branch between two paths.

```ruby
reduce_if_else(
  ->(ctx) { ctx.amount < 50 },
  [ RetryPayment.new, SendSuccessNotice.new ],
  [ CreateSupportTask.new ]
)
```

### Iterate

Run steps for each item in a collection.

```ruby
iterate(:items, [
  ProcessItem.new
])
```

The item key is inferred from the collection key (`:items` → `:item`). Override
with `item_key:`:

```ruby
iterate(:orders, [ ProcessOrder.new ], item_key: :order)
```

### ReduceWhile

Run steps repeatedly while a condition is true.

```ruby
Workflow::Steps::ReduceWhile.new(
  ->(ctx) { ctx[:attempts] < 3 },
  [ RetryWithBackoff.new ]
)
```

### ReduceUntil

Run steps repeatedly until a condition is true.

```ruby
Workflow::Steps::ReduceUntil.new(
  ->(ctx) { ctx[:converged] == true },
  [ RefineEstimate.new ]
)
```

### ReduceCase

Branch on a value.

```ruby
Workflow::Steps::ReduceCase.new(
  ->(ctx) { ctx[:type] },
  {
    admin: [ LoadAdminDashboard.new ],
    user:  [ LoadUserDashboard.new ]
  }
)
```

### Execute

Wrap an inline block as a step.

```ruby
execute { |ctx| ctx[:timestamp] = Time.now; ctx }
```

### AddToContext

Inject key-value pairs into the context.

```ruby
Workflow::Steps::AddToContext.new(status: "pending", retry_count: 0)
```

### AddAliases

Register key aliases on the context.

```ruby
Workflow::Steps::AddAliases.new(name: :full_name)
```

After this, `ctx[:name]` resolves to `ctx[:full_name]`.

### WithCallback

Run steps, then store a callback for later invocation.

```ruby
Workflow::Steps::WithCallback.new(:on_complete,
  [ PrepareData.new ],     # run immediately
  [ SendNotification.new ] # stored as callback
)
```

The callback is available as `ctx[:on_complete]` and can be called later:

```ruby
ctx[:on_complete].call(ctx)
```

### Composition example

```ruby
with(input).reduce(
  fetch_items,
  reduce_if(->(ctx) { ctx.items.empty? }, [
    notify_empty_result
  ]),
  iterate(:items, [
    reduce_if_else(
      ->(ctx) { ctx.item.urgent? },
      [ process_urgent ],
      [ process_normal ]
    )
  ]),
  finalize
)
```

---

## Hooks

Hooks run before, after, or around each action execution. Register them on
the session returned by `with`.

### before_each

```ruby
with(input)
  .before_each(->(action, ctx) { logger.info("Running #{action.class.name}") })
  .reduce(steps)
```

### after_each

```ruby
with(input)
  .after_each(->(action, ctx) { audit_log.record(action, ctx) })
  .reduce(steps)
```

### around_each

Wraps the action execution. Must call `yield` (or `blk.call`) to continue.

```ruby
class LogDuration
  def initialize(logger:)
    @logger = logger
  end

  def call(action, ctx, &blk)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = blk.call
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    @logger.info(action: action.class.name, duration: elapsed)
    result
  end
end

with(input)
  .around_each(LogDuration.new(logger: my_logger))
  .reduce(steps)
```

Multiple around hooks compose naturally — outer wraps inner wraps action.

Hooks fire only for workflow actions (objects with `workflow_metadata`), not
for plain lambdas or control-flow steps.

---

## Configuration

Global configuration via `Workflow.configure`:

```ruby
Workflow.configure do |config|
  config.logger = Logger.new($stdout)
  config.strict_context_access = true
  config.localization_adapter = Workflow::Localization::HashAdapter.new(catalog)
end
```

| Setting | Default | Purpose |
|---|---|---|
| `logger` | `nil` | Logger instance for framework logging |
| `localization_adapter` | `nil` | Adapter for translating failure messages |
| `strict_context_access` | `false` | Raise on undefined dynamic context accessors |

---

## Localization

Adapter-based message translation for `fail!`.

### NullAdapter (default behavior)

Returns the message unchanged.

```ruby
Workflow::Localization::NullAdapter.new
```

### HashAdapter

Looks up messages in a hash catalog. Falls back to the raw message for
unknown keys.

```ruby
catalog = {
  "charge_card.failures.card_declined" => "Your card was declined",
  "charge_card.failures.gateway_timeout" => "Payment gateway timed out"
}

Workflow.configure do |config|
  config.localization_adapter = Workflow::Localization::HashAdapter.new(catalog)
end
```

When configured, `ctx.fail!` translates the message:

```ruby
ctx.fail!("charge_card.failures.card_declined")
ctx.message  # => "Your card was declined"
```

You can also provide your own adapter by implementing `#failure(message, action, options)`.

---

## Testing

### Direct action testing

Use `#execute` to run through the full lifecycle (contract checks, hooks):

```ruby
action = ChargeCard.new(payment_gateway: fake_gateway)
ctx = Workflow::Context.new(user: user, amount: 100)

result = action.execute(ctx)

expect(result).to be_success
expect(result[:charge]).to eq(expected_charge)
```

Use `#call` to bypass the framework and test raw business logic only.

### Organizer integration testing

```ruby
checkout = Checkout.new(
  validate_cart: ValidateCart.new,
  charge_card: ChargeCard.new(payment_gateway: fake_gateway),
  send_receipt: SendReceipt.new(mailer: fake_mailer)
)

result = checkout.call(cart: cart, user: user, amount: 100)

expect(result).to be_success
expect(result[:charge]).to be_present
```

### ContextFactory

Build the context as it would appear just before a specific action runs:

```ruby
ctx = Workflow::Testing::ContextFactory
  .make_from(checkout)
  .before(charge_card)
  .with(cart: cart, user: user, amount: 100)
```

Look up by instance or by class:

```ruby
.before(charge_card_instance)
.before(ChargeCard)
```

The `with` overrides let you inject specific values for the test, even
overriding values that preceding actions would have produced.

---

## Error Reference

| Error | Raised when |
|---|---|
| `Workflow::ExpectedKeysMissing` | An action's `expects` keys are not in the context |
| `Workflow::PromisedKeysMissing` | An action's `promises` keys are not set after `#call` |
| `Workflow::FailWithRollback` | Raised by `ctx.fail_with_rollback!` to trigger rollback |

---

## Architecture Overview

```
Organizer.with(data)
  │
  ▼
OrganizerSession
  .before_each / .after_each / .around_each
  │
  ▼
Reducer.reduce(ctx, steps)
  │
  ▼  per step:
  ├─ Workflow action? ──→ ActionRunner
  │    apply defaults
  │    verify expected keys
  │    before hooks
  │    around hooks → action.call(ctx)
  │    verify promised keys (on success)
  │    after hooks
  ├─ Control-flow step? ──→ step.call(ctx)
  ├─ Callable? ──→ step.call(ctx)
  │
  ▼
Context (final)
  .success? / .failure? / .message / .to_h
```

---

## AI-Agent Integration (Optional)

The `Workflow::Ai` namespace provides components for building AI-agent
workflow composition systems. These are optional and the core library works
without them.

### Capability

Wraps an action with metadata safe to expose to agents:

```ruby
Workflow::Ai::Capability.new(
  :find_order,
  action: FindOrder.new(order_repository: repo),
  description: "Finds an order by order_id.",
  expects: [:order_id],
  promises: [:order],
  side_effects: [],
  risk: :low
)
```

`to_description` returns a hash without the action reference.

### CapabilityRegistry

```ruby
registry = Workflow::Ai::CapabilityRegistry.new
registry.register(capability)
registry.fetch(:find_order)
registry.descriptions  # array of sanitized hashes for agent consumption
```

### Plan

Represents a structured workflow plan:

```ruby
plan = Workflow::Ai::Plan.new({
  "name" => "refund_order",
  "input" => {"order_id" => "ord_123"},
  "steps" => [
    {"id" => "find_order"},
    {"id" => "validate_order"},
    {"id" => "issue_refund"}
  ]
})
```

Supports linear steps, conditional (`"type" => "if"` / `"if_else"`), and
iteration (`"type" => "iterate"`).

### PlanValidator

Simulates key flow without executing. Checks that all step IDs are registered
and all expected keys are available at each step.

```ruby
validator = Workflow::Ai::PlanValidator.new(registry: registry)
result = validator.validate(plan, initial_keys: [:order_id])

result.safe?               # true / false
result.errors              # array of error strings
result.requires_approval?  # true if any high-risk step is included
```

### PlanCompiler

Compiles a validated plan into executable step objects:

```ruby
compiler = Workflow::Ai::PlanCompiler.new(registry: registry)
steps = compiler.compile(plan)
```

Linear steps resolve to action objects, conditionals to `ReduceIfElse`,
iterations to `Iterate`.

### DynamicOrganizer

Executes compiled plans using the standard runtime:

```ruby
organizer = Workflow::Ai::DynamicOrganizer.new(
  steps: compiled_steps,
  before_hooks: [AuditHook.new]
)

result = organizer.call(order_id: "ord_123")
```

---

## Design Principles

1. **Actions are ordinary objects.** Include a module, implement `#call`.
2. **Dependencies are constructor-injected.** Context is not a service locator.
3. **Context is for business data.** Never put gateways, mailers, or repos in it.
4. **`#call` is raw business logic.** `#execute` is framework execution. The
   pipeline calls `#execute`.
5. **Organizers compose objects.** Not classes. Not globals.
6. **Control flow is object-based.** ReduceIf, Iterate, etc. are first-class.
7. **Contracts are explicit.** `expects` and `promises` are verified by the
   framework, not by your code.
8. **Controlled failure is not an exception.** `fail!` sets a flag. Exceptions
   are for unexpected failures.
