# Blueprint: A Dependency-Injected, Object-Composed Workflow Gem

This document outlines a design for a Ruby workflow/service-object gem inspired by LightService, but with **dependency injection** and **object composition** as central architectural features.

The goal is to preserve the strengths of LightService:

- small composable actions,
- shared workflow context,
- explicit input/output contracts,
- organizers,
- branching and iteration,
- rollback,
- hooks,
- logging,
- localization,
- and testing helpers,

while changing the core execution model from class-level DSL actions to normal Ruby objects.

---

## 1. Core Architectural Shift

LightService-style actions look like this:

```ruby
class ChargeCard
  extend LightService::Action

  expects :user, :amount
  promises :charge

  executed do |ctx|
    ctx.charge = PaymentGateway.charge(ctx.user, ctx.amount)
  end
end
```

The proposed object-composed style would look like this:

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

The important distinction:

- **Context carries business state.**
- **Constructors receive service dependencies.**
- **Actions are normal Ruby objects.**
- **Organizers compose action objects.**
- **The framework owns execution lifecycle.**

---

## 2. Design Principles

The gem should be built around these principles:

1. Actions are ordinary objects.
2. Dependencies are injected through constructors.
3. Context is for workflow/business data, not infrastructure dependencies.
4. Actions implement `#call(ctx)` as their business body.
5. The framework provides `#execute(ctx)` for full lifecycle execution.
6. Organizers are objects that compose other objects.
7. Control-flow constructs are also objects.
8. Contracts are explicit through `expects` and `promises`.
9. Failure and skip behavior is represented on the context.
10. Rollback is optional and object-oriented via `#rollback(ctx)`.

Comparison:

| LightService | Proposed version |
|---|---|
| Actions are mostly stateless classes | Actions are objects |
| Dependencies often come from globals or context | Dependencies are constructor-injected |
| `executed do ... end` defines class-level execution | User implements instance `#call(ctx)` |
| Organizers are often class-level | Organizers are composed instances |
| Steps are class constants | Steps are callable objects |
| Macros define class execution behavior | Runner wraps object execution lifecycle |

---

## 3. Example Public API

### Action

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

  def rollback(ctx)
    # optional compensation logic
  end
end
```

### Organizer

```ruby
class CalculateOrderTotal
  include Workflow::Organizer

  def initialize(calculate_tax:, apply_discount:, calculate_total:)
    @calculate_tax = calculate_tax
    @apply_discount = apply_discount
    @calculate_total = calculate_total
  end

  def call(order:)
    with(order:).reduce(
      @calculate_tax,
      @apply_discount,
      @calculate_total
    )
  end
end
```

### Usage

```ruby
workflow = CalculateOrderTotal.new(
  calculate_tax: CalculateTax.new(tax_client: AvalaraClient.new),
  apply_discount: ApplyDiscount.new(discount_service: DiscountService.new),
  calculate_total: CalculateTotal.new
)

result = workflow.call(order:)

if result.success?
  puts result.total
else
  puts result.message
end
```

---

## 4. Suggested Project Structure

```text
lib/workflow.rb

lib/workflow/context.rb
lib/workflow/action.rb
lib/workflow/action_metadata.rb
lib/workflow/action_runner.rb

lib/workflow/organizer.rb
lib/workflow/organizer_session.rb
lib/workflow/reducer.rb
lib/workflow/step.rb

lib/workflow/steps/reduce_if.rb
lib/workflow/steps/reduce_if_else.rb
lib/workflow/steps/reduce_until.rb
lib/workflow/steps/reduce_while.rb
lib/workflow/steps/reduce_case.rb
lib/workflow/steps/iterate.rb
lib/workflow/steps/execute.rb
lib/workflow/steps/add_to_context.rb
lib/workflow/steps/add_aliases.rb
lib/workflow/steps/with_callback.rb

lib/workflow/hooks.rb
lib/workflow/rollback_strategy.rb
lib/workflow/localization.rb
lib/workflow/configuration.rb
lib/workflow/errors.rb

lib/workflow/testing/context_factory.rb
```

The most important separation is:

```text
Action object
  Holds business behavior and dependencies.

ActionRunner
  Owns framework lifecycle:
  - apply defaults
  - verify expected keys
  - run before hooks
  - call action
  - run after hooks
  - verify promised keys
  - handle fail/skip state
  - track current action
```

---

## 5. Context

The context carries workflow data and status.

Unlike LightService, consider avoiding inheritance from `Hash`. Prefer composition.

```ruby
module Workflow
  class Context
    attr_reader :data
    attr_accessor :message, :error_code, :current_step, :organized_by

    def initialize(data = {})
      @data = data.to_h.transform_keys(&:to_sym)
      @success = true
      @skip_remaining = false
      @skip_all_remaining = false
      @message = nil
      @error_code = nil
      @aliases = {}
    end

    def [](key)
      @data[resolve_alias(key)]
    end

    def []=(key, value)
      @data[resolve_alias(key)] = value
    end

    def key?(key)
      @data.key?(resolve_alias(key))
    end

    def keys
      @data.keys
    end

    def to_h
      @data.dup
    end

    def success?
      @success
    end

    def failure?
      !success?
    end

    def fail!(message = nil, error_code: nil, **_options)
      @success = false
      @message = message
      @error_code = error_code
    end

    def succeed!(message = nil)
      @success = true
      @message = message
    end

    def skip_remaining!(message = nil)
      @message = message
      @skip_remaining = true
    end

    def skip_all_remaining!(message = nil)
      @message = message
      @skip_all_remaining = true
    end

    def skip_remaining?
      @skip_remaining
    end

    def skip_all_remaining?
      @skip_all_remaining
    end

    def stop_processing?
      failure? || skip_remaining? || skip_all_remaining?
    end

    def reset_skip_remaining!
      @skip_remaining = false
      @message = nil
    end

    def assign_aliases(aliases)
      @aliases.merge!(aliases.transform_keys(&:to_sym).transform_values(&:to_sym))
    end

    private

    def resolve_alias(key)
      key = key.to_sym
      @aliases.key(key) || key
    end
  end
end
```

Optional dynamic accessors can be added:

```ruby
def method_missing(name, *args)
  name_string = name.to_s

  if name_string.end_with?("=")
    self[name_string.delete_suffix("=").to_sym] = args.first
  elsif key?(name)
    self[name]
  else
    super
  end
end

def respond_to_missing?(name, include_private = false)
  key?(name.to_s.delete_suffix("=").to_sym) || super
end
```

Dynamic context access is convenient but magical. Consider a strict mode to catch typos.

---

## 6. Action Module

Actions include a module that provides contract metadata and a framework-level `#execute` method.

```ruby
module Workflow
  module Action
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def expects(*keys, **options)
        if options.key?(:default)
          key = keys.fetch(0).to_sym
          workflow_metadata.expected_keys << key
          workflow_metadata.defaults[key] = options[:default]
        else
          workflow_metadata.expected_keys.concat(keys.map(&:to_sym))
        end
      end

      def promises(*keys)
        workflow_metadata.promised_keys.concat(keys.map(&:to_sym))
      end

      def workflow_metadata
        @workflow_metadata ||= ActionMetadata.new
      end
    end

    def workflow_metadata
      self.class.workflow_metadata
    end

    def execute(ctx = Context.new)
      Workflow::ActionRunner.default.call(self, ctx)
    end
  end
end
```

Metadata object:

```ruby
module Workflow
  class ActionMetadata
    attr_reader :expected_keys, :promised_keys, :optional_keys, :defaults

    def initialize(
      expected_keys: [],
      promised_keys: [],
      optional_keys: [],
      defaults: {}
    )
      @expected_keys = expected_keys
      @promised_keys = promised_keys
      @optional_keys = optional_keys
      @defaults = defaults
    end
  end
end
```

---

## 7. ActionRunner

`ActionRunner` is central to the architecture.

It lets user actions remain simple objects while the framework enforces lifecycle behavior.

```ruby
module Workflow
  class ActionRunner
    def self.default
      new
    end

    def initialize(before_hooks: [], after_hooks: [], around_hooks: [], logger: nil)
      @before_hooks = before_hooks
      @after_hooks = after_hooks
      @around_hooks = around_hooks
      @logger = logger
    end

    def call(action, ctx)
      return ctx if ctx.stop_processing?

      ctx.current_step = action

      apply_defaults(action, ctx)
      verify_expected_keys!(action, ctx)

      run_before_hooks(action, ctx)

      run_around_hooks(action, ctx) do
        action.call(ctx)
      end

      verify_promised_keys!(action, ctx)
      run_after_hooks(action, ctx)

      ctx
    end

    private

    def metadata_for(action)
      action.workflow_metadata
    end

    def apply_defaults(action, ctx)
      metadata_for(action).defaults.each do |key, default|
        next if ctx.key?(key)

        ctx[key] = default.respond_to?(:call) ? default.call(ctx) : default
      end
    end

    def verify_expected_keys!(action, ctx)
      missing = metadata_for(action).expected_keys.reject { |key| ctx.key?(key) }
      raise ExpectedKeysMissing, "Missing expected keys: #{missing.inspect}" unless missing.empty?
    end

    def verify_promised_keys!(action, ctx)
      return if ctx.failure?

      missing = metadata_for(action).promised_keys.reject { |key| ctx.key?(key) }
      raise PromisedKeysMissing, "Missing promised keys: #{missing.inspect}" unless missing.empty?
    end

    def run_before_hooks(action, ctx)
      @before_hooks.each { |hook| hook.call(action, ctx) }
    end

    def run_after_hooks(action, ctx)
      @after_hooks.each { |hook| hook.call(action, ctx) }
    end

    def run_around_hooks(action, ctx, &block)
      chain = @around_hooks.reverse.reduce(block) do |next_block, hook|
        -> { hook.call(action, ctx, &next_block) }
      end

      chain.call
    end
  end
end
```

Important convention:

- `#call(ctx)` is the raw business method.
- `#execute(ctx)` runs the action through the framework lifecycle.
- Reducers should call `#execute`, not raw `#call`, for workflow actions.

---

## 8. Reducer

The reducer executes a sequence of steps.

```ruby
module Workflow
  class Reducer
    def initialize(action_runner:, rollback_strategy: RollbackStrategy.new)
      @action_runner = action_runner
      @rollback_strategy = rollback_strategy
    end

    def reduce(ctx, steps)
      executed_steps = []

      Array(steps).flatten.each do |step|
        break if ctx.stop_processing?

        executed_steps << step
        invoke(step, ctx)
      rescue FailWithRollback
        @rollback_strategy.rollback(ctx, executed_steps.reverse)
        break
      end

      ctx
    end

    private

    def invoke(step, ctx)
      if workflow_action?(step)
        @action_runner.call(step, ctx)
      else
        step.call(ctx)
      end
    end

    def workflow_action?(step)
      step.respond_to?(:workflow_metadata)
    end
  end
end
```

A step can be:

- an action object,
- a control-flow object,
- a lambda,
- a nested workflow object,
- or any object responding to `#call(ctx)`.

---

## 9. Organizer

Organizers should also be objects.

```ruby
module Workflow
  module Organizer
    def with(data = {})
      ctx = data.is_a?(Workflow::Context) ? data : Workflow::Context.new(data)
      ctx.organized_by = self
      Workflow::OrganizerSession.new(self, ctx)
    end

    def reduce(*steps)
      with({}).reduce(*steps)
    end

    def reduce_if(condition, steps)
      Steps::ReduceIf.new(condition, steps)
    end

    def reduce_if_else(condition, if_steps, else_steps)
      Steps::ReduceIfElse.new(condition, if_steps, else_steps)
    end

    def iterate(collection_key, steps, item_key: nil)
      Steps::Iterate.new(collection_key, steps, item_key: item_key)
    end

    def execute(code_block = nil, &block)
      Steps::Execute.new(code_block || block)
    end
  end
end
```

`OrganizerSession` holds per-run state:

```ruby
module Workflow
  class OrganizerSession
    def initialize(organizer, ctx)
      @organizer = organizer
      @ctx = ctx
      @before_hooks = []
      @after_hooks = []
      @around_hooks = []
    end

    def around_each(hook)
      @around_hooks << hook
      self
    end

    def before_each(hook)
      @before_hooks << hook
      self
    end

    def after_each(hook)
      @after_hooks << hook
      self
    end

    def reduce(*steps)
      runner = ActionRunner.new(
        before_hooks: @before_hooks,
        after_hooks: @after_hooks,
        around_hooks: @around_hooks,
        logger: Workflow.configuration.logger
      )

      reducer = Reducer.new(action_runner: runner)
      reducer.reduce(@ctx, steps.flatten)
    end
  end
end
```

---

## 10. Control-Flow Steps

Control flow should be represented by explicit objects rather than anonymous lambdas wherever possible.

### ReduceIf

```ruby
module Workflow
  module Steps
    class ReduceIf
      def initialize(condition, steps)
        @condition = condition
        @steps = steps
      end

      def call(ctx)
        return ctx if ctx.stop_processing?

        scoped_reduce(ctx, @steps) if @condition.call(ctx)
        ctx
      end

      private

      def scoped_reduce(ctx, steps)
        ctx.reset_skip_remaining! unless ctx.failure?

        runner = ActionRunner.default
        reducer = Reducer.new(action_runner: runner)
        reducer.reduce(ctx, steps)

        ctx.reset_skip_remaining! unless ctx.failure? || ctx.skip_all_remaining?
        ctx
      end
    end
  end
end
```

### Iterate

```ruby
module Workflow
  module Steps
    class Iterate
      def initialize(collection_key, steps, item_key: nil)
        @collection_key = collection_key
        @steps = steps
        @item_key = item_key
      end

      def call(ctx)
        collection = ctx[@collection_key]
        item_key = @item_key || singularize(@collection_key)

        collection.each do |item|
          break if ctx.stop_processing?

          ctx[item_key] = item
          scoped_reduce(ctx, @steps)
        end

        ctx
      end

      private

      def singularize(key)
        key.to_s.sub(/s\z/, '').to_sym
      end

      def scoped_reduce(ctx, steps)
        runner = ActionRunner.default
        reducer = Reducer.new(action_runner: runner)
        reducer.reduce(ctx, steps)
      end
    end
  end
end
```

Other control-flow steps to implement:

- `ReduceIfElse`
- `ReduceUntil`
- `ReduceWhile`
- `ReduceCase`
- `Execute`
- `AddToContext`
- `AddAliases`
- `WithCallback`

Example usage:

```ruby
with(input).reduce(
  fetch_items,
  reduce_if(->(ctx) { ctx.items.empty? }, [
    notify_empty_result
  ]),
  iterate(:items, [
    process_item
  ]),
  finalize
)
```

---

## 11. Hooks and Middleware

Hooks should also be objects.

```ruby
class LogDuration
  def initialize(logger:)
    @logger = logger
  end

  def call(action, ctx)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    @logger.info(action: action.class.name, duration: duration)

    result
  end
end
```

Usage:

```ruby
with(input)
  .around_each(LogDuration.new(logger: logger))
  .reduce(actions)
```

Potential hook APIs:

```ruby
before_each SomeBeforeHook.new
after_each SomeAfterHook.new
around_each SomeAroundHook.new
```

Support hooks at multiple levels:

1. Global configuration
2. Organizer instance
3. Specific run/session

---

## 12. Rollback

Rollback is naturally represented as an optional instance method.

```ruby
class SaveOrder
  include Workflow::Action

  def call(ctx)
    ctx.order.save!
  end

  def rollback(ctx)
    ctx.order.destroy!
  end
end
```

Trigger rollback from context:

```ruby
ctx.fail_with_rollback!("Payment failed")
```

Context implementation:

```ruby
class Context
  def fail_with_rollback!(message = nil, error_code: nil)
    fail!(message, error_code: error_code)
    raise Workflow::FailWithRollback
  end
end
```

Rollback strategy:

```ruby
module Workflow
  class RollbackStrategy
    def rollback(ctx, steps)
      steps.each do |step|
        step.rollback(ctx) if step.respond_to?(:rollback)
      end

      ctx
    end
  end
end
```

---

## 13. Contracts

Contracts remain central.

```ruby
class ChargeCard
  include Workflow::Action

  expects :user, :amount
  promises :charge
end
```

Expected keys are verified before action execution.

Promised keys are verified after action execution.

Defaults should be supported:

```ruby
class SendSms
  include Workflow::Action

  expects :user, :message
  expects :allow_failure, default: true
end
```

Callable defaults should also work:

```ruby
expects :allow_failure, default: ->(ctx) { !ctx.user.admin? }
```

Reserved keys should be protected:

```ruby
RESERVED_KEYS = %i[
  message
  error_code
  current_step
  organized_by
]
```

---

## 14. Instance-Specific Metadata

One advantage of object-based actions is that metadata can be instance-specific.

Example:

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
```

Usage:

```ruby
normalize_name = NormalizeField.new(
  from: :name,
  to: :normalized_name
)
```

This is much harder to express elegantly with class-level actions.

---

## 15. Error Handling Philosophy

Separate controlled business failure from exceptional programming/system failure.

Controlled failure:

```ruby
ctx.fail!("Card declined")
```

Exceptional failure:

```ruby
raise NetworkError
```

Recommended defaults:

- `ctx.fail!` stops the pipeline and returns a failed context.
- `ctx.skip_remaining!` stops the current scope successfully.
- `ctx.skip_all_remaining!` stops all remaining nested scopes successfully.
- Exceptions bubble by default.
- `ctx.fail_with_rollback!` fails and triggers compensation.

Optional configuration:

```ruby
Workflow.configure do |config|
  config.capture_exceptions = false
end
```

If enabled, exceptions could be converted to failed contexts, but this should not be the default.

---

## 16. Localization

Localization should be adapter-based.

```ruby
Workflow.configure do |config|
  config.localization_adapter = Workflow::Localization::I18nAdapter.new
end
```

Context failure can delegate message translation:

```ruby
def fail!(message_or_key = nil, **options)
  @message = Workflow.configuration.localization_adapter.failure(
    message_or_key,
    current_step,
    options
  )
  @success = false
end
```

For object actions, scopes can be based on the action class:

```text
charge_card.workflow.failures.card_declined
```

or:

```text
workflow.charge_card.failures.card_declined
```

Make the scope strategy configurable.

---

## 17. Logging and Introspection

Logging should include action object information:

```ruby
logger.info("[Workflow] executing #{step.class.name}")
logger.info("[Workflow] expected keys: #{metadata.expected_keys}")
logger.info("[Workflow] promised keys: #{metadata.promised_keys}")
logger.info("[Workflow] context keys: #{ctx.keys}")
```

A useful introspection API could be:

```ruby
workflow.describe
```

Example output:

```ruby
[
  {
    name: "ValidateCart",
    expects: [:cart],
    promises: []
  },
  {
    name: "ChargeCard",
    expects: [:user, :amount],
    promises: [:charge]
  }
]
```

This could become a major feature of the object-composed design.

---

## 18. Testing Helpers

A context factory is still useful.

Goal:

> Give me the context immediately before a specific action runs in this workflow.

Example API:

```ruby
ctx = Workflow::Testing::ContextFactory
  .make_from(checkout)
  .before(charge_card)
  .with(cart: cart, user: user, amount: 100)
```

Support lookup by object or class:

```ruby
.before(charge_card_instance)
.before(ChargeCard)
```

Direct action tests should use `#execute`, not raw `#call`, when contract verification matters:

```ruby
action = ChargeCard.new(payment_gateway: fake_gateway)
ctx = Workflow::Context.new(user: user, amount: 100)

result = action.execute(ctx)

expect(result).to be_success
expect(result.charge).to eq(charge)
```

Potential RSpec matchers:

```ruby
expect(action).to expect_keys(:user, :amount)
expect(action).to promise_keys(:charge)
expect(result).to be_success
expect(result).to have_context_value(:charge)
```

---

## 19. Rails Integration

Optional Rails support could include generators:

```shell
rails generate workflow:action ChargeCard expects:user,amount promises:charge
rails generate workflow:organizer Checkout
```

Generated action:

```ruby
class ChargeCard
  include Workflow::Action

  expects :user, :amount
  promises :charge

  def initialize(payment_gateway:)
    @payment_gateway = payment_gateway
  end

  def call(ctx)
    # implementation
  end
end
```

Generated organizer:

```ruby
class Checkout
  include Workflow::Organizer

  def initialize(validate_cart:, charge_card:, send_receipt:)
    @validate_cart = validate_cart
    @charge_card = charge_card
    @send_receipt = send_receipt
  end

  def call(input)
    with(input).reduce(
      @validate_cart,
      @charge_card,
      @send_receipt
    )
  end
end
```

---

## 20. Suggested Implementation Phases

### Phase 1: Core Pipeline

Implement:

1. `Workflow::Context`
2. `Workflow::Action`
3. `Workflow::ActionMetadata`
4. `Workflow::ActionRunner`
5. `Workflow::Reducer`
6. `Workflow::Organizer`
7. Basic specs

Support:

- `expects`
- `promises`
- `ctx.fail!`
- `ctx.success?`
- `ctx.failure?`
- linear `reduce`

---

### Phase 2: Dependency-Injected Workflows

Add examples and specs for:

```ruby
ChargeCard.new(payment_gateway: fake_gateway)
Checkout.new(charge_card: charge_card)
```

Support:

- callable objects,
- lambdas,
- nested organizers,
- direct `action.execute(ctx)`.

---

### Phase 3: Flow Control

Implement step objects:

- `ReduceIf`
- `ReduceIfElse`
- `ReduceWhile`
- `ReduceUntil`
- `ReduceCase`
- `Iterate`
- `Execute`
- `AddToContext`
- `AddAliases`

Write acceptance-style specs for each.

---

### Phase 4: Hooks, Logging, Around Behavior

Add:

- `before_each`
- `after_each`
- `around_each`
- global middleware
- logger integration

Make sure around hooks work with object actions and nested flow-control steps.

---

### Phase 5: Rollback

Add:

- `ctx.fail_with_rollback!`
- `Workflow::FailWithRollback`
- rollback strategy
- reverse-order rollback
- rollback specs

---

### Phase 6: Localization

Add:

- localization adapter interface,
- simple hash adapter,
- optional I18n adapter.

---

### Phase 7: Testing Support

Add:

- context factory,
- action runner helpers,
- workflow introspection helpers,
- optional RSpec matchers.

---

### Phase 8: Rails Integration

Optional:

- Rails generators,
- Zeitwerk-friendly structure,
- initializer generator,
- action generator,
- organizer generator.

---

## 21. Full Example

```ruby
class ValidateCart
  include Workflow::Action

  expects :cart

  def call(ctx)
    ctx.fail!("Cart is empty") if ctx.cart.empty?
  end
end

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

class SendReceipt
  include Workflow::Action

  expects :user, :charge

  def initialize(mailer:)
    @mailer = mailer
  end

  def call(ctx)
    @mailer.receipt(ctx.user, ctx.charge).deliver_later
  end
end

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

Composition:

```ruby
checkout = Checkout.new(
  validate_cart: ValidateCart.new,
  charge_card: ChargeCard.new(payment_gateway: StripeGateway.new),
  send_receipt: SendReceipt.new(mailer: ReceiptMailer)
)

result = checkout.call(cart: cart, user: user, amount: amount)

if result.success?
  puts "Charged #{result.charge.id}"
else
  puts result.message
end
```

Testing:

```ruby
fake_gateway = instance_double("Gateway")
allow(fake_gateway).to receive(:charge).and_return(successful_charge)

action = ChargeCard.new(payment_gateway: fake_gateway)
ctx = Workflow::Context.new(user: user, amount: 100)

result = action.execute(ctx)

expect(result).to be_success
expect(result.charge).to eq(successful_charge.charge)
```

---

## 22. Pitfalls to Watch For

### Accidentally bypassing the runner

If users call:

```ruby
action.call(ctx)
```

they bypass expectations, promises, hooks, and logging.

Document clearly:

- `#call` is raw business logic.
- `#execute` is framework execution.
- Organizers/reducers use `#execute` for workflow actions.

---

### Service dependencies leaking into context

Avoid this:

```ruby
with(payment_gateway: gateway, mailer: mailer)
```

Prefer this:

```ruby
ChargeCard.new(payment_gateway: gateway)
SendReceipt.new(mailer: mailer)
```

Context should represent business state, not service infrastructure.

---

### Stateful action instances

Object actions can hold state, which is powerful but risky.

Avoid per-run mutable instance state:

```ruby
# Avoid

def call(ctx)
  @current_user = ctx.user
end
```

Prefer local variables:

```ruby
def call(ctx)
  user = ctx.user
end
```

This matters if action instances are reused across threads or requests.

---

### Context accessor magic

Dynamic methods are convenient:

```ruby
ctx.amount
ctx.charge = charge
```

But they can hide typos.

Consider strict mode:

```ruby
Workflow.configure do |config|
  config.strict_context_access = true
end
```

---

## 23. Architectural Thesis

The gem can be positioned as:

> A workflow orchestration library for Ruby that combines LightService-style context pipelines with explicit object composition and constructor dependency injection.

The core opinion:

- Context is for business data.
- Constructors are for dependencies.
- Actions are objects.
- Organizers compose objects.
- The framework owns execution lifecycle.

This provides a coherent alternative to LightService’s class-level DSL while keeping the same spirit of small, readable, composable business workflows.

---

## 24. AI-Agent Workflow Composition

This architecture is especially well-suited to systems where AI agents are allowed to select, configure, or compose workflows from developer-defined capabilities.

The key insight is that AI-agent workflow composition is not merely about executing Ruby code. It is about exposing a safe, inspectable, policy-controlled catalog of capabilities that an agent can reason about.

For AI use cases, the object-composed approach is generally a better foundation than a class-level DSL because:

1. Actions can be exposed as prebuilt capability objects.
2. Service dependencies can be injected by the application and hidden from the agent.
3. Actions can carry richer metadata for planning and validation.
4. Runtime workflow composition is naturally represented as arrays of objects or structured plans.
5. Instance-specific and parameterized actions are easier to support.
6. AI-generated plans can be validated before execution.
7. Dangerous side effects can be governed through policies and approval gates.

However, this does not mean agents should be allowed to execute arbitrary Ruby or freely instantiate arbitrary classes.

The recommended model is:

```text
Developer-defined actions and workflows
        ↓
Capability registry with metadata and policies
        ↓
Agent sees sanitized capability descriptions
        ↓
Agent proposes structured workflow plan
        ↓
Validator checks contracts, safety, policy, and permissions
        ↓
Compiler turns approved plan into executable steps
        ↓
Runner executes with audit, approval, and rollback support
```

---

## 25. Two AI Integration Models

There are two distinct ways to use workflow libraries with AI agents.

### Model A: Agent Selects from Predefined Workflows

In this model, developers define complete workflows ahead of time.

The agent only chooses which workflow to run and supplies inputs.

Example:

```ruby
class RefundAndNotifyCustomer
  include Workflow::Organizer

  def initialize(find_order:, validate_refund:, issue_refund:, send_email:)
    @find_order = find_order
    @validate_refund = validate_refund
    @issue_refund = issue_refund
    @send_email = send_email
  end

  def call(order_id:)
    with(order_id: order_id).reduce(
      @find_order,
      @validate_refund,
      @issue_refund,
      @send_email
    )
  end
end
```

The AI chooses:

```json
{
  "workflow": "refund_and_notify_customer",
  "input": {
    "order_id": "ord_123"
  }
}
```

This approach is:

- safer,
- easier to audit,
- easier to test,
- more predictable,
- and suitable for high-risk production systems.

Classic LightService works well for this model too, because static class-level organizers are easy for humans to review.

### Model B: Agent Composes Workflows from Capabilities

In this model, developers expose primitive actions as capabilities, and the agent builds a workflow plan.

Example user request:

> Find customers whose last payment failed, retry payment if under $50, otherwise create support tasks.

The agent might produce a plan equivalent to:

```ruby
[
  query_customers_with_failed_payment,
  iterate(:customers, [
    calculate_retry_amount,
    reduce_if_else(
      ->(ctx) { ctx.amount < 50 },
      [retry_payment, send_success_notice],
      [create_support_task]
    )
  ])
]
```

This model is more dynamic and expressive, but also riskier.

It is a stronger fit for the object-composed architecture because runtime composition is naturally represented as objects, registered capabilities, and structured plans.

---

## 26. Capability Registry

A first-class capability registry should be part of the AI-facing architecture.

The registry stores executable action objects together with metadata that is safe to expose to agents.

Example:

```ruby
registry = Workflow::CapabilityRegistry.new

registry.register(
  :find_order,
  action: FindOrder.new(order_repository: order_repository),
  description: "Finds an order by order_id.",
  expects: [:order_id],
  promises: [:order],
  side_effects: [],
  risk: :low
)

registry.register(
  :issue_refund,
  action: IssueRefund.new(payment_gateway: payment_gateway),
  description: "Issues a refund for an order.",
  expects: [:order],
  promises: [:refund],
  side_effects: [:money_movement],
  requires_approval: true,
  rollback_available: true,
  risk: :high
)
```

The agent sees only sanitized descriptions:

```json
[
  {
    "id": "find_order",
    "description": "Finds an order by order_id.",
    "expects": ["order_id"],
    "promises": ["order"],
    "side_effects": [],
    "risk": "low"
  },
  {
    "id": "issue_refund",
    "description": "Issues a refund for an order.",
    "expects": ["order"],
    "promises": ["refund"],
    "side_effects": ["money_movement"],
    "requires_approval": true,
    "risk": "high"
  }
]
```

The agent does not see credentials, API clients, mailers, repositories, or other implementation dependencies.

This preserves the important distinction:

- constructor injection is for infrastructure dependencies,
- context is for business data,
- capability metadata is for planning and validation.

---

## 27. Capability Metadata for Planning

AI agents need more than `expects` and `promises`.

Useful metadata includes:

```ruby
{
  id: :charge_card,
  description: "Charges a customer's payment method for the current amount.",
  expects: [:customer, :payment_method, :amount],
  promises: [:charge],
  failure_modes: [:card_declined, :gateway_unavailable],
  side_effects: [:external_api_call, :money_movement],
  requires_approval: true,
  rollback_available: true,
  idempotent: false,
  risk: :high,
  categories: [:payments]
}
```

This metadata can live on the action class, the action instance, or the registry entry.

Registry-level metadata is often preferable because it can vary by environment, tenant, user, or deployment.

For example:

```ruby
registry.register(
  :charge_card,
  action: ChargeCard.new(payment_gateway: stripe_gateway),
  description: "Charge the customer's saved payment method.",
  risk: Rails.env.production? ? :high : :medium,
  requires_approval: Rails.env.production?
)
```

---

## 28. Structured Plans Instead of Runtime Ruby

Agents should not emit arbitrary Ruby code.

Instead, agents should produce structured workflow plans.

Example linear plan:

```json
{
  "name": "refund_order_and_notify",
  "input": {
    "order_id": "ord_123"
  },
  "steps": [
    { "id": "find_order" },
    { "id": "validate_refund_eligibility" },
    { "id": "issue_refund" },
    { "id": "send_refund_email" }
  ]
}
```

Example conditional plan:

```json
{
  "type": "if",
  "condition": {
    "key": "refund_eligible",
    "equals": true
  },
  "then": [
    { "id": "issue_refund" },
    { "id": "send_refund_email" }
  ],
  "else": [
    { "id": "create_support_ticket" }
  ]
}
```

Example iteration plan:

```json
{
  "type": "iterate",
  "collection": "orders",
  "as": "order",
  "steps": [
    { "id": "validate_refund_eligibility" },
    { "id": "issue_refund" }
  ]
}
```

A plan schema should be deliberately small and safe.

Recommended primitives:

- action step by registered `id`,
- `if`,
- `if_else`,
- `iterate`,
- `add_to_context`,
- possibly `case`,
- possibly `while` or `until`, but only with strict bounds.

Avoid arbitrary expressions. Conditions should be represented as data and interpreted by a safe evaluator.

---

## 29. Plan Validation

Before execution, every agent-generated plan should be validated.

Validation should check:

- all step IDs are registered,
- all expected keys are available before each step,
- promised keys are added to the simulated key set,
- reserved keys are not overwritten,
- side effects are allowed,
- risk level is acceptable,
- approval requirements are detected,
- user or agent has permission to use each capability,
- loops are bounded,
- nesting depth is bounded,
- the plan is not empty,
- dangerous steps have rollback or approval when required,
- tenant/environment policies are satisfied.

The `expects` and `promises` contract model is extremely valuable here.

A validator can simulate key flow without executing the workflow:

```text
Initial keys: [:order_id]

find_order
  expects: [:order_id] OK
  promises: [:order]
  keys now: [:order_id, :order]

validate_refund_eligibility
  expects: [:order] OK
  promises: [:refund_eligible]
  keys now: [:order_id, :order, :refund_eligible]

issue_refund
  expects: [:order] OK
  promises: [:refund]
  side_effects: [:money_movement]
  requires approval: true
```

Example API:

```ruby
validator = Workflow::PlanValidator.new(registry: registry, policy: policy)
validation = validator.validate(plan, initial_keys: [:order_id], agent: agent)

unless validation.safe?
  return validation.errors
end
```

---

## 30. Plan Compiler

After validation, a compiler turns the structured plan into executable workflow steps.

```ruby
steps = Workflow::PlanCompiler.new(registry: registry).compile(plan)
```

A linear plan compiles to action objects:

```ruby
[
  registry.fetch(:find_order),
  registry.fetch(:validate_refund_eligibility),
  registry.fetch(:issue_refund),
  registry.fetch(:send_refund_email)
]
```

A conditional plan compiles to control-flow step objects:

```ruby
[
  registry.fetch(:find_order),
  Workflow::Steps::ReduceIfElse.new(
    condition,
    [registry.fetch(:issue_refund), registry.fetch(:send_refund_email)],
    [registry.fetch(:create_support_ticket)]
  )
]
```

Execution then uses the normal runtime:

```ruby
result = Workflow::Runner.new.run(
  input: plan.fetch("input"),
  steps: steps
)
```

or:

```ruby
dynamic_workflow = Workflow::DynamicOrganizer.new(steps: steps)
result = dynamic_workflow.call(plan.fetch("input"))
```

---

## 31. Policy, Approval, and Safety Gates

AI-composed workflows need explicit safety mechanisms.

### Policy Engine

Each action should be checked before execution:

```ruby
policy.allowed?(agent: agent, action: action, context: ctx)
```

Policy can consider:

- the agent identity,
- the current user,
- tenant,
- environment,
- action risk,
- side effects,
- context values,
- rate limits,
- business constraints.

### Approval Gates

High-risk capabilities should support approval gates.

Example metadata:

```ruby
requires_approval: true
```

When such a step appears, the system can pause:

```ruby
{
  status: "approval_required",
  pending_steps: [...],
  reason: "Plan includes money_movement action issue_refund"
}
```

A human or trusted system can approve continuation.

### Dry-Run Mode

Dry-run mode should simulate the workflow without executing side effects.

```ruby
Workflow::Runner.new(dry_run: true).run(plan)
```

Dry-run output should include:

- steps,
- expected inputs,
- promised outputs,
- missing keys,
- side effects,
- approval requirements,
- estimated risk,
- rollback availability.

### Audit Trail

Every agent-generated workflow should produce an audit record:

```ruby
{
  agent_id: "agent_123",
  user_id: "user_456",
  plan: plan,
  validation_result: validation.to_h,
  executed_steps: [...],
  skipped_steps: [...],
  failures: [...],
  approvals: [...]
}
```

This is critical for production use.

---

## 32. Dynamic Organizer

For runtime-composed workflows, provide a small dynamic organizer.

```ruby
module Workflow
  class DynamicOrganizer
    include Workflow::Organizer

    def initialize(steps:, before_hooks: [], after_hooks: [], around_hooks: [])
      @steps = steps
      @before_hooks = before_hooks
      @after_hooks = after_hooks
      @around_hooks = around_hooks
    end

    def call(input = {})
      session = with(input)

      @before_hooks.each { |hook| session.before_each(hook) }
      @after_hooks.each { |hook| session.after_each(hook) }
      @around_hooks.each { |hook| session.around_each(hook) }

      session.reduce(@steps)
    end
  end
end
```

This lets the system execute compiled plans while still using the same reducer, action runner, hooks, and context semantics.

---

## 33. Recommended AI Autonomy Levels

A production system should support different levels of agent autonomy.

### Low Autonomy

The agent may only select from approved workflows.

```json
{
  "workflow": "refund_order",
  "input": {
    "order_id": "ord_123"
  }
}
```

Best for high-risk domains.

### Medium Autonomy

The agent may compose read-only or low-risk capabilities.

```json
{
  "steps": [
    { "id": "find_order" },
    { "id": "summarize_order" },
    { "id": "draft_customer_response" }
  ]
}
```

Good for research, summarization, reporting, support preparation, and internal tools.

### High Autonomy

The agent may compose side-effecting actions, but only with validation, policies, approval gates, and audit trails.

```json
{
  "steps": [
    { "id": "find_order" },
    { "id": "issue_refund" },
    { "id": "send_refund_email" }
  ]
}
```

Best used only when safeguards are mature.

---

## 34. Comparison: LightService vs Object-Composed for AI Agents

| Use case | Better fit |
|---|---|
| Agent chooses among known workflows | LightService or object-composed |
| Agent fills inputs for known workflows | LightService or object-composed |
| Agent composes new workflows dynamically | Object-composed |
| Agent configures parameterized steps | Object-composed |
| Maximum auditability through static code | LightService-style static organizers |
| Maximum runtime flexibility | Object-composed with registry and validator |
| Human-authored workflows | Either |
| Agent-authored runtime plans | Object-composed |
| Capability metadata and policy integration | Object-composed |
| Constructor dependency injection | Object-composed |

The strongest recommendation is a hybrid:

1. Developers define primitive capabilities as object actions.
2. Developers may also define approved high-level workflows.
3. Agents operate through a capability registry and structured plans.
4. All plans are validated before execution.
5. High-risk actions require approval.
6. Every execution is audited.

---

## 35. Additional AI-Focused Components

If AI-agent composition is a first-class goal, add these components to the library:

```text
Workflow::CapabilityRegistry
Workflow::Capability
Workflow::Plan
Workflow::PlanValidator
Workflow::PlanCompiler
Workflow::Policy
Workflow::ApprovalGate
Workflow::DryRunRunner
Workflow::AuditTrail
Workflow::DynamicOrganizer
```

Possible structure:

```text
lib/workflow/ai/capability.rb
lib/workflow/ai/capability_registry.rb
lib/workflow/ai/plan.rb
lib/workflow/ai/plan_validator.rb
lib/workflow/ai/plan_compiler.rb
lib/workflow/ai/policy.rb
lib/workflow/ai/approval_gate.rb
lib/workflow/ai/audit_trail.rb
```

These can be optional modules so the core workflow library remains small.

---

## 36. Updated Architectural Thesis for AI Use

For normal application code, the thesis remains:

> Context is for business data. Constructors are for dependencies. Actions are objects. Organizers compose objects. The framework owns execution lifecycle.

For AI-agent workflow composition, extend the thesis:

> Agents should compose structured plans from registered capabilities, not arbitrary code. The runtime should validate, authorize, compile, execute, and audit those plans using the same action, context, and organizer primitives available to human developers.

This keeps the system flexible enough for agentic composition while preserving safety, auditability, and developer control.
