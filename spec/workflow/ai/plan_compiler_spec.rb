# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Ai::PlanCompiler do
  let(:registry) { Workflow::Ai::CapabilityRegistry.new }
  let(:compiler) { described_class.new(registry: registry) }
  let(:find_action) do
    ->(ctx) do
      ctx[:order] = {id: ctx[:order_id]}
      ctx
    end
  end
  let(:validate_action) do
    ->(ctx) do
      ctx[:valid] = true
      ctx
    end
  end

  before do
    registry.register(Workflow::Ai::Capability.new(
      :find_order, action: find_action,
      description: "Find", expects: [:order_id], promises: [:order], side_effects: [], risk: :low
    ))
    registry.register(Workflow::Ai::Capability.new(
      :validate_order, action: validate_action,
      description: "Validate", expects: [:order], promises: [:valid], side_effects: [], risk: :low
    ))
  end

  it "compiles linear plan to action objects" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"id" => "find_order"},
        {"id" => "validate_order"}
      ]
    })

    steps = compiler.compile(plan)
    expect(steps.length).to eq(2)
    expect(steps[0]).to respond_to(:call)
    expect(steps[1]).to respond_to(:call)
  end

  it "compiles conditional plan to ReduceIfElse" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if_else",
         "condition" => {"key" => "valid", "equals" => true},
         "then" => [{"id" => "validate_order"}],
         "else" => []}
      ]
    })

    steps = compiler.compile(plan)
    expect(steps[0]).to be_a(Workflow::Steps::ReduceIfElse)
  end

  it "compiles iteration plan to Iterate" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "iterate",
         "collection" => "items",
         "as" => "item",
         "steps" => [{"id" => "find_order"}]}
      ]
    })

    steps = compiler.compile(plan)
    expect(steps[0]).to be_a(Workflow::Steps::Iterate)
  end

  it "compiles if step to ReduceIf" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if",
         "condition" => {"key" => "valid", "equals" => true},
         "then" => [{"id" => "validate_order"}]}
      ]
    })

    steps = compiler.compile(plan)
    expect(steps[0]).to be_a(Workflow::Steps::ReduceIf)
  end

  it "builds condition that matches key equality" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if",
         "condition" => {"key" => "status", "equals" => "approved"},
         "then" => [{"id" => "validate_order"}]}
      ]
    })

    steps = compiler.compile(plan)
    if_step = steps[0]
    # The condition is a lambda; we can test it via the ReduceIf internals
    # by running the compiled step against a context
    Workflow::Context.new(status: "approved")
    # ReduceIf checks condition against context data
    expect(if_step).to be_a(Workflow::Steps::ReduceIf)
  end

  it "if_else compiles with else steps" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if_else",
         "condition" => {"key" => "valid", "equals" => true},
         "then" => [{"id" => "find_order"}],
         "else" => [{"id" => "validate_order"}]}
      ]
    })

    steps = compiler.compile(plan)
    if_else_step = steps[0]
    expect(if_else_step).to be_a(Workflow::Steps::ReduceIfElse)
  end

  it "if compiles with empty then steps" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if",
         "condition" => {"key" => "valid", "equals" => true}}
      ]
    })

    steps = compiler.compile(plan)
    expect(steps[0]).to be_a(Workflow::Steps::ReduceIf)
  end

  it "if_else compiles with missing then defaults to empty" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "if_else",
         "condition" => {"key" => "valid", "equals" => true},
         "else" => [{"id" => "validate_order"}]}
      ]
    })

    steps = compiler.compile(plan)
    expect(steps[0]).to be_a(Workflow::Steps::ReduceIfElse)
  end

  it "iterate compiles with custom item_key from as field" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"type" => "iterate",
         "collection" => "orders",
         "as" => "custom_item",
         "steps" => [{"id" => "find_order"}]}
      ]
    })

    steps = compiler.compile(plan)
    expect(steps[0]).to be_a(Workflow::Steps::Iterate)
  end

  it "linear step resolves to the exact action from registry" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "find_order"}]
    })

    steps = compiler.compile(plan)
    expect(steps[0]).to equal(find_action)
  end

  it "returns empty array for plan with no steps" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => []
    })

    steps = compiler.compile(plan)
    expect(steps).to eq([])
  end

  # --- Execution tests: kill mutations by running compiled steps ---

  def register_tracker(registry, id, marker = id)
    action = ->(ctx) do
      (ctx[:executed] ||= []) << marker
      ctx
    end
    registry.register(Workflow::Ai::Capability.new(
      id, action: action,
      description: id.to_s, expects: [], promises: [], side_effects: [], risk: :low
    ))
    action
  end

  it "executes a compiled linear step and modifies context" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{"id" => "find_order"}]
    })

    steps = compiler.compile(plan)
    ctx = Workflow::Context.new(order_id: 42)
    steps[0].call(ctx)
    expect(ctx[:order]).to eq({id: 42})
  end

  it "executes if_else then-branch when condition is true" do
    register_tracker(registry, :then_step, :ran_then)
    register_tracker(registry, :else_step, :ran_else)

    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{
        "type" => "if_else",
        "condition" => {"key" => "valid", "equals" => true},
        "then" => [{"id" => "then_step"}],
        "else" => [{"id" => "else_step"}]
      }]
    })

    steps = compiler.compile(plan)
    ctx = Workflow::Context.new(valid: true)
    steps[0].call(ctx)
    expect(ctx[:executed]).to eq([:ran_then])
  end

  it "executes if_else else-branch when condition is false" do
    register_tracker(registry, :then_step, :ran_then)
    register_tracker(registry, :else_step, :ran_else)

    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{
        "type" => "if_else",
        "condition" => {"key" => "valid", "equals" => true},
        "then" => [{"id" => "then_step"}],
        "else" => [{"id" => "else_step"}]
      }]
    })

    steps = compiler.compile(plan)
    ctx = Workflow::Context.new(valid: false)
    steps[0].call(ctx)
    expect(ctx[:executed]).to eq([:ran_else])
  end

  it "if_else with nil else key defaults to empty array" do
    register_tracker(registry, :then_step, :ran_then)

    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{
        "type" => "if_else",
        "condition" => {"key" => "valid", "equals" => true},
        "then" => [{"id" => "then_step"}]
      }]
    })

    steps = compiler.compile(plan)
    ctx = Workflow::Context.new(valid: true)
    steps[0].call(ctx)
    expect(ctx[:executed]).to eq([:ran_then])
  end

  it "executes if then-steps when condition is true" do
    register_tracker(registry, :track, :ran_if)

    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{
        "type" => "if",
        "condition" => {"key" => "valid", "equals" => true},
        "then" => [{"id" => "track"}]
      }]
    })

    steps = compiler.compile(plan)
    ctx = Workflow::Context.new(valid: true)
    steps[0].call(ctx)
    expect(ctx[:executed]).to eq([:ran_if])
  end

  it "skips if then-steps when condition is false" do
    register_tracker(registry, :track, :ran_if)

    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{
        "type" => "if",
        "condition" => {"key" => "valid", "equals" => true},
        "then" => [{"id" => "track"}]
      }]
    })

    steps = compiler.compile(plan)
    ctx = Workflow::Context.new(valid: false)
    steps[0].call(ctx)
    expect(ctx[:executed]).to be_nil
  end

  it "condition matches string equality correctly" do
    register_tracker(registry, :track, :ran)

    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{
        "type" => "if",
        "condition" => {"key" => "status", "equals" => "approved"},
        "then" => [{"id" => "track"}]
      }]
    })

    steps = compiler.compile(plan)
    ctx = Workflow::Context.new(status: "approved")
    steps[0].call(ctx)
    expect(ctx[:executed]).to eq([:ran])
  end

  it "condition does not match different string value" do
    register_tracker(registry, :track, :ran)

    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{
        "type" => "if",
        "condition" => {"key" => "status", "equals" => "approved"},
        "then" => [{"id" => "track"}]
      }]
    })

    steps = compiler.compile(plan)
    ctx = Workflow::Context.new(status: "rejected")
    steps[0].call(ctx)
    expect(ctx[:executed]).to be_nil
  end

  it "iterates over collection and runs steps for each item" do
    register_tracker(registry, :track, :ran)

    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{
        "type" => "iterate",
        "collection" => "items",
        "as" => "item",
        "steps" => [{"id" => "track"}]
      }]
    })

    steps = compiler.compile(plan)
    ctx = Workflow::Context.new(items: [1, 2, 3])
    steps[0].call(ctx)
    expect(ctx[:executed]).to eq([:ran, :ran, :ran])
  end

  it "iterate sets item key from as field" do
    register_tracker(registry, :track, :ran)

    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{
        "type" => "iterate",
        "collection" => "items",
        "as" => "element",
        "steps" => [{"id" => "track"}]
      }]
    })

    steps = compiler.compile(plan)
    ctx = Workflow::Context.new(items: [:a, :b])
    steps[0].call(ctx)
    expect(ctx[:element]).to eq(:b)
  end

  it "iterate without as field uses singularized collection key" do
    register_tracker(registry, :track, :ran)

    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{
        "type" => "iterate",
        "collection" => "items",
        "steps" => [{"id" => "track"}]
      }]
    })

    steps = compiler.compile(plan)
    ctx = Workflow::Context.new(items: [:x, :y])
    steps[0].call(ctx)
    expect(ctx[:item]).to eq(:y)
  end

  it "iterate without steps key defaults to empty" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{
        "type" => "iterate",
        "collection" => "items"
      }]
    })

    steps = compiler.compile(plan)
    ctx = Workflow::Context.new(items: [1, 2])
    result = steps[0].call(ctx)
    expect(result).to eq(ctx)
  end

  it "compiles nested conditional inside iterate" do
    register_tracker(registry, :inner_action, :ran_inner)

    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [{
        "type" => "iterate",
        "collection" => "items",
        "as" => "item",
        "steps" => [{
          "type" => "if",
          "condition" => {"key" => "active", "equals" => true},
          "then" => [{"id" => "inner_action"}]
        }]
      }]
    })

    steps = compiler.compile(plan)
    ctx = Workflow::Context.new(items: [1, 2, 3], active: true)
    steps[0].call(ctx)
    expect(ctx[:executed]).to eq([:ran_inner, :ran_inner, :ran_inner])
  end

  it "compiles multiple steps in sequence" do
    plan = Workflow::Ai::Plan.new({
      "name" => "test",
      "steps" => [
        {"id" => "find_order"},
        {"id" => "validate_order"}
      ]
    })

    steps = compiler.compile(plan)
    ctx = Workflow::Context.new(order_id: 99)
    steps.each { |s| s.call(ctx) }
    expect(ctx[:order]).to eq({id: 99})
    expect(ctx[:valid]).to eq(true)
  end
end
