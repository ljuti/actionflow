# frozen_string_literal: true

# Expects & Promises Contracts Example
#
# Demonstrates:
# - Static expects/promises declarations
# - Default values (static and callable)
# - Instance-specific contracts via #workflow_metadata
# - What happens when keys are missing
#
# Run:  ruby -Ilib examples/02_contracts.rb

require "actionflow"

# ── Static contract ──────────────────────────────────────────────────

class CalculateDiscount
  include Workflow::Action

  expects :amount, :tier
  promises :discount, :total

  def call(ctx)
    rate = case ctx[:tier]
    when :gold then 0.20
    when :silver then 0.10
    else 0.05
    end

    ctx[:discount] = (ctx[:amount] * rate).round(2)
    ctx[:total] = (ctx[:amount] - ctx[:discount]).round(2)
  end
end

# ── Default values ───────────────────────────────────────────────────
# Static defaults and callable defaults (which receive the context).

class ApplyPromoCode
  include Workflow::Action

  expects :amount
  expects :promo_rate, default: 0.0            # static default
  expects :customer_tier, default: ->(ctx) { :standard }  # callable default
  promises :adjusted_total

  def call(ctx)
    ctx[:adjusted_total] = (ctx[:amount] * (1 - ctx[:promo_rate])).round(2)
  end
end

# ── Instance-specific contract ───────────────────────────────────────
# Override #workflow_metadata to build contracts from constructor args.

class NormalizeField
  include Workflow::Action

  def initialize(from:, to:)
    @from = from
    @to = to
  end

  # Called by ActionRunner to determine expected/promised keys
  def workflow_metadata
    @metadata ||= Workflow::ActionMetadata.new(
      expected_keys: [@from],
      promised_keys: [@to]
    )
  end

  def call(ctx)
    raw = ctx[@from]
    ctx[@to] = raw.to_s.strip.downcase
  end
end

# ── Demonstrate ──────────────────────────────────────────────────────

puts "--- Static contract ---"
result = CalculateDiscount.new.execute(Workflow::Context.new(amount: 100, tier: :gold))
puts "discount=#{result[:discount]} total=#{result[:total]} success=#{result.success?}"

puts "\n--- Defaults applied automatically ---"
result = ApplyPromoCode.new.execute(Workflow::Context.new(amount: 50))
puts "adjusted_total=#{result[:adjusted_total]} promo_rate=#{result[:promo_rate]}"

puts "\n--- Callable default ---"
result = ApplyPromoCode.new.execute(Workflow::Context.new(amount: 50, promo_rate: 0.15))
puts "adjusted_total=#{result[:adjusted_total]} promo_rate=#{result[:promo_rate]}"

puts "\n--- Instance-specific contract ---"
normalizer = NormalizeField.new(from: :name, to: :normalized_name)
result = normalizer.execute(Workflow::Context.new(name: "  Alice Smith  "))
puts "normalized_name=#{result[:normalized_name].inspect}"

puts "\n--- Missing expected key raises ---"
begin
  CalculateDiscount.new.execute(Workflow::Context.new(amount: 100))
rescue Workflow::ExpectedKeysMissing => e
  puts "Caught: #{e.message}"
end

puts "\n--- Missing promised key raises ---"
action = Class.new do
  include Workflow::Action

  expects :x
  promises :y
  # forgot to set :y
  def call(ctx)
  end
end.new

begin
  action.execute(Workflow::Context.new(x: 1))
rescue Workflow::PromisedKeysMissing => e
  puts "Caught: #{e.message}"
end
