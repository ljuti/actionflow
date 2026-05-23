# Implementation Plan — Test-Driven Development

This plan breaks the Actionflow gem into 8 phases, ordered by the component
dependency graph. Each phase lists the **test file to write first**, the
specific test cases (Red), the minimum implementation to pass (Green), and the
refactor opportunities.

**Rule: Red → Green → Refactor → Commit.** One cycle per commit.

---

## Phase 1: Foundation (no dependencies)

Build the leaf types that everything else depends on.

### 1.1 `Workflow::Errors`

**Test file:** `spec/workflow/errors_spec.rb` (create directory first)

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | `ExpectedKeysMissing` inherits from `StandardError` | kind check |
| 2 | `ExpectedKeysMissing` message includes missing key names | `raise` + message match |
| 3 | `PromisedKeysMissing` inherits from `StandardError` | kind check |
| 4 | `PromisedKeysMissing` message includes missing key names | `raise` + message match |
| 5 | `FailWithRollback` inherits from `StandardError` | kind check |

**Implementation:** `lib/workflow/errors.rb`

```ruby
module Workflow
  class ExpectedKeysMissing < StandardError; end
  class PromisedKeysMissing < StandardError; end
  class FailWithRollback < StandardError; end
end
```

### 1.2 `Workflow::ActionMetadata`

**Test file:** `spec/workflow/action_metadata_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Default initialization | all four fields are empty collections |
| 2 | Initialization with keyword args | fields reflect constructor args |
| 3 | `expected_keys` returns an Array of Symbols | type + content |
| 4 | `promised_keys` returns an Array of Symbols | type + content |
| 5 | `defaults` returns a Hash | type + content |

**Implementation:** `lib/workflow/action_metadata.rb`

### 1.3 `Workflow::Configuration`

**Test file:** `spec/workflow/configuration_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Default `logger` is nil | `config.logger.nil?` |
| 2 | Default `localization_adapter` is nil | `config.localization_adapter.nil?` |
| 3 | Default `strict_context_access` is false | `config.strict_context_access == false` |
| 4 | `Workflow.configure` yields a Configuration instance | block yields config, values stick |
| 5 | `Workflow.configuration` returns same instance | identity check |

**Implementation:** `lib/workflow/configuration.rb` + wire into `lib/actionflow.rb`

**Commit point:** All foundation specs green. `bundle exec rake spec` passes.

---

## Phase 2: Context

Context is the data carrier. It depends only on Errors (for `FailWithRollback`).

### 2.1 `Workflow::Context` — core

**Test file:** `spec/workflow/context_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Initialize with hash data | `ctx[:foo] == "bar"` |
| 2 | Initialize with empty hash | `ctx.keys == []` |
| 3 | String keys are symbolized on init | `Context.new("foo" => 1)[:foo] == 1` |
| 4 | `[]=` writes a value | `ctx[:x] = 1; ctx[:x] == 1` |
| 5 | `key?` returns true for present key | `ctx.key?(:foo)` |
| 6 | `key?` returns false for absent key | `ctx.key?(:missing) == false` |
| 7 | `keys` returns all symbol keys | `ctx.keys == [:a, :b]` |
| 8 | `to_h` returns a shallow copy | `ctx.to_h != ctx.data.object_id`; mutation of copy doesn't affect ctx |
| 9 | `to_h` does not return internal state | modifying returned hash doesn't affect context |
| 10 | New context is successful | `ctx.success? == true`, `ctx.failure? == false` |

### 2.2 `Workflow::Context` — failure

| # | Test case | Asserts |
|---|-----------|---------|
| 11 | `fail!` marks failure | `ctx.success? == false`, `ctx.failure? == true` |
| 12 | `fail!` sets message | `ctx.message == "boom"` |
| 13 | `fail!` sets error_code | `ctx.error_code == :timeout` |
| 14 | `fail!` without args | `ctx.message.nil?`, `ctx.error_code.nil?` |
| 15 | `fail!` makes `stop_processing?` true | `ctx.stop_processing? == true` |
| 16 | `succeed!` sets success and message | `ctx.succeed!("ok"); ctx.success? && ctx.message == "ok"` |

### 2.3 `Workflow::Context` — skip

| # | Test case | Asserts |
|---|-----------|---------|
| 17 | `skip_remaining!` sets message | `ctx.message == "skip"` |
| 18 | `skip_remaining!` does not mark failure | `ctx.success? == true` |
| 19 | `skip_remaining!` makes `stop_processing?` true | via `skip_remaining?` |
| 20 | `skip_all_remaining!` makes `stop_processing?` true | via `skip_all_remaining?` |
| 21 | `skip_all_remaining!` does not mark failure | `ctx.success? == true` |
| 22 | `reset_skip_remaining!` clears skip and message | both reset |
| 23 | `reset_skip_remaining!` does not change success | still successful |
| 24 | `reset_skip_remaining!` does not clear `skip_all_remaining` | `skip_all_remaining?` stays true if set |

### 2.4 `Workflow::Context` — aliases

| # | Test case | Asserts |
|---|-----------|---------|
| 25 | `assign_aliases` maps key to another key | `ctx[:alias]` reads `ctx[:original]` |
| 26 | `[]=` through alias writes to original key | `ctx[:alias] = val; ctx[:original] == val` |
| 27 | `key?` resolves alias | `ctx.key?(:alias) == true` when original exists |
| 28 | Unresolved key returns self | `resolve_alias(:unknown) == :unknown` |

### 2.5 `Workflow::Context` — `fail_with_rollback!`

| # | Test case | Asserts |
|---|-----------|---------|
| 29 | `fail_with_rollback!` marks failure and raises `FailWithRollback` | `expect { ctx.fail_with_rollback! }.to raise_error(Workflow::FailWithRollback)` |
| 30 | `fail_with_rollback!` sets message | after rescue, `ctx.message == "Payment failed"` |
| 31 | `fail_with_rollback!` sets error_code | after rescue, `ctx.error_code == :gateway_timeout` |

### 2.6 `Workflow::Context` — metadata accessors

| # | Test case | Asserts |
|---|-----------|---------|
| 32 | `current_step` is nil by default | `ctx.current_step.nil?` |
| 33 | `current_step` can be set | `ctx.current_step = :step; ctx.current_step == :step` |
| 34 | `organized_by` is nil by default | `ctx.organized_by.nil?` |
| 35 | `organized_by` can be set | `ctx.organized_by = organizer` |

**Implementation:** `lib/workflow/context.rb`

**Commit point:** All context specs green. 35 test cases.

---

## Phase 3: ActionRunner + Action

These two have a runtime dependency cycle (Action's `#execute` calls
ActionRunner), but no load-time cycle. Build ActionRunner first (it doesn't
`require` Action — it just calls methods on passed objects), then Action.

### 3.1 `Workflow::ActionRunner`

**Test file:** `spec/workflow/action_runner_spec.rb`

Use test doubles (plain objects with `Workflow::Action` included or simple
structs that respond to `#call`, `#workflow_metadata`).

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Calls action's `#call(ctx)` | spy verifies call received |
| 2 | Returns context | `runner.call(action, ctx) == ctx` |
| 3 | Returns ctx unchanged if `stop_processing?` | action never called |
| 4 | Sets `ctx.current_step` to action before calling | `ctx.current_step == action` |
| 5 | Applies defaults from metadata | missing key gets default value |
| 6 | Applies callable defaults | lambda receives ctx |
| 7 | Does not overwrite existing keys with defaults | pre-set value preserved |
| 8 | Raises `ExpectedKeysMissing` when keys absent | `expect { runner.call(action, ctx) }.to raise_error(Workflow::ExpectedKeysMissing)` |
| 9 | Error message lists missing keys | message includes key names |
| 10 | Raises `PromisedKeysMissing` when keys absent after call | action that doesn't set promised key |
| 11 | Does NOT verify promised keys on failure | action calls `fail!`, no `PromisedKeysMissing` |
| 12 | `.default` returns a new runner | `ActionRunner.default` works |
| 13 | Runs before hooks in order | two spies, verify call order |
| 14 | Runs after hooks in order | two spies, verify call order |
| 15 | Around hooks wrap `action.call` | spy verifies pre/post execution |
| 16 | Multiple around hooks compose correctly | outer wraps inner |
| 17 | No hooks — still works | empty hook arrays |

**Implementation:** `lib/workflow/action_runner.rb`

### 3.2 `Workflow::Action` module

**Test file:** `spec/workflow/action_spec.rb`

Define disposable test action classes inside the spec.

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | `expects` registers expected keys on class | `TestClass.workflow_metadata.expected_keys == [:a, :b]` |
| 2 | `expects` with `default:` registers key + default | `metadata.expected_keys.include?(:flag)` and `metadata.defaults[:flag] == true` |
| 3 | `expects :key, default: ->(ctx) { ... }` stores callable | `metadata.defaults[:key].respond_to?(:call)` |
| 4 | `promises` registers promised keys | `metadata.promised_keys == [:result]` |
| 5 | Multiple `expects` calls accumulate keys | two separate calls, all keys present |
| 6 | Instance `#workflow_metadata` delegates to class | `action.workflow_metadata == ActionClass.workflow_metadata` |
| 7 | `#execute(ctx)` delegates to ActionRunner | `action.execute(ctx)` returns ctx |
| 8 | `#execute(ctx)` verifies expected keys | missing key → `ExpectedKeysMissing` |
| 9 | `#execute(ctx)` verifies promised keys | not set → `PromisedKeysMissing` |
| 10 | `#execute(ctx)` defaults to `Context.new` if no arg | `action.execute` doesn't raise on nil |
| 11 | Action with `#rollback` defined | `action.respond_to?(:rollback) == true` |
| 12 | Action without `#rollback` | `action.respond_to?(:rollback) == false` |
| 13 | Instance-specific metadata override | custom `#workflow_metadata` returns different metadata |

**Implementation:** `lib/workflow/action.rb`

**Commit point:** All ActionRunner + Action specs green. 30 test cases.

---

## Phase 4: Reducer + RollbackStrategy + Organizer

The pipeline that ties actions together.

### 4.1 `Workflow::RollbackStrategy`

**Test file:** `spec/workflow/rollback_strategy_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Calls `#rollback(ctx)` on steps that respond | spy receives `rollback` call |
| 2 | Skips steps without `#rollback` | no error raised |
| 3 | Iterates in reverse order | three spies, verify order is 3→2→1 |
| 4 | Returns ctx | `strategy.rollback(ctx, steps) == ctx` |

**Implementation:** `lib/workflow/rollback_strategy.rb`

### 4.2 `Workflow::Reducer`

**Test file:** `spec/workflow/reducer_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Executes steps in order | two spies, verify order |
| 2 | Returns ctx | `reducer.reduce(ctx, steps) == ctx` |
| 3 | Breaks on `ctx.stop_processing?` | second spy never called after `fail!` |
| 4 | Dispatches workflow actions through ActionRunner | action with metadata goes through runner |
| 5 | Calls plain callables directly | lambda `->(ctx) { ... }` is invoked |
| 6 | Flattens nested step arrays | `[[step1], [step2]]` works as `[step1, step2]` |
| 7 | Empty steps — returns ctx unchanged | `reducer.reduce(ctx, []) == ctx` |
| 8 | `FailWithRollback` triggers rollback in reverse | spy verifies rollback called |
| 9 | After rollback, reducer breaks out of loop | no further steps execute |
| 10 | `FailWithRollback` — only rolled-back steps receive rollback | step after rollback not touched |

**Implementation:** `lib/workflow/reducer.rb`

### 4.3 `Workflow::OrganizerSession`

**Test file:** `spec/workflow/organizer_session_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | `reduce` returns context | session returns ctx |
| 2 | `reduce` executes steps | spy verifies call |
| 3 | `before_each` accumulates and applies hooks | hook spy called |
| 4 | `after_each` accumulates and applies hooks | hook spy called |
| 5 | `around_each` accumulates and applies hooks | hook spy wraps action |
| 6 | Hook methods return `self` for chaining | `session.before_each(hook) == session` |
| 7 | Steps are flattened | nested array works |

**Implementation:** `lib/workflow/organizer_session.rb`

### 4.4 `Workflow::Organizer` module

**Test file:** `spec/workflow/organizer_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | `with(hash)` creates OrganizerSession with Context | session.ctx is a Context |
| 2 | `with(Context)` uses Context directly | same object identity |
| 3 | `with` sets `ctx.organized_by` to self | `ctx.organized_by == organizer` |
| 4 | `with` returns OrganizerSession | kind check |
| 5 | `reduce` shortcut works | `organizer.reduce(step)` returns ctx |
| 6 | `reduce_if` returns a ReduceIf step | kind check (stub ReduceIf for now) |
| 7 | `reduce_if_else` returns a ReduceIfElse step | kind check |
| 8 | `iterate` returns an Iterate step | kind check |
| 9 | `execute` returns an Execute step | kind check |

### 4.5 Integration: full workflow

**Test file:** `spec/workflow/integration_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Three actions in sequence, data flows through | final ctx has all promised keys |
| 2 | Dependency-injected actions work | action with constructor dep |
| 3 | Organizer with DI actions | `Checkout.new(charge_card: ...).call(...)` |
| 4 | Failure stops pipeline | `fail!` in step 2 → step 3 never called |
| 5 | `fail!` message propagates to result | `result.message == "Cart is empty"` |
| 6 | Lambda as step works | `->(ctx) { ctx[:computed] = true }` |
| 7 | Nested organizer as step works | organizer A includes organizer B as step |

**Commit point:** Full pipeline working. ~50 test cases across Phase 4.

---

## Phase 5: Control-Flow Steps

Each step is self-contained. Build them one at a time, TDD each.

### 5.1 `Workflow::Steps::ReduceIf`

**Test file:** `spec/workflow/steps/reduce_if_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Runs steps when condition is truthy | spy called |
| 2 | Skips steps when condition is falsy | spy NOT called |
| 3 | Returns ctx unchanged if `stop_processing?` | early return |
| 4 | Resets `skip_remaining` on exit | `skip_remaining?` is false after block |
| 5 | Does not reset `skip_remaining` on failure | failure stays |
| 6 | Does not reset `skip_remaining` on `skip_all_remaining` | global skip stays |

### 5.2 `Workflow::Steps::ReduceIfElse`

**Test file:** `spec/workflow/steps/reduce_if_else_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Runs if-steps when condition is truthy | if-spy called, else-spy NOT called |
| 2 | Runs else-steps when condition is falsy | else-spy called, if-spy NOT called |
| 3 | Returns ctx unchanged if `stop_processing?` | early return |

### 5.3 `Workflow::Steps::Iterate`

**Test file:** `spec/workflow/steps/iterate_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Runs steps for each item | spy called 3 times for 3-item collection |
| 2 | Sets item_key from singularized collection_key | `:items` → `:item` |
| 3 | Custom `item_key:` overrides default | `ctx[:custom_key]` is set |
| 4 | Breaks on `stop_processing?` | only first items processed |
| 5 | Empty collection — no steps run | spy never called |

### 5.4 `Workflow::Steps::ReduceWhile`

**Test file:** `spec/workflow/steps/reduce_while_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Runs steps while condition is true | runs N times |
| 2 | Stops when condition becomes false | stops, ctx is successful |
| 3 | Returns ctx unchanged if `stop_processing?` | early return |

### 5.5 `Workflow::Steps::ReduceUntil`

**Test file:** `spec/workflow/steps/reduce_until_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Runs steps until condition is true | runs until satisfied |
| 2 | Stops when condition becomes true | stops, ctx is successful |

### 5.6 `Workflow::Steps::ReduceCase`

**Test file:** `spec/workflow/steps/reduce_case_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Runs steps matching the value | matching branch runs |
| 2 | No match — no steps run | all branches skipped |
| 3 | First match wins | second match not run |

### 5.7 `Workflow::Steps::Execute`

**Test file:** `spec/workflow/steps/execute_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Executes block with ctx | block receives ctx |
| 2 | Returns ctx | `step.call(ctx) == ctx` |
| 3 | Block can modify ctx | `ctx[:added] == true` |

### 5.8 `Workflow::Steps::AddToContext`

**Test file:** `spec/workflow/steps/add_to_context_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Adds key-value pairs to context | `ctx[:new_key] == "value"` |
| 2 | Overwrites existing keys | new value present |

### 5.9 `Workflow::Steps::AddAliases`

**Test file:** `spec/workflow/steps/add_aliases_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Registers aliases on context | `ctx[:alias]` resolves to `ctx[:original]` |

### 5.10 `Workflow::Steps::WithCallback`

**Test file:** `spec/workflow/steps/with_callback_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Runs steps, stores callback in context | `ctx[:callback].respond_to?(:call)` |
| 2 | Callback, when invoked, runs callback steps | callback steps execute |

### 5.11 Integration: control-flow composition

**Test file:** `spec/workflow/steps/composition_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | `reduce_if` + `iterate` composition | complex workflow executes correctly |
| 2 | Nested `reduce_if_else` inside `iterate` | branching per item |
| 3 | Organizer helper methods produce correct step types | `reduce_if`, `iterate` from organizer |

**Commit point:** All control-flow steps green. ~50 test cases.

---

## Phase 6: Hooks Deep Dive

Expand ActionRunner hook support with integration tests.

**Test file:** `spec/workflow/hooks_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Before hook receives action and ctx | hook args verified |
| 2 | After hook receives action and ctx | hook args verified |
| 3 | Around hook wraps action.call | timing verified (before + after) |
| 4 | Multiple around hooks compose correctly | order: outer → inner → action → inner → outer |
| 5 | Hooks registered at session level override defaults | session hooks active |
| 6 | Around hook with `fail!` inside action | hook still completes (after portion runs) |
| 7 | `LogDuration`-style around hook works | real example from blueprint |
| 8 | Hook sees `ctx.current_step` set | `ctx.current_step` is the action |

**Implementation:** No new files — expand `ActionRunner` and `OrganizerSession` as needed.

**Commit point:** Hook integration green.

---

## Phase 7: Localization + Testing Helpers

### 7.1 `Workflow::Localization`

**Test file:** `spec/workflow/localization_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Null adapter passes messages through | `adapter.failure("msg", nil, {}) == "msg"` |
| 2 | Hash adapter resolves key | lookup from hash catalog |
| 3 | Hash adapter falls back to raw message | unknown key returns message |
| 4 | `I18n` adapter delegates to I18n.t | mock I18n, verify delegation |
| 5 | Configuration sets adapter | `Workflow.configuration.localization_adapter` sticks |
| 6 | `fail!` uses adapter when configured | message is translated |

**Implementation:** `lib/workflow/localization.rb`

### 7.2 `Workflow::Testing::ContextFactory`

**Test file:** `spec/workflow/testing/context_factory_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Builds context up to a specific action instance | context has keys from preceding actions |
| 2 | Builds context up to a specific action class | lookup by class |
| 3 | `.with` overrides context values | supplied values present |
| 4 | Works with dependency-injected organizer | actions with constructor deps |

**Implementation:** `lib/workflow/testing/context_factory.rb`

### 7.3 RSpec matchers (optional)

**Test file:** `spec/workflow/testing/matchers_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | `expect_keys` matcher passes | `expect(action).to expect_keys(:a, :b)` |
| 2 | `expect_keys` matcher fails on mismatch | negative case |
| 3 | `promise_keys` matcher passes | `expect(action).to promise_keys(:result)` |
| 4 | `have_context_value` matcher | `expect(ctx).to have_context_value(:key)` |

**Implementation:** `lib/workflow/testing/matchers.rb`

**Commit point:** Localization + testing helpers green.

---

## Phase 8: AI-Agent Composition (Optional Module)

This is a self-contained module under `Workflow::Ai`. Each component is
independent and can be built in any order.

### 8.1 `Workflow::Ai::Capability`

**Test file:** `spec/workflow/ai/capability_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Wraps action with metadata | id, description, expects, promises |
| 2 | Exposes `side_effects`, `risk`, `requires_approval` | metadata fields |
| 3 | `to_description` returns sanitized JSON-safe hash | no action object leaked |

### 8.2 `Workflow::Ai::CapabilityRegistry`

**Test file:** `spec/workflow/ai/capability_registry_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Register and fetch by id | `registry.fetch(:find_order)` returns capability |
| 2 | Fetch unknown raises error | `registry.fetch(:unknown)` raises |
| 3 | `descriptions` returns all sanitized descriptions | array of hashes, no actions |
| 4 | Duplicate id overwrites | last registration wins |

### 8.3 `Workflow::Ai::Plan`

**Test file:** `spec/workflow/ai/plan_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Parses linear plan from hash | steps extracted |
| 2 | Parses conditional plan | if/then/else structure preserved |
| 3 | Parses iteration plan | collection + steps preserved |
| 4 | Rejects invalid plan structure | raises on malformed input |

### 8.4 `Workflow::Ai::PlanValidator`

**Test file:** `spec/workflow/ai/plan_validator_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Valid linear plan passes | `validation.safe? == true` |
| 2 | Unknown step id fails validation | error lists unknown id |
| 3 | Missing expected keys detected | error lists missing keys at step |
| 4 | Promised keys added to simulated key set | subsequent step sees new keys |
| 5 | High-risk step triggers approval flag | `validation.requires_approval? == true` |

### 8.5 `Workflow::Ai::PlanCompiler`

**Test file:** `spec/workflow/ai/plan_compiler_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Compiles linear plan to action objects | array of actions from registry |
| 2 | Compiles conditional plan to ReduceIfElse | correct step type |
| 3 | Compiles iteration plan to Iterate | correct step type |

### 8.6 `Workflow::Ai::DynamicOrganizer`

**Test file:** `spec/workflow/ai/dynamic_organizer_spec.rb`

| # | Test case | Asserts |
|---|-----------|---------|
| 1 | Executes compiled steps | full pipeline |
| 2 | Hooks applied | before/after/around work |
| 3 | Returns context | standard result |

**Commit point:** AI module green. Entire gem test suite passing.

---

## Dependency Graph (build order)

```
Errors ─────────────────────┐
ActionMetadata ─────────────┤
Configuration ──────────────┤
                             ▼
                     ┌── Context ────┐
                     │               │
              RollbackStrategy   ActionRunner
                     │               │
                     └── Reducer ←───┘
                          │
                   OrganizerSession
                          │
                      Organizer
                          │
                    Steps::* (10 classes)
                          │
                  Hooks integration
                          │
               Localization + Testing
                          │
                  AI::* (6 classes)
```

## Summary

| Phase | Components | Test files | Est. test cases |
|-------|-----------|------------|----------------|
| 1. Foundation | Errors, ActionMetadata, Configuration | 3 | ~15 |
| 2. Context | Context | 1 | ~35 |
| 3. Runner+Action | ActionRunner, Action | 2 | ~30 |
| 4. Pipeline | RollbackStrategy, Reducer, OrganizerSession, Organizer, Integration | 5 | ~50 |
| 5. Steps | 10 step classes + composition | 11 | ~50 |
| 6. Hooks | Hook integration | 1 | ~8 |
| 7. Localization+Testing | Localization, ContextFactory, Matchers | 3 | ~15 |
| 8. AI | 6 AI classes | 6 | ~20 |
| **Total** | **~30 components** | **~32 spec files** | **~223 test cases** |

Each test case is a Red-Green-Refactor cycle. Commit after each cycle or
group of closely-related cycles.
