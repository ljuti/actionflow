# Implementation Status

> Living document tracking blueprint coverage. Update in the same commit as any feature work.
> Source of truth: `docs/blueprint.md` (36 sections).

---

## Fully Implemented

| Section | Feature | File |
|---|---|---|
| §5 | Context core (`[]`, `[]=`, `key?`, `to_h`, `fail!`, `skip_*`, aliases, `fail_with_rollback!`, dynamic accessors) | `lib/workflow/context.rb` |
| §6 | Action module (`expects`, `promises`, `workflow_metadata`, `execute`, `describe`) | `lib/workflow/action.rb` |
| §6 | ActionMetadata (`expected_keys`, `promised_keys`, `defaults`) | `lib/workflow/action_metadata.rb` |
| §7 | ActionRunner full lifecycle (defaults, verify, hooks, call, verify promised) | `lib/workflow/action_runner.rb` |
| §8 | Reducer (step dispatch, rollback on `FailWithRollback`) | `lib/workflow/reducer.rb` |
| §9 | Organizer (`with`, `reduce`, control-flow builders, `describe`) | `lib/workflow/organizer.rb` |
| §9 | OrganizerSession (hook accumulation, chained reduce) | `lib/workflow/organizer_session.rb` |
| §10 | Step base class (stop guard, `scoped_reduce`, hook propagation) | `lib/workflow/step.rb` |
| §10 | All 10 control-flow steps | `lib/workflow/steps/*.rb` |
| §11 | Session-level hooks (`before_each`, `after_each`, `around_each`) | `lib/workflow/organizer_session.rb` |
| §12 | Rollback (`fail_with_rollback!`, `FailWithRollback`, reverse-order compensation) | `lib/workflow/context.rb`, `lib/workflow/reducer.rb` |
| §13 | Contracts (expects, promises, defaults, callable defaults) | `lib/workflow/action.rb`, `lib/workflow/action_runner.rb` |
| §14 | Instance-specific metadata (override `#workflow_metadata`) | `lib/workflow/action.rb` |
| §16 | Localization (adapter-based, `NullAdapter`, `HashAdapter`) | `lib/workflow/localization.rb` |
| §18 | ContextFactory | `lib/workflow/testing/context_factory.rb` |
| §18 | RSpec matchers (`expect_keys`, `promise_keys`, `have_context_value`) | `lib/workflow/testing/rspec_matchers.rb` |
| §26 | Capability | `lib/workflow/ai/capability.rb` |
| §26 | CapabilityRegistry | `lib/workflow/ai/capability_registry.rb` |
| §28 | Plan | `lib/workflow/ai/plan.rb` |
| §29 | PlanValidator (recursive validation, nested control-flow, branch key tracking) | `lib/workflow/ai/plan_validator.rb` |
| §30 | PlanCompiler | `lib/workflow/ai/plan_compiler.rb` |
| §32 | DynamicOrganizer | `lib/workflow/ai/dynamic_organizer.rb` |

---

## Implemented Gaps (Previously Required by Blueprint AND AGENTS.md)

### 1. Reserved keys enforcement ✅
- **Section:** §13, AGENTS.md §4.1 rule 5
- Raises `ArgumentError` at class definition time for reserved keys in `expects` or `promises`.

### 2. Global hooks ✅
- **Section:** §11, AGENTS.md §8
- Hooks at 2 levels: (1) Global configuration, (2) Session. Global hooks prepend to session hooks.

### 3. Logger integration ✅
- **Section:** §17
- `ActionRunner` logs `[Workflow] executing ClassName` when a logger is configured.

### 4. Explicit `break` after rollback ✅
- **Section:** §8
- Reducer breaks immediately after rollback. The `break` is also guarded by `stop_processing?`.

---

## Implemented Enhancements

### 5. Dynamic context accessors ✅
- **Section:** §5
- `method_missing` / `respond_to_missing?` on Context. Getter reads by key, setter writes by key, `NoMethodError` for unknown getters.

### 6. RSpec matchers ✅
- **Section:** §18
- `Workflow::Testing::RSpecMatchers` — `expect_keys`, `promise_keys`, `have_context_value`. Include in RSpec config or per-example group.

### 7. Introspection / `describe` API ✅
- **Section:** §17
- `Action#describe` returns `{name:, expects:, promises:}`. `Organizer#describe(steps)` returns array of metadata for all steps.

### 8. `capture_exceptions` config ✅
- **Section:** §15
- `Configuration#capture_exceptions = true` converts exceptions to failed contexts (`ctx.fail!(message, error_code: class_name)`). `FailWithRollback` always re-raised. Default: `nil` (exceptions bubble).

---

## Gaps — Out of Scope (Optional Module / Rails)

### 9. Rails generators
- **Section:** §19
- **Status:** ❌ Not applicable to a standalone gem.

### 10. AI: Policy
- **Section:** §31
- **Status:** ❌ File does not exist. Listed in AGENTS.md layout.

### 11. AI: ApprovalGate
- **Section:** §31
- **Status:** ❌ File does not exist. Listed in AGENTS.md layout.

### 12. AI: AuditTrail
- **Section:** §31
- **Status:** ❌ File does not exist. Listed in AGENTS.md layout.

### 13. AI: DryRunRunner
- **Section:** §31
- **Status:** ❌ File does not exist. Listed in AGENTS.md layout.

---

## Minor Discrepancies (Implementation Differs From Blueprint)

| Item | Blueprint | Implementation | Impact |
|---|---|---|---|
| `resolve_alias` | `@aliases.key(key) \|\| key` | `@aliases.fetch(key, key)` | Implementation is correct; blueprint had a subtle bug |
| `OrganizerSession` constructor | `(organizer, ctx)` | `(ctx)` | Organizer param was never used |
| `Context#initialize` | `data = {}` | `data = nil` | Handles nil via `data.to_h` |
| `ActionMetadata.optional_keys` | Declared | Removed | Dead code — never used by any production path |
| `RollbackStrategy` | Separate class | Inlined into `Reducer#rollback` | Over-abstracted for a single call site |
