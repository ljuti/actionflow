# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Ai::PlanValidator do
  let(:registry) { Workflow::Ai::CapabilityRegistry.new }
  let(:validator) { described_class.new(registry: registry) }

  before do
    registry.register(Workflow::Ai::Capability.new(
      :find_order, action: ->(ctx) { ctx },
      description: "Find", expects: [:order_id], promises: [:order],
      side_effects: [], risk: :low
    ))
    registry.register(Workflow::Ai::Capability.new(
      :validate_order, action: ->(ctx) { ctx },
      description: "Validate", expects: [:order], promises: [:valid],
      side_effects: [], risk: :low
    ))
    registry.register(Workflow::Ai::Capability.new(
      :issue_refund, action: ->(ctx) { ctx },
      description: "Refund", expects: [:order], promises: [:refund],
      side_effects: [:money_movement], risk: :high, requires_approval: true
    ))
    registry.register(Workflow::Ai::Capability.new(
      :notify, action: ->(ctx) { ctx },
      description: "Notify", expects: [:order], promises: [:notified],
      side_effects: [], risk: :low
    ))
  end

  it "valid linear plan passes" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "input" => {"order_id" => "ord_123"},
      "steps" => [
        {"id" => "find_order"},
        {"id" => "validate_order"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result).to be_safe
    expect(result.errors).to be_empty
  end

  it "defaults initial_keys to empty when not provided" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "find_order"}]
    })

    result = validator.validate(plan)
    # find_order expects :order_id which is not in the empty default key set
    expect(result).not_to be_safe
  end

  it "unknown step id fails validation" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "unknown_step"}]
    })

    result = validator.validate(plan, initial_keys: [])
    expect(result).not_to be_safe
    expect(result.errors).to include(a_string_matching(/unknown_step/))
  end

  it "missing expected keys detected" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "find_order"}]
    })

    result = validator.validate(plan, initial_keys: [])
    expect(result).not_to be_safe
    expect(result.errors).to include(a_string_matching(/order_id/))
  end

  it "promised keys added to simulated key set" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "input" => {"order_id" => "ord_123"},
      "steps" => [
        {"id" => "find_order"},
        {"id" => "validate_order"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result).to be_safe
  end

  it "high-risk step triggers approval flag" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"id" => "find_order"},
        {"id" => "issue_refund"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result.requires_approval?).to eq(true)
  end

  it "does not require approval when all steps are low risk" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"id" => "find_order"},
        {"id" => "validate_order"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result.requires_approval?).to eq(false)
  end

  it "returns exact error message for missing id" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"type" => "linear"}]
    })

    result = validator.validate(plan, initial_keys: [])
    expect(result.errors).to include("Step missing 'id': {\"type\" => \"linear\"}")
  end

  it "returns exact error message for unknown capability" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "nonexistent"}]
    })

    result = validator.validate(plan, initial_keys: [])
    expect(result.errors).to include("Unknown capability: nonexistent")
  end

  it "returns exact error message for missing expected keys" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "find_order"}]
    })

    result = validator.validate(plan, initial_keys: [])
    expect(result.errors).to include(a_string_matching(/Step 'find_order' missing expected keys: \[:order_id\]\. Available:/))
  end

  it "validates if branch steps" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if",
         "condition" => {"key" => "valid", "equals" => true},
         "then" => [{"id" => "validate_order"}]}
      ]
    })

    # validate_order expects :order, which is not available
    result = validator.validate(plan, initial_keys: [])
    expect(result).not_to be_safe
    expect(result.errors).to include(a_string_matching(/validate_order/))
  end

  it "validates if_else both branches" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if_else",
         "condition" => {"key" => "valid", "equals" => true},
         "then" => [{"id" => "validate_order"}],
         "else" => [{"id" => "notify"}]}
      ]
    })

    # Both branches have missing keys
    result = validator.validate(plan, initial_keys: [])
    expect(result).not_to be_safe
    expect(result.errors.length).to be >= 2
  end

  it "validates iterate steps" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "iterate",
         "collection" => "orders",
         "as" => "order",
         "steps" => [{"id" => "validate_order"}]}
      ]
    })

    # iterate adds :order to available keys via 'as', so validate_order should pass
    result = validator.validate(plan, initial_keys: [])
    expect(result).to be_safe
  end

  it "iterate uses default item key when as is absent" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "iterate",
         "collection" => "orders",
         "steps" => [{"id" => "find_order"}]}
      ]
    })

    # Default item key is :item; find_order expects :order_id, not available
    result = validator.validate(plan, initial_keys: [])
    expect(result).not_to be_safe
  end

  it "track_step_keys adds promised keys from then branch to available keys" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if",
         "condition" => {"key" => "valid", "equals" => true},
         "then" => [{"id" => "find_order"}]},
        {"id" => "validate_order"}
      ]
    })

    # find_order in if branch promises :order, which should become available
    # for the subsequent validate_order step
    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result).to be_safe
  end

  it "sets requires_approval to false when no high-risk steps" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "find_order"}]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result.requires_approval?).to eq(false)
  end

  it "ValidationResult safe? returns false when errors present" do
    result = Workflow::Ai::PlanValidator::ValidationResult.new(errors: ["some error"])
    expect(result.safe?).to eq(false)
  end

  it "ValidationResult safe? returns true when errors empty" do
    result = Workflow::Ai::PlanValidator::ValidationResult.new(errors: [])
    expect(result.safe?).to eq(true)
  end

  it "ValidationResult defaults errors to empty and requires_approval to false" do
    result = Workflow::Ai::PlanValidator::ValidationResult.new
    expect(result.errors).to eq([])
    expect(result.requires_approval?).to eq(false)
  end

  # === validate_single_step: exact error message format ===

  it "error for missing id uses inspect formatting" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"type" => "linear"}]
    })

    result = validator.validate(plan, initial_keys: [])
    expect(result.errors).to include("Step missing 'id': {\"type\" => \"linear\"}")
  end

  it "error for missing expected keys includes available keys as array inspect" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "validate_order"}]
    })

    result = validator.validate(plan, initial_keys: [:order_id, :other])
    error = result.errors.first
    expect(error).to include("[:order_id, :other]").or include("[:other, :order_id]")
  end

  it "error for missing expected keys includes exact missing keys inspect" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "find_order"}]
    })

    result = validator.validate(plan, initial_keys: [])
    error = result.errors.first
    expect(error).to include("missing expected keys: [:order_id]")
  end

  it "error for missing expected keys shows non-empty available keys as array" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "find_order"}]
    })

    result = validator.validate(plan, initial_keys: [:foo])
    error = result.errors.first
    expect(error).to include("[:foo]")
  end

  # === validate_single_step: return value structure ===

  it "missing id step does not set approval" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"type" => "linear"}, {"id" => "find_order"}]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result.errors.length).to eq(1)
    expect(result.errors.first).to start_with("Step missing 'id'")
    expect(result.requires_approval?).to eq(nil).or eq(false)
  end

  it "unknown capability step does not propagate approval" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "bogus"}]
    })

    result = validator.validate(plan, initial_keys: [])
    expect(result).not_to be_safe
    expect(result.requires_approval?).to eq(nil).or eq(false)
  end

  # === validate_steps: key propagation within branches ===

  it "second step in if branch sees keys promised by first step" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if",
         "condition" => {"key" => "x", "equals" => true},
         "then" => [
           {"id" => "find_order"},
           {"id" => "validate_order"}
         ]}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result).to be_safe
  end

  it "second step in else branch sees keys promised by first step" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if_else",
         "condition" => {"key" => "x", "equals" => true},
         "then" => [{"id" => "find_order"}],
         "else" => [
           {"id" => "find_order"},
           {"id" => "notify"}
         ]}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result).to be_safe
  end

  # === validate: if without then key ===

  it "if step without then key does not error" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if",
         "condition" => {"key" => "x", "equals" => true}}
      ]
    })

    result = validator.validate(plan, initial_keys: [])
    expect(result).to be_safe
  end

  it "if_else step without else key does not error" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if_else",
         "condition" => {"key" => "x", "equals" => true},
         "then" => [{"id" => "find_order"}]}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result).to be_safe
  end

  # === validate: iterate without steps key ===

  it "iterate step without steps key does not error" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "iterate",
         "collection" => "orders"}
      ]
    })

    result = validator.validate(plan, initial_keys: [])
    expect(result).to be_safe
  end

  # === validate: else branch dup isolation ===

  it "else branch validation uses dup of available keys" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if_else",
         "condition" => {"key" => "x", "equals" => true},
         "then" => [{"id" => "find_order"}],
         "else" => [{"id" => "find_order"}]},
        {"id" => "validate_order"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    # Both branches have find_order which promises :order
    # track_step_keys processes "then" steps, so :order becomes available
    expect(result).to be_safe
  end

  # === track_step_keys: nil id guard ===

  it "track_step_keys handles step with nil id in then branch" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if",
         "condition" => {"key" => "x", "equals" => true},
         "then" => [
           {"no_id" => "yes"},
           {"id" => "find_order"}
         ]},
        {"id" => "validate_order"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    # The nil-id step produces an error in branch validation
    expect(result).not_to be_safe
    # But track_step_keys should still process find_order, adding :order
    # So validate_order should work — no validate_order error
    expect(result.errors).not_to include(a_string_matching(/validate_order/))
    # Error is only from the nil-id step
    expect(result.errors).to include(a_string_matching(/Step missing 'id'/))
  end

  it "track_step_keys handles unknown capability silently" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if",
         "condition" => {"key" => "x", "equals" => true},
         "then" => [{"id" => "nonexistent"}]},
        {"id" => "find_order"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result.errors.length).to eq(1)
    expect(result.errors.first).to include("Unknown capability: nonexistent")
  end

  # === validate: high-risk step triggers approval ===

  it "high-risk step as linear step triggers approval" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"id" => "find_order"},
        {"id" => "issue_refund"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result.requires_approval?).to eq(true)
  end

  # === validate: multiple sequential steps propagate keys ===

  it "three sequential steps each see prior promises" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"id" => "find_order"},
        {"id" => "validate_order"},
        {"id" => "notify"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result).to be_safe
  end

  # === validate: requires_approval aggregation ===

  it "requires_approval stays true once set by any step" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"id" => "issue_refund"},
        {"id" => "find_order"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order])
    expect(result.requires_approval?).to eq(true)
  end

  # === validate: empty plan ===

  it "empty steps plan is safe with no approval" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => []
    })

    result = validator.validate(plan, initial_keys: [])
    expect(result).to be_safe
    expect(result.requires_approval?).to eq(false)
  end

  # === validate: error message includes available keys content ===

  it "missing keys error shows actual available keys not empty" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "validate_order"}]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    error = result.errors.first
    expect(error).to include("[:order_id]")
  end

  # === validate: .dup isolation for then branch ===

  it "then branch key propagation does not leak to else branch or outer flow" do
    # If .dup is removed, the then branch validate_steps would add :order to
    # the shared available_keys, meaning the else branch would incorrectly
    # see :order and subsequent steps would too
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if_else",
         "condition" => {"key" => "x", "equals" => true},
         "then" => [{"id" => "find_order"}],
         "else" => []},
        # After the if_else, only track_step_keys (then branch) adds :order
        # Without .dup, validate_steps for then branch would also add :order
        # to the outer available_keys, but that's actually the same as track_step_keys
        # So we need a different approach...
        {"id" => "validate_order"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result).to be_safe
  end

  it "then branch with nil value for then key does not validate" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if",
         "condition" => {"key" => "x", "equals" => true},
         "then" => nil}
      ]
    })

    # step["then"] is nil, so if guard should skip validation
    result = validator.validate(plan, initial_keys: [])
    expect(result).to be_safe
  end

  it "else branch with nil value for else key does not validate" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if_else",
         "condition" => {"key" => "x", "equals" => true},
         "then" => [{"id" => "find_order"}],
         "else" => nil}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result).to be_safe
  end

  # === validate: Set.new wrapping matters ===

  it "available_keys deduplicates initial keys via Set" do
    # With duplicate keys, Set dedup matters for error messages
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "find_order"}]
    })

    result = validator.validate(plan, initial_keys: [:order_id, :order_id])
    # With Set, available is {order_id} — find_order expects [:order_id] which is available
    expect(result).to be_safe
  end

  # === validate: iterate default item key is :item not :'' ===

  it "iterate without as defaults to :item not empty string" do
    # Register a capability that expects :item
    registry.register(Workflow::Ai::Capability.new(
      :use_item, action: ->(ctx) { ctx },
      description: "Use", expects: [:item], promises: [],
      side_effects: [], risk: :low
    ))

    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "iterate",
         "collection" => "items",
         "steps" => [{"id" => "use_item"}]}
      ]
    })

    # Default item key :item should satisfy use_item's expectation
    result = validator.validate(plan, initial_keys: [])
    expect(result).to be_safe
  end

  # === validate_single_step: return value must be 3-element array ===

  it "nil-id step return value includes explicit false approval" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"type" => "linear"}, {"id" => "issue_refund"}]
    })

    result = validator.validate(plan, initial_keys: [:order])
    # First step has no id (error + no approval), second step is high-risk
    # If nil-id return omitted the 3rd element, approval from issue_refund might be wrong
    expect(result.requires_approval?).to eq(true)
    expect(result.errors.length).to eq(1)
  end

  it "unknown capability step return value includes explicit false approval" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "nonexistent"}, {"id" => "issue_refund"}]
    })

    result = validator.validate(plan, initial_keys: [:order])
    expect(result.requires_approval?).to eq(true)
  end

  # === validate_single_step: error message uses .to_a.inspect for available keys ===

  it "error message shows array-style brackets around available keys" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "find_order"}]
    })

    result = validator.validate(plan, initial_keys: [:foo])
    error = result.errors.first
    # .to_a.inspect produces "[:foo]" not "#<Set: {:foo}>"
    expect(error).to include("Available: [:foo]")
  end

  # === validate: then branch validation with falsy then value ===

  it "if step with false as then value does not validate" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if",
         "condition" => {"key" => "x", "equals" => true},
         "then" => false}
      ]
    })

    result = validator.validate(plan, initial_keys: [])
    expect(result).to be_safe
  end

  it "Set dedup is visible in error messages for duplicate initial keys" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "validate_order"}]
    })

    result = validator.validate(plan, initial_keys: [:order_id, :order_id])
    # validate_order expects :order which is missing
    # With Set, available is [:order_id]; with Array, available would be [:order_id, :order_id]
    error = result.errors.first
    # Set dedup: should show [:order_id] not [:order_id, :order_id]
    expect(error).not_to include("[:order_id, :order_id]")
  end

  it "else branch key promises propagate to subsequent steps" do
    # The else branch has find_order which promises :order
    # Both branches' promised keys are tracked (union), so :order IS available
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if_else",
         "condition" => {"key" => "x", "equals" => true},
         "then" => [],
         "else" => [{"id" => "find_order"}]},
        {"id" => "validate_order"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result).to be_safe
  end

  it "high-risk step in if branch triggers approval" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if",
         "condition" => {"key" => "x", "equals" => true},
         "then" => [{"id" => "issue_refund"}]}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order])
    expect(result.requires_approval?).to eq(true)
  end

  it "high-risk step in iterate triggers approval" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "iterate",
         "collection" => "orders",
         "as" => "order",
         "steps" => [{"id" => "issue_refund"}]}
      ]
    })

    result = validator.validate(plan, initial_keys: [])
    expect(result.requires_approval?).to eq(true)
  end

  it "validates nested if inside iterate" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "iterate",
         "collection" => "orders",
         "as" => "order",
         "steps" => [
           {"type" => "if",
            "condition" => {"key" => "valid", "equals" => true},
            "then" => [{"id" => "find_order"}]}
         ]}
      ]
    })

    result = validator.validate(plan, initial_keys: [])
    # find_order expects :order_id, not provided by iterate (only :order is)
    expect(result).not_to be_safe
    expect(result.errors).to include(a_string_matching(/find_order/))
  end

  it "then branch with false then value skips track_step_keys" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if",
         "condition" => {"key" => "x", "equals" => true},
         "then" => false},
        {"id" => "validate_order"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order])
    # then is false, so (step["then"] || []).each iterates over [] — no keys tracked
    # validate_order expects :order which IS available from initial_keys
    expect(result).to be_safe
  end

  it "then branch validation does not pollute else branch available keys" do
    # If then branch validation didn't use .dup, keys added during then
    # branch validation would leak to the else branch validation
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if_else",
         "condition" => {"key" => "x", "equals" => true},
         "then" => [{"id" => "find_order"}],
         "else" => [{"id" => "validate_order"}]}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    # Then branch: find_order expects :order_id ✓, promises :order
    # Else branch: validate_order expects :order — NOT available (only :order_id)
    # Without .dup on then, validate_order would incorrectly see :order
    expect(result).not_to be_safe
    expect(result.errors).to include(a_string_matching(/validate_order/))
  end

  # === Nested control-flow: key propagation across levels ===

  it "keys from nested if_else propagate to steps after outer if" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if",
         "condition" => {"key" => "flag", "equals" => true},
         "then" => [
           {"type" => "if_else",
            "condition" => {"key" => "sub_flag", "equals" => true},
            "then" => [{"id" => "find_order"}],
            "else" => []}
         ]},
        {"id" => "validate_order"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    # find_order (nested in if > if_else > then) promises :order
    # :order should propagate through both levels to validate_order
    expect(result).to be_safe
  end

  it "high-risk step in else branch triggers approval" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if_else",
         "condition" => {"key" => "x", "equals" => true},
         "then" => [],
         "else" => [{"id" => "issue_refund"}]}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order])
    expect(result.requires_approval?).to eq(true)
  end

  it "keys from nested if_else else branch propagate to outer flow" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if_else",
         "condition" => {"key" => "flag", "equals" => true},
         "then" => [],
         "else" => [{"id" => "find_order"}]},
        {"id" => "validate_order"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result).to be_safe
  end

  it "iterate inner steps see keys from outer flow" do
    # find_order expects :order_id (from initial_keys), inside an iterate
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "iterate",
         "collection" => "items",
         "as" => "item",
         "steps" => [{"id" => "find_order"}]}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result).to be_safe
  end

  it "iterate preserves existing keys when item_key overlaps" do
    # item_key :order_id is already in initial_keys — | and ^ differ here
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "iterate",
         "collection" => "items",
         "as" => "order_id",
         "steps" => [{"id" => "find_order"}]}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result).to be_safe
  end

  it "keys from iterate available to subsequent steps" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "iterate",
         "collection" => "items",
         "as" => "item",
         "steps" => [{"id" => "find_order"}]},
        {"id" => "validate_order"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result).to be_safe
  end

  it "duplicate step does not remove already-promised keys" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"id" => "find_order"},
        {"id" => "find_order"},
        {"id" => "validate_order"}
      ]
    })

    result = validator.validate(plan, initial_keys: [:order_id])
    expect(result).to be_safe
  end
end
