# Abstractions

> Living document. Update in the same commit as any code change that
> introduces, renames, or reshapes a core domain type. See `AGENTS.md`
> §10.6 for the rules.

This document catalogs the **core domain types** in the Actionflow workflow
engine. A type appears here only if it is referenced from more than one module
or represents a cross-cutting contract that developers interact with.

For each entry, record:
- **Purpose** — what the type represents and where it is used.
- **Shape** — the public API surface (methods, fields, DSL).
- **Invariants** — what must always be true. Tested.
- **Where it lives** — file path.

---

## `Workflow::Context` — shared workflow state

Carries all business data through a workflow pipeline. Every action reads from
and writes to the same context instance. Also tracks pipeline status (success,
failure, skip) and provides alias support for key remapping.

| Field     | Value                                 |
| --------- | ------------------------------------- |
| Purpose   | Single shared state object for a workflow run |
| Shape     | `#[key]`, `#[key]=`, `#key?`, `#keys`, `#to_h`, `#success?`, `#failure?`, `#fail!`, `#fail_with_rollback!`, `#succeed!`, `#skip_remaining!`, `#skip_all_remaining!`, `#stop_processing?`, `#reset_skip_remaining!`, `#assign_aliases` |
| Storage   | Internal `@data` hash (symbolized keys), status booleans, message, error_code |
| File      | `lib/workflow/context.rb`             |
| Spec      | `spec/workflow/context_spec.rb`       |

**Invariants:**

- All keys are stored as symbols. String keys are converted on initialization.
- Context does **not** inherit from `Hash`. It delegates through `[]`/`[]=`.
- Alias resolution is transparent: `ctx[:foo]` returns `ctx[:bar]` if
  `aliases: { foo: :bar }`.
- `fail!` sets `@success = false`. After `fail!`, `stop_processing?` returns
  `true`.
- `fail_with_rollback!` raises `FailWithRollback` in addition to marking
  failure.
- `skip_remaining!` and `skip_all_remaining!` do **not** mark failure.
  `success?` remains `true`.
- `reset_skip_remaining!` clears `@skip_remaining` and `@message` but does
  **not** change `@success` or `@skip_all_remaining`.
- `to_h` returns a shallow copy; mutation of the returned hash does not affect
  context.
- Reserved keys (`:message`, `:error_code`, `:current_step`,
  `:organized_by`) are metadata and not part of `@data`.

---

## `Workflow::ActionMetadata` — action contract descriptor

Stores the `expects` and `promises` declarations for an action class or
instance. Used by `ActionRunner` for contract verification and by
`ContextFactory` for testing support.

| Field     | Value                                 |
| --------- | ------------------------------------- |
| Purpose   | Declares what an action requires and produces |
| Shape     | `expected_keys`, `promised_keys`, `optional_keys`, `defaults` |
| File      | `lib/workflow/action_metadata.rb`     |
| Spec      | `spec/workflow/action_spec.rb` (tested via Action integration) |

**Invariants:**

- `expected_keys` and `promised_keys` are Arrays of Symbols.
- `defaults` is a Hash mapping Symbol keys to default values or callables.
- Callable defaults receive the context and are evaluated at execution time.
- Reserved keys must not appear in `expected_keys` or `promised_keys`.
- Instances may override `#workflow_metadata` to provide parameterized
  contracts (e.g., `NormalizeField`).

---

## `Workflow::Action` — action mixin

Module included into action classes. Provides the `expects`/`promises` DSL and
the `#execute` entry point.

| Field     | Value                                 |
| --------- | ------------------------------------- |
| Purpose   | Turns a plain Ruby class into a workflow action |
| Shape     | `ClassMethods#expects`, `ClassMethods#promises`, `ClassMethods#workflow_metadata`, `#workflow_metadata`, `#execute(ctx)` |
| Requires  | Including classes implement `#call(ctx)` |
| Optional  | Including classes may implement `#rollback(ctx)` |
| File      | `lib/workflow/action.rb`              |
| Spec      | `spec/workflow/action_spec.rb`        |

**Invariants:**

- `#execute(ctx)` delegates to `ActionRunner.default.call(self, ctx)`.
  It is the **only** correct entry point for framework-level execution.
- `#call(ctx)` is the raw business method. Calling it directly bypasses
  contract verification, hooks, and logging.
- `expects` may be called multiple times; keys accumulate.
- `expects :key, default: value` registers a single key with a default.
- `promises` may be called multiple times; keys accumulate.

---

## `Workflow::ActionRunner` — framework lifecycle

Wraps action execution with contract verification, hook dispatch, and error
handling. The reducer delegates to the action runner for workflow actions.

| Field     | Value                                 |
| --------- | ------------------------------------- |
| Purpose   | Owns the full execution lifecycle for a single action |
| Shape     | `#call(action, ctx)`                  |
| Constructor | `before_hooks:`, `after_hooks:`, `around_hooks:`, `logger:` |
| File      | `lib/workflow/action_runner.rb`       |
| Spec      | `spec/workflow/action_runner_spec.rb` |

**Invariants:**

- Returns `ctx` unchanged if `ctx.stop_processing?` is true.
- Sets `ctx.current_step = action` before processing.
- Applies defaults before verifying expected keys.
- Verifies expected keys **before** `#call`; raises `ExpectedKeysMissing`.
- Verifies promised keys **after** `#call` (only if `ctx.success?`);
  raises `PromisedKeysMissing`.
- Around hooks compose as a nested chain; innermost call is `action.call(ctx)`.
- Never catches exceptions from `action.call(ctx)` (except `FailWithRollback`,
  which the reducer handles).

---

## `Workflow::Reducer` — step execution loop

Iterates over an array of steps, dispatching each to the action runner or
calling directly, with rollback support.

| Field     | Value                                 |
| --------- | ------------------------------------- |
| Purpose   | Execute a sequence of steps with rollback |
| Shape     | `#reduce(ctx, steps)`                 |
| Constructor | `action_runner:`, `rollback_strategy:` |
| File      | `lib/workflow/reducer.rb`             |
| Spec      | `spec/workflow/reducer_spec.rb`       |

**Invariants:**

- Flattens the step array to support nested arrays.
- Breaks on `ctx.stop_processing?`.
- Workflow actions (respond to `#workflow_metadata`) are dispatched through
  the action runner.
- Non-workflow callables are invoked with `step.call(ctx)` directly.
- On `FailWithRollback`, delegates to `RollbackStrategy` with steps in
  reverse execution order.
- Returns `ctx` in all cases.

---

## `Workflow::Organizer` — workflow composition mixin

Module included into organizer classes. Provides `with`, `reduce`, and
control-flow builder methods.

| Field     | Value                                 |
| --------- | ------------------------------------- |
| Purpose   | Compose action objects into workflows  |
| Shape     | `#with(data)`, `#reduce(*steps)`, `#reduce_if`, `#reduce_if_else`, `#iterate`, `#execute` |
| File      | `lib/workflow/organizer.rb`           |
| Spec      | `spec/workflow/organizer_spec.rb`     |

**Invariants:**

- `with(data)` creates a `Context` (if data is a Hash) or uses an existing
  `Context` (if data is already one).
- `with(data)` returns an `OrganizerSession`, not a `Context`.
- Control-flow helpers (`reduce_if`, `iterate`, etc.) return step objects;
  they do not execute immediately.
- Organizers compose **object instances**, not classes.

---

## `Workflow::OrganizerSession` — per-run execution context

Accumulates hooks and executes the reducer. Created by `Organizer#with`.

| Field     | Value                                 |
| --------- | ------------------------------------- |
| Purpose   | Per-run hook accumulation and execution |
| Shape     | `#before_each(hook)`, `#after_each(hook)`, `#around_each(hook)`, `#reduce(*steps)` |
| File      | `lib/workflow/organizer_session.rb`   |
| Spec      | `spec/workflow/organizer_session_spec.rb` |

**Invariants:**

- `before_each`, `after_each`, `around_each` return `self` for chaining.
- `reduce` creates a fresh `ActionRunner` with the accumulated hooks and
  delegates to `Reducer#reduce`.
- `reduce` returns the final `Context`.

---

## `Workflow::RollbackStrategy` — compensation executor

Walks executed steps in reverse order, calling `#rollback` where available.

| Field     | Value                                 |
| --------- | ------------------------------------- |
| Purpose   | Execute compensating actions on failure |
| Shape     | `#rollback(ctx, executed_steps)`       |
| File      | `lib/workflow/rollback_strategy.rb`   |
| Spec      | `spec/workflow/reducer_spec.rb` (tested via reducer rollback scenarios) |

**Invariants:**

- Iterates steps in reverse execution order.
- Calls `#rollback(ctx)` only on steps that `respond_to?(:rollback)`.
- Does not raise on steps without `#rollback`.
- Returns `ctx`.

---

## `Workflow::Steps::ReduceIf` — conditional execution

Runs a set of steps only if a condition lambda returns truthy.

| Field     | Value                                 |
| --------- | ------------------------------------- |
| Purpose   | Conditional step execution            |
| Shape     | `#call(ctx)`                          |
| Constructor | `condition` (callable), `steps` (array) |
| File      | `lib/workflow/steps/reduce_if.rb`     |
| Spec      | `spec/workflow/steps/reduce_if_spec.rb` |

**Invariants:**

- Returns `ctx` unchanged if `ctx.stop_processing?`.
- Creates a scoped reducer for the nested steps.
- Resets `skip_remaining` on exit (unless failure or `skip_all_remaining`).

---

## `Workflow::Steps::Iterate` — collection iteration

Runs a set of steps for each item in a context collection.

| Field     | Value                                 |
| --------- | ------------------------------------- |
| Purpose   | Iterate over a context collection     |
| Shape     | `#call(ctx)`                          |
| Constructor | `collection_key`, `steps`, `item_key:` (optional) |
| File      | `lib/workflow/steps/iterate.rb`       |
| Spec      | `spec/workflow/steps/iterate_spec.rb` |

**Invariants:**

- `item_key` defaults to singularized `collection_key` (strip trailing 's').
- Sets `ctx[item_key] = item` for each iteration.
- Breaks on `ctx.stop_processing?`.
- Creates a scoped reducer for nested steps per item.

---

## `Workflow::Errors` — error hierarchy

Custom error classes for the framework.

| Error                | Purpose                                    |
| -------------------- | ------------------------------------------ |
| `ExpectedKeysMissing`| Raised when expected keys are absent from context |
| `PromisedKeysMissing`| Raised when promised keys are absent after action execution |
| `FailWithRollback`   | Raised by `ctx.fail_with_rollback!` to trigger compensation |

**Invariants:**

- All errors inherit from `StandardError`.
- `FailWithRollback` is caught by the reducer, not by the action runner.
- `ExpectedKeysMissing` and `PromisedKeysMissing` include the missing key
  names in their messages.

---

## (Add new abstractions above this line in the order they were introduced. Each must cite the commit/ADR that established it.)
