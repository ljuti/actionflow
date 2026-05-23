# frozen_string_literal: true

# Testing Patterns Example
#
# Demonstrates:
# - Testing actions in isolation (#call vs #execute)
# - Testing organizers end-to-end
# - Using Workflow::Testing::ContextFactory to build context
#   as it would appear just before a target action
#
# Run:  ruby -Ilib examples/07_testing_patterns.rb
#
# These are demonstration patterns. In real code, these would live
# in spec/ files and use RSpec expectations.

require "actionflow"

# ── Actions ──────────────────────────────────────────────────────────

class FindProduct
  include Workflow::Action

  expects :product_id
  promises :product

  def initialize(catalog:)
    @catalog = catalog
  end

  def call(ctx)
    ctx[:product] = @catalog.find(ctx[:product_id])
  end
end

class ApplyDiscount
  include Workflow::Action

  expects :product, :discount_percent
  promises :final_price

  def call(ctx)
    ctx[:final_price] = (ctx[:product][:price] * (1 - ctx[:discount_percent])).round(2)
  end
end

class FormatReceipt
  include Workflow::Action

  expects :product, :final_price
  promises :receipt

  def call(ctx)
    ctx[:receipt] = "#{ctx[:product][:name]}: $#{ctx[:final_price]}"
  end
end

# ── Organizer ────────────────────────────────────────────────────────

class PurchasePipeline
  include Workflow::Organizer

  def initialize(catalog:)
    @catalog = catalog
    @find = FindProduct.new(catalog: @catalog)
    @discount = ApplyDiscount.new
    @receipt = FormatReceipt.new
  end

  def call(product_id:, discount_percent: 0)
    with(product_id: product_id, discount_percent: discount_percent)
      .reduce(@find, @discount, @receipt)
  end
end

# ── Fake services ────────────────────────────────────────────────────

FakeCatalog = Struct.new(:products) do
  def find(id)
    products.fetch(id) { raise "Product #{id} not found" }
  end
end

catalog = FakeCatalog.new({
  "p1" => {name: "Widget", price: 100.0},
  "p2" => {name: "Gadget", price: 50.0}
})

# ── Pattern 1: Test action in isolation with #execute ────────────────
# #execute runs the full lifecycle: defaults, contract checks, hooks.

puts "=== Test action with #execute (full lifecycle) ==="

action = FindProduct.new(catalog: catalog)
ctx = Workflow::Context.new(product_id: "p1")
result = action.execute(ctx)

puts "success: #{result.success?}"
puts "product: #{result[:product]}"
puts "contract enforced: expects checked, promises verified"

# ── Pattern 2: Test action business logic with #call ─────────────────
# #call bypasses framework — just the raw business logic.

puts "\n=== Test action with #call (business logic only) ==="

ctx = Workflow::Context.new(product_id: "p1")
action = FindProduct.new(catalog: catalog)
action.call(ctx)

puts "product: #{ctx[:product]}"
puts "(no contract checks ran — faster for unit tests)"

# ── Pattern 3: Test organizer end-to-end ─────────────────────────────

puts "\n=== Test organizer end-to-end ==="

pipeline = PurchasePipeline.new(catalog: catalog)
result = pipeline.call(product_id: "p1", discount_percent: 0.2)

puts "success: #{result.success?}"
puts "receipt: #{result[:receipt]}"
puts "final_price: #{result[:final_price]}"

# ── Pattern 4: ContextFactory — build context as it would appear
#                just before a specific action ─────────────────────────

puts "\n=== ContextFactory: context before ApplyDiscount ==="

pipeline = PurchasePipeline.new(catalog: catalog)
discount_action = ApplyDiscount.new

ctx = Workflow::Testing::ContextFactory
  .make_from(pipeline)
  .before(discount_action)
  .with(product_id: "p1", discount_percent: 0.5)

puts "context keys: #{ctx.keys.sort.inspect}"
puts "product present: #{ctx.key?(:product)}"
puts "discount_percent: #{ctx[:discount_percent]}"
# The factory ran FindProduct to populate :product, then applied overrides

# Now test ApplyDiscount in isolation with a realistic context
result = discount_action.execute(ctx)
puts "final_price from isolated test: #{result[:final_price]}"

# ── Pattern 5: Look up by class instead of instance ──────────────────

puts "\n=== ContextFactory: lookup by class ==="

pipeline2 = PurchasePipeline.new(catalog: catalog)

ctx2 = Workflow::Testing::ContextFactory
  .make_from(pipeline2)
  .before(FormatReceipt)  # class, not instance
  .with(product_id: "p2", discount_percent: 0.1, final_price: 42.0)

puts "context before FormatReceipt: product=#{ctx2[:product][:name]}, final_price=#{ctx2[:final_price]}"
# Override takes precedence: final_price=42.0, not what ApplyDiscount would compute

result2 = FormatReceipt.new.execute(ctx2)
puts "receipt: #{result2[:receipt]}"

# ── Pattern 6: Testing failure cases ─────────────────────────────────

puts "\n=== Testing failure ==="

class FailOnNegativePrice
  include Workflow::Action

  expects :product
  promises :final_price

  def call(ctx)
    if ctx[:product][:price] < 0
      ctx.fail!("Price cannot be negative", error_code: :invalid_price)
    else
      ctx[:final_price] = ctx[:product][:price]
    end
  end
end

action = FailOnNegativePrice.new
result = action.execute(Workflow::Context.new(product: {price: -5}))

puts "success: #{result.success?}"
puts "failure: #{result.failure?}"
puts "message: #{result.message}"
puts "error_code: #{result.error_code}"
