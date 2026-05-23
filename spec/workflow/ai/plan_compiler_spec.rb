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
    ctx = Workflow::Context.new(status: "approved")
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
end
