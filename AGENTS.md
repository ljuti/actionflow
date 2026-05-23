# AGENTS.md — Architecture & Build Rules

This document is the **operating contract** for any agent (human or LLM) working
on this codebase. It encodes hard rules. Violations require an ADR that
explicitly supersedes the rule.

---

## 1. Stack (locked)

| Layer         | Tech                                              | Notes                       |
| ------------- | ------------------------------------------------- | --------------------------- |
| Language      | Ruby ≥ 3.2                                        | Required by gemspec         |
| Module        | `Workflow` (inside `Actionflow` gem namespace)    | Top-level namespace         |
| Linting       | Standard Ruby (`standardrb`)                      | Zero warnings policy        |
| Type sigs     | RBS (`sig/actionflow.rbs`)                        | Optional, kept in sync      |
| Tests         | RSpec                                             | TDD mandatory               |
| Build         | Bundler, `rake`                                   | Gem packaging               |

**Forbidden:** `rubocop` (use Standard), `minitest` (use RSpec), any runtime
dependency that isn't strictly necessary — this is a library, not an
application.

---

## 2. Process Model (the one diagram you must internalize)

```
User code
│
│  Organizer.with(input)
│       │
│       ▼
OrganizerSession
│  .before_each / .after_each / .around_each
│       │
│       ▼
Reducer.reduce(ctx, steps)
│       │
│       ▼  for each step:
├── Workflow action?  ──→  ActionRunner.call(action, ctx)
│                            apply_defaults
│                            verify_expected_keys
│                            before_hooks
│                            around_hooks → action.call(ctx)
│                            verify_promised_keys
│                            after_hooks
├── Control-flow step? ──→ step.call(ctx)
│    (ReduceIf, Iterate, …)
├── Callable? ──→ step.call(ctx)
│    (lambda, nested organizer)
│
▼
Context (final state)
  .success? / .failure? / .message / .to_h
```

**Invariants:**

- Context carries **business data only** — never infrastructure dependencies.
- Constructors receive **service dependencies** — never business data.
- Actions implement `#call(ctx)` as raw business logic.
- Actions implement `#execute(ctx)` for full framework lifecycle.
- Organizers/reducers call `#execute`, not raw `#call`, for workflow actions.
- The framework owns the execution lifecycle; actions own the business logic.

---

## 3. Repository Layout (do not deviate)

```
lib/
  actionflow.rb                               # Entry point, requires workflow modules
  actionflow/
    version.rb                                # VERSION constant
  workflow/
    context.rb                                # Shared workflow state
    action.rb                                 # Action module (expects/promises/execute)
    action_metadata.rb                        # Contract metadata container
    action_runner.rb                          # Framework lifecycle around #call
    organizer.rb                              # Organizer module (with/reduce/control-flow helpers)
    organizer_session.rb                      # Per-run state, hooks
    reducer.rb                                # Step execution loop
    step.rb                                   # Base step type
    steps/
      reduce_if.rb
      reduce_if_else.rb
      reduce_until.rb
      reduce_while.rb
      reduce_case.rb
      iterate.rb
      execute.rb
      add_to_context.rb
      add_aliases.rb
      with_callback.rb
    hooks.rb                                  # Hook type definitions
    rollback_strategy.rb                      # Reverse-order rollback
    localization.rb                           # Adapter-based i18n
    configuration.rb                          # Global config singleton
    errors.rb                                 # Custom error hierarchy
    testing/
      context_factory.rb                      # Test helper: context at a given step
    ai/                                       # Optional AI-agent composition
      capability.rb
      capability_registry.rb
      plan.rb
      plan_validator.rb
      plan_compiler.rb
      policy.rb
      approval_gate.rb
      audit_trail.rb
spec/
  spec_helper.rb
  actionflow_spec.rb
  workflow/
    context_spec.rb
    action_spec.rb
    action_runner_spec.rb
    reducer_spec.rb
    organizer_spec.rb
    organizer_session_spec.rb
    steps/
      reduce_if_spec.rb
      iterate_spec.rb
      ...
    ai/
      capability_registry_spec.rb
      plan_validator_spec.rb
      ...
docs/
  ARCHITECTURE.md                             # Living, updated in same commit as code
  ABSTRACTIONS.md                             # Core domain types
  blueprint.md                                # Original design document (reference only)
  adr/
    TEMPLATE.md
    0001-*.md
sig/
  actionflow.rbs                              # RBS type signatures
```

---

## 4. The Contract (expects / promises)

### 4.1 Defining an action

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

**Rules:**

1. `expects` declares keys that **must** be present in context before `#call`
   runs. Missing keys raise `ExpectedKeysMissing`.
2. `promises` declares keys that **must** be present in context after `#call`
   runs (on success). Missing keys raise `PromisedKeysMissing`.
3. Defaults are supported: `expects :flag, default: true` or
   `expects :flag, default: ->(ctx) { ctx.user.admin? }`.
4. `expects` and `promises` are verified by `ActionRunner`, not by `#call`
   itself. This is the framework's job.
5. Reserved keys (`:message`, `:error_code`, `:current_step`,
   `:organized_by`) must never appear in `expects` or `promises`.

### 4.2 Calling it

```ruby
# Direct execution (full lifecycle)
action = ChargeCard.new(payment_gateway: gateway)
result = action.execute(ctx)
# => verifies expects, runs hooks, calls #call, verifies promises

# Raw call (no lifecycle — use only in tests when intentionally bypassing)
action.call(ctx)
```

### 4.3 Organizer composition

```ruby
class Checkout
  include Workflow::Organizer

  def initialize(charge_card:, send_receipt:)
    @charge_card = charge_card
    @send_receipt = send_receipt
  end

  def call(order:, user:, amount:)
    with(order: order, user: user, amount: amount).reduce(
      @charge_card,
      @send_receipt
    )
  end
end
```

**Rules:**

1. Organizers compose **objects**, not classes. Dependencies are
   constructor-injected.
2. `with(data)` creates an `OrganizerSession`. Chain `.before_each`,
   `.after_each`, `.around_each` before `.reduce`.
3. Control-flow helpers (`reduce_if`, `iterate`, etc.) produce step objects
   that the reducer handles uniformly.

---

## 5. Data Flow Invariants (non-negotiable)

### 5.1 Context is for business data only

- Context keys hold workflow/business state: order IDs, computed values,
  flags, messages.
- **NEVER** put infrastructure (gateways, mailers, loggers, API clients) in
  context. Inject via constructors.
- **NEVER** put per-run mutable state on the action instance (e.g.
  `@current_user`). Use local variables inside `#call`.

### 5.2 Authority flow

```
Input data
    │
    ▼
Context.new(data)
    │
    ▼  each action reads/writes context keys
    │
    ▼
Context (final)
  .success? → result data in .to_h
  .failure? → .message + .error_code
```

### 5.3 Controlled failure vs exceptional failure

- `ctx.fail!("Card declined")` — controlled business failure. Stops pipeline,
  returns failed context. No exception.
- `ctx.fail_with_rollback!("Payment failed")` — controlled failure with
  compensation. Triggers reverse-order rollback of executed steps.
- `raise NetworkError` — exceptional failure. Bubbles up. The framework does
  **not** catch exceptions by default.

### 5.4 Skip semantics

- `ctx.skip_remaining!` — skip remaining steps in current scope. Context
  remains successful.
- `ctx.skip_all_remaining!` — skip all remaining steps across all nested
  scopes. Context remains successful.
- `ctx.reset_skip_remaining!` — clear skip flag. Used by control-flow steps
  to scope skip behavior.

---

## 6. Where State Lives

| State type              | Where                              | Examples                          |
| ----------------------- | ---------------------------------- | --------------------------------- |
| Workflow data           | `Workflow::Context#data`           | Input keys, computed results      |
| Action dependencies     | Action instance `@ivar`s           | Payment gateways, mailers, repos  |
| Per-run hooks           | `OrganizerSession`                 | before/after/around callbacks     |
| Global config           | `Workflow::Configuration`          | Logger, localization adapter      |
| Action contracts        | `ActionMetadata` (per-class)       | expected_keys, promised_keys      |
| Instance-specific meta  | Override `#workflow_metadata`      | Parameterized expects/promises    |

**NEVER** store per-run business state on action instances. Actions may be
reused across threads or requests.

---

## 7. Action Patterns

### 7.1 Simple action

```ruby
class CalculateTax
  include Workflow::Action

  expects :order
  promises :tax

  def call(ctx)
    ctx.tax = ctx.order.subtotal * 0.08
  end
end
```

### 7.2 Dependency-injected action

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

  def rollback(ctx)
    @payment_gateway.refund(ctx.charge) if ctx.key?(:charge)
  end
end
```

### 7.3 Parameterized action

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

### 7.4 Control-flow composition

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

## 8. Hooks and Middleware

Hooks are objects implementing `#call(action, ctx)` (before/after) or
`#call(action, ctx, &block)` (around).

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

Hooks can be registered at three levels:
1. Global configuration (`Workflow.configuration`)
2. Organizer instance
3. Specific run/session

---

## 9. Rollback

Rollback is optional and object-oriented:

- Actions may define `#rollback(ctx)` for compensation logic.
- `ctx.fail_with_rollback!` triggers rollback of all executed steps in
  reverse order.
- `RollbackStrategy` iterates executed steps, calling `#rollback` on those
  that respond to it.
- Steps without `#rollback` are silently skipped during rollback.

---

## 10. Workflow Rules

### 10.1 Branching & commits

- Work on `main`. No branches, no PRs (or follow your team's policy — but
  pick one and enforce via pre-push hook).
- Commit every 20–30 min. Conventional Commits: `feat:`, `fix:`, `refactor:`,
  `test:`, `docs:`.
- **NEVER** use `--no-verify`. If a hook blocks you, fix the cause.

### 10.2 TDD (mandatory)

Red → Green → Refactor → Commit, one cycle per commit. For bugs: failing
regression test first, then the fix.

Test quality (Kent Beck): isolated, deterministic, fast, behavioral,
structure-insensitive, specific, predictive. Fix flaky tests before adding
features.

### 10.3 Coverage gates

- ≥ 90% lines for `lib/workflow/` core.
- ≥ 80% lines for `lib/workflow/ai/` (optional module).
- Runs in pre-push and CI.

### 10.4 Code health ratchet

Track complexity via `standardrb` and a custom threshold file. Values **only
go up**. Pre-push enforces the floor.

**NEVER** lower the threshold. If the gate blocks, refactor.

**Boy Scout Rule:** every file you touch leaves with a higher (or equal-if-
already-perfect) score.

### 10.5 ADRs

Live in `docs/adr/NNNN-kebab-name.md`. Create in the same commit as the code.

**Never edit an existing ADR** — create a new one that supersedes it.

Required for: new dependency, core abstraction change, new public API,
cross-cutting pattern, AI integration model change.

Not required for: bug fixes, internal refactors, test improvements.

**Format (mandatory).** Every ADR begins with YAML frontmatter:

```yaml
---
type: ADR
id: "NNNN"
title: "Sentence-case title"
status: active  # active | superseded
date: YYYY-MM-DD
supersedes:
superseded_by:
---
```

Rules:

- `id` matches the filename's numeric prefix, zero-padded to 4 digits,
  kebab-case (`0006-some-decision.md`).
- `status` is `active` or `superseded`. No other values without an ADR
  amending this rule.
- When superseding, edit _only_ the prior ADR's `status` and `superseded_by`
  fields.

### 10.6 Docs

After any of the following, update `docs/ARCHITECTURE.md` and/or
`docs/ABSTRACTIONS.md` in the same commit:

- New public API method or module
- New core abstraction
- Contract change (expects/promises semantics)
- New control-flow step type
- AI integration change

### 10.7 Forbidden escapes

**NEVER** use any of these to silence a tool:

- `# standard:disable`
- `# rubocop:disable`
- `#noinspection`
- `--no-verify`

If the tool is wrong, fix the tool config in a dedicated commit with a
justification in the message.

---

## 11. Testing Strategy

| Layer           | Tool           | Scope                              | Runs in        |
| --------------- | -------------- | ---------------------------------- | -------------- |
| Unit specs      | RSpec          | Context, Action, Runner, Reducer   | pre-push, CI   |
| Integration     | RSpec          | Full organizer workflows           | pre-push, CI   |
| Step specs      | RSpec          | Each control-flow step type        | pre-push, CI   |
| AI specs        | RSpec          | Registry, validator, compiler      | pre-push, CI   |
| Coverage        | SimpleCov      | ≥ 90% lines (core)                 | pre-push, CI   |
| Lint            | `standardrb`   | Zero warnings                      | pre-push, CI   |

### Testing patterns

```ruby
# Direct action test with full lifecycle
action = ChargeCard.new(payment_gateway: fake_gateway)
ctx = Workflow::Context.new(user: user, amount: 100)
result = action.execute(ctx)

expect(result).to be_success
expect(result[:charge]).to eq(charge)

# Organizer integration test
checkout = Checkout.new(
  charge_card: ChargeCard.new(payment_gateway: fake_gateway),
  send_receipt: SendReceipt.new(mailer: fake_mailer)
)
result = checkout.call(order: order, user: user, amount: 100)

expect(result).to be_success
```

---

## 12. Build & Distribution

```bash
bundle install                # install dependencies
bundle exec rake spec         # run tests
bundle exec standardrb        # lint
bundle exec rake install      # install gem locally
bundle exec rake release      # tag + push to rubygems.org
```

---

## 13. Definition of Done

A task is done only when **all** of these are true:

1. Tests added (TDD): unit + integration if it touches a core flow.
2. All gates pass: lint, tests, coverage.
3. Docs updated: `ARCHITECTURE.md` / `ABSTRACTIONS.md` if applicable.
4. ADR created if the change matches §10.5.
5. Public API changes are reflected in RBS signatures.
6. Pre-push succeeds without `--no-verify`.

## 14. Think before coding

Don't assume. Don't hide confusion. State ambiguity explicitly. Present
multiple interpretations rather than silently picking one. Push back if a
simpler approach exists. Stop and ask rather than guess.

## 15. Simplicity first

No features beyond what was asked. No abstractions for single-use code. No
"flexibility" that wasn't requested. No error handling for impossible
scenarios. The test: would a senior engineer say this is overcomplicated? If
yes, rewrite it.

## 16. Surgical changes

Don't "improve" adjacent code. Don't refactor things that aren't broken. Match
the existing style even if you'd do it differently. If you notice unrelated
dead code, mention it, don't delete it. Every changed line should trace
directly to the request.

## 17. Goal-driven execution

Transform "fix the bug" into "write a test that reproduces it, then make it
pass." Transform "add validation" into "write tests for invalid inputs, then
make them pass." Give it success criteria and watch it loop until done.
