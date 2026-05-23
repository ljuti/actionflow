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
end
