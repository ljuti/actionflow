# frozen_string_literal: true

# Failure, Rollback & Skip Example
#
# Demonstrates:
# - ctx.fail! — stop pipeline, mark as failure
# - ctx.fail_with_rollback! — trigger rollback in reverse order
# - ctx.skip_remaining! — bail out of current scope but stay successful
# - ctx.skip_all_remaining! — bail out of all scopes
#
# Run:  ruby -Ilib examples/03_failure_and_rollback.rb

require "actionflow"

# ── Actions ──────────────────────────────────────────────────────────

class ReserveInventory
  include Workflow::Action

  expects :item_id, :quantity
  promises :reservation

  def initialize(inventory:)
    @inventory = inventory
  end

  def call(ctx)
    if @inventory.available?(ctx[:item_id], ctx[:quantity])
      ctx[:reservation] = @inventory.reserve(ctx[:item_id], ctx[:quantity])
    else
      ctx.fail!("Out of stock", error_code: :inventory_shortage)
    end
  end

  def rollback(ctx)
    @inventory.release(ctx[:reservation]) if ctx.key?(:reservation)
    puts "  ↩ ReserveInventory: released reservation #{ctx[:reservation]}"
  end
end

class ChargePayment
  include Workflow::Action

  expects :user, :amount
  promises :charge_id

  def initialize(gateway:)
    @gateway = gateway
  end

  def call(ctx)
    ctx[:charge_id] = @gateway.charge(ctx[:user], ctx[:amount])
  end

  def rollback(ctx)
    @gateway.refund(ctx[:charge_id]) if ctx.key?(:charge_id)
    puts "  ↩ ChargePayment: refunded #{ctx[:charge_id]}"
  end
end

class ShipOrder
  include Workflow::Action

  expects :reservation, :charge_id
  promises :tracking_number

  def initialize(shipping:)
    @shipping = shipping
  end

  def call(ctx)
    ctx[:tracking_number] = @shipping.ship(ctx[:reservation])
  end

  def rollback(ctx)
    @shipping.cancel(ctx[:tracking_number]) if ctx.key?(:tracking_number)
    puts "  ↩ ShipOrder: cancelled #{ctx[:tracking_number]}"
  end
end

# Fail with rollback — triggers reverse rollback on all executed steps
class AuditCompliance
  include Workflow::Action

  expects :charge_id

  def initialize(audit_service:, reject: false)
    @audit_service = audit_service
    @reject = reject
  end

  def call(ctx)
    if @reject
      # This triggers rollback of all previously executed steps
      ctx.fail_with_rollback!("Compliance check failed")
    else
      @audit_service.approve(ctx[:charge_id])
    end
  end
end

# ── Fake services ────────────────────────────────────────────────────

FakeInventory = Struct.new(:stock) do
  def available?(item_id, qty)
    stock.fetch(item_id, 0) >= qty
  end

  def reserve(item_id, qty)
    stock[item_id] -= qty
    "res-#{item_id}-#{rand(1000)}"
  end

  def release(reservation)
    puts "  (inventory released for #{reservation})"
  end
end

FakeGateway = Struct.new(:charges) do
  def charge(_user, amount)
    "ch_#{rand(1000)}"
  end

  def refund(charge_id)
    puts "  (refund processed for #{charge_id})"
  end
end

FakeShipping = Struct.new(:packages) do
  def ship(_reservation)
    "track-#{rand(1000)}"
  end

  def cancel(tracking)
    puts "  (shipment cancelled: #{tracking})"
  end
end

FakeAudit = Struct.new(:approved) do
  def approve(_charge_id)
    puts "  Audit approved"
  end
end

# ── Organizer ────────────────────────────────────────────────────────

class PlaceOrder
  include Workflow::Organizer

  def initialize(inventory:, gateway:, shipping:, audit:, reject_audit: false)
    @reserve = ReserveInventory.new(inventory: inventory)
    @charge = ChargePayment.new(gateway: gateway)
    @ship = ShipOrder.new(shipping: shipping)
    @audit = AuditCompliance.new(audit_service: audit, reject: reject_audit)
  end

  def call(user:, item_id:, quantity:, amount:)
    with(user: user, item_id: item_id, quantity: quantity, amount: amount)
      .reduce(@reserve, @charge, @audit, @ship)
  end
end

# ── Run: success path ────────────────────────────────────────────────

inventory = FakeInventory.new({"sku-1" => 10})
gateway = FakeGateway.new([])
shipping = FakeShipping.new([])
audit = FakeAudit.new([])

order = PlaceOrder.new(inventory: inventory, gateway: gateway,
  shipping: shipping, audit: audit)

result = order.call(user: "alice", item_id: "sku-1", quantity: 2, amount: 49.99)

puts "=== Success ==="
puts "success?    #{result.success?}"
puts "reservation #{result[:reservation]}"
puts "charge_id   #{result[:charge_id]}"
puts "tracking    #{result[:tracking_number]}"

# ── Run: controlled failure (out of stock) ───────────────────────────

inventory2 = FakeInventory.new({"sku-1" => 0})
order2 = PlaceOrder.new(inventory: inventory2, gateway: gateway,
  shipping: shipping, audit: audit)

result2 = order2.call(user: "alice", item_id: "sku-1", quantity: 1, amount: 10)

puts "\n=== Controlled Failure (no rollback) ==="
puts "success?    #{result2.success?}"
puts "message     #{result2.message}"
puts "error_code  #{result2.error_code}"

# ── Run: rollback triggered ──────────────────────────────────────────

inventory3 = FakeInventory.new({"sku-1" => 10})
order3 = PlaceOrder.new(inventory: inventory3, gateway: gateway,
  shipping: shipping, audit: audit, reject_audit: true)

result3 = order3.call(user: "alice", item_id: "sku-1", quantity: 1, amount: 10)

puts "\n=== Rollback Triggered ==="
puts "success?    #{result3.success?}"
puts "message     #{result3.message}"
puts "(rollback ran in reverse order above)"

# ── Skip remaining ───────────────────────────────────────────────────

class SkipDemo
  include Workflow::Action

  expects :should_skip

  def call(ctx)
    if ctx[:should_skip]
      ctx.skip_remaining!("Skipping for demonstration")
    else
      ctx[:ran] = true
    end
  end
end

class ShouldNotRun
  include Workflow::Action

  promises :never_set

  def call(ctx)
    ctx[:never_set] = "oops"
  end
end

skip_result = SkipDemo.new.execute(Workflow::Context.new(should_skip: true))
puts "\n=== Skip Remaining ==="
puts "success?      #{skip_result.success?}"
puts "stop?         #{skip_result.stop_processing?}"
puts "message       #{skip_result.message}"
puts "has never_set? #{skip_result.key?(:never_set)}"
