# frozen_string_literal: true

# AI-Agent Composition Example
#
# Demonstrates the optional Workflow::Ai module for building
# AI-agent workflow composition systems:
#
#   Capability      — wraps an action with metadata safe for agents
#   CapabilityRegistry — register and look up capabilities
#   Plan            — structured workflow plan from an agent
#   PlanValidator   — simulate key flow, check safety
#   PlanCompiler    — compile a plan into executable step objects
#   DynamicOrganizer — execute compiled plans
#
# Run:  ruby -Ilib examples/08_ai_agent.rb

require "actionflow"

# ── Define real actions ──────────────────────────────────────────────

class FindOrder
  include Workflow::Action

  expects :order_id
  promises :order

  def initialize(orders:)
    @orders = orders
  end

  def call(ctx)
    ctx[:order] = @orders.fetch(ctx[:order_id])
  end
end

class ValidateOrder
  include Workflow::Action

  expects :order
  promises :valid

  def call(ctx)
    ctx[:valid] = ctx[:order][:status] != "cancelled"
  end
end

class IssueRefund
  include Workflow::Action

  expects :order, :valid
  promises :refund_id

  def initialize(payment_gateway:)
    @gateway = payment_gateway
  end

  def call(ctx)
    unless ctx[:valid]
      ctx.fail!("Order is not valid for refund")
      return
    end

    ctx[:refund_id] = @gateway.refund(ctx[:order][:charge_id])
  end
end

class NotifyCustomer
  include Workflow::Action

  expects :refund_id

  def call(ctx)
    puts "  Email sent: Your refund #{ctx[:refund_id]} has been processed."
  end
end

# ── Fake services ────────────────────────────────────────────────────

orders = {
  "ord_1" => {id: "ord_1", status: "delivered", charge_id: "ch_abc"},
  "ord_2" => {id: "ord_2", status: "cancelled", charge_id: "ch_xyz"}
}

gateway = Struct.new(:refunds) do
  def refund(charge_id)
    "ref_#{rand(1000)}"
  end
end.new([])

# ── Create capabilities ──────────────────────────────────────────────
# Capabilities wrap actions with metadata that is safe to expose
# to an AI agent (no code references, no internal state).

puts "=== Register Capabilities ==="

registry = Workflow::Ai::CapabilityRegistry.new

registry.register(Workflow::Ai::Capability.new(
  :find_order,
  action: FindOrder.new(orders: orders),
  description: "Finds an order by its ID.",
  expects: [:order_id],
  promises: [:order],
  side_effects: [],
  risk: :low
))

registry.register(Workflow::Ai::Capability.new(
  :validate_order,
  action: ValidateOrder.new,
  description: "Checks whether an order is valid for processing.",
  expects: [:order],
  promises: [:valid],
  side_effects: [],
  risk: :low
))

registry.register(Workflow::Ai::Capability.new(
  :issue_refund,
  action: IssueRefund.new(payment_gateway: gateway),
  description: "Issues a refund for a validated order.",
  expects: [:order, :valid],
  promises: [:refund_id],
  side_effects: [:payment_refund],
  risk: :high,
  requires_approval: true,
  rollback_available: true
))

registry.register(Workflow::Ai::Capability.new(
  :notify_customer,
  action: NotifyCustomer.new,
  description: "Sends a refund confirmation email to the customer.",
  expects: [:refund_id],
  promises: [],
  side_effects: [:email],
  risk: :low
))

# Descriptions are safe to share with the agent
puts "Capabilities: #{registry.descriptions.map { |d| d[:id] }}"
puts "High-risk: #{registry.descriptions.select { |d| d[:risk] == :high }.map { |d| d[:id] }}"

# ── Create a plan ────────────────────────────────────────────────────
# This would normally come from the AI agent's output.

puts "\n=== Create Plan ==="

plan = Workflow::Ai::Plan.new({
  "name" => "refund_order",
  "input" => {"order_id" => "ord_1"},
  "steps" => [
    {"id" => "find_order"},
    {"id" => "validate_order"},
    {"id" => "issue_refund"},
    {"id" => "notify_customer"}
  ]
})

puts "Plan: #{plan.name}, #{plan.steps.size} steps"

# ── Validate the plan ────────────────────────────────────────────────
# PlanValidator simulates key flow without executing actions.

puts "\n=== Validate Plan ==="

validator = Workflow::Ai::PlanValidator.new(registry: registry)
validation = validator.validate(plan, initial_keys: [:order_id])

puts "Safe? #{validation.safe?}"
puts "Requires approval? #{validation.requires_approval?}"
puts "Errors: #{validation.errors.inspect}"

# ── Validate a bad plan ──────────────────────────────────────────────

bad_plan = Workflow::Ai::Plan.new({
  "name" => "bad_plan",
  "steps" => [
    {"id" => "validate_order"},   # missing :order — no find_order first
    {"id" => "unknown_action"}    # not in registry
  ]
})

bad_validation = validator.validate(bad_plan, initial_keys: [:order_id])
puts "\nBad plan safe? #{bad_validation.safe?}"
bad_validation.errors.each { |e| puts "  Error: #{e}" }

# ── Compile the plan ─────────────────────────────────────────────────
# PlanCompiler turns plan steps into executable objects.

puts "\n=== Compile Plan ==="

compiler = Workflow::Ai::PlanCompiler.new(registry: registry)
steps = compiler.compile(plan)

puts "Compiled #{steps.size} steps:"
steps.each { |s| puts "  #{s.class.name}" }

# ── Execute via DynamicOrganizer ─────────────────────────────────────

puts "\n=== Execute Plan ==="

organizer = Workflow::Ai::DynamicOrganizer.new(steps: steps)
result = organizer.call(order_id: "ord_1")

puts "Success? #{result.success?}"
puts "Order: #{result[:order][:id]} (status: #{result[:order][:status]})"
puts "Refund: #{result[:refund_id]}"

# ── Conditional plan ─────────────────────────────────────────────────

puts "\n=== Conditional Plan (if_else) ==="

conditional_plan = Workflow::Ai::Plan.new({
  "name" => "conditional_refund",
  "steps" => [
    {"id" => "find_order"},
    {"id" => "validate_order"},
    {"type" => "if_else",
     "condition" => {"key" => "valid", "equals" => true},
     "then" => [
       {"id" => "issue_refund"},
       {"id" => "notify_customer"}
     ],
     "else" => []}
  ]
})

cond_steps = compiler.compile(conditional_plan)
cond_organizer = Workflow::Ai::DynamicOrganizer.new(steps: cond_steps)

# Valid order
result1 = cond_organizer.call(order_id: "ord_1")
puts "Valid order success: #{result1.success?}, refund: #{result1[:refund_id]}"

# Cancelled order — validate sets valid=false, so refund branch is skipped
result2 = cond_organizer.call(order_id: "ord_2")
puts "Cancelled order success: #{result2.success?}, valid: #{result2[:valid]}"
