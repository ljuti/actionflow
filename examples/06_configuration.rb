# frozen_string_literal: true

# Configuration & Localization Example
#
# Demonstrates:
# - Workflow.configure for global settings
# - Localization adapters (NullAdapter, HashAdapter)
# - How ctx.fail! uses localization when configured
#
# Run:  ruby -Ilib examples/06_configuration.rb

require "actionflow"

# ── Actions ──────────────────────────────────────────────────────────

class ValidateOrder
  include Workflow::Action

  expects :order

  def call(ctx)
    if ctx[:order][:total] <= 0
      ctx.fail!("validate_order.invalid_total", error_code: :invalid_order)
    else
      ctx[:valid] = true
    end
  end
end

class CheckInventory
  include Workflow::Action

  expects :order

  def call(ctx)
    if ctx[:order][:sku] == "out-of-stock"
      ctx.fail!("check_inventory.out_of_stock", error_code: :no_stock)
    else
      ctx[:in_stock] = true
    end
  end
end

# ── Without localization ────────────────────────────────────────────
# Default: messages pass through unchanged.

puts "=== Without Localization ==="

result = ValidateOrder.new.execute(Workflow::Context.new(order: {total: 0}))
puts "message: #{result.message.inspect}"
puts "error_code: #{result.error_code}"

# ── With HashAdapter ─────────────────────────────────────────────────
# Keys are looked up in a catalog; unknown keys pass through as-is.

catalog = {
  "validate_order.invalid_total" => "The order total must be greater than zero.",
  "check_inventory.out_of_stock" => "Sorry, this item is currently out of stock."
}

Workflow.configure do |config|
  config.localization_adapter = Workflow::Localization::HashAdapter.new(catalog)
end

puts "\n=== With HashAdapter Localization ==="

result2 = ValidateOrder.new.execute(Workflow::Context.new(order: {total: 0}))
puts "message: #{result2.message}"
# => "The order total must be greater than zero."

result3 = CheckInventory.new.execute(Workflow::Context.new(order: {total: 10, sku: "out-of-stock"}))
puts "message: #{result3.message}"
# => "Sorry, this item is currently out of stock."

# Unknown key falls back to the raw message
ValidateOrder.new.execute(Workflow::Context.new(order: {total: 0}))
puts "known key: #{result2.message}"

class FailWithUnknownKey
  include Workflow::Action

  def call(ctx)
    ctx.fail!("some.unknown.key")
  end
end

result5 = FailWithUnknownKey.new.execute(Workflow::Context.new)
puts "unknown key fallback: #{result5.message}"
# => "some.unknown.key" (not in catalog, passes through)

# ── With logger ──────────────────────────────────────────────────────

require "logger"

puts "\n=== With Logger ==="

Workflow.configure do |config|
  config.logger = Logger.new($stdout, formatter: ->(_, _, _, msg) { "[WF] #{msg}\n" })
end

puts "(Logger configured — available to hooks and action runner)"
puts "Logger class: #{Workflow.configuration.logger.class}"

# Reset for cleanliness
Workflow.configure do |config|
  config.logger = nil
  config.localization_adapter = nil
end
