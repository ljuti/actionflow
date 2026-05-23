# frozen_string_literal: true

# Control-Flow Steps Example
#
# Demonstrates all 10 control-flow step classes:
#   ReduceIf, ReduceIfElse, Iterate, ReduceWhile, ReduceUntil,
#   ReduceCase, Execute, AddToContext, AddAliases, WithCallback
#
# Run:  ruby -Ilib examples/04_control_flow.rb

require "actionflow"

# ── Helper actions ───────────────────────────────────────────────────

class DoubleValue
  include Workflow::Action

  expects :value
  promises :value

  def call(ctx)
    ctx[:value] = ctx[:value] * 2
  end
end

class IncrementCount
  include Workflow::Action

  expects :count
  promises :count

  def call(ctx)
    ctx[:count] = ctx[:count] + 1
  end
end

class MultiplyBy
  include Workflow::Action

  expects :number
  promises :number

  def initialize(factor)
    @factor = factor
  end

  def workflow_metadata
    @metadata ||= Workflow::ActionMetadata.new(
      expected_keys: [:number],
      promised_keys: [:number]
    )
  end

  def call(ctx)
    ctx[:number] = ctx[:number] * @factor
  end
end

class AppendLabel
  include Workflow::Action

  expects :item
  promises :item

  def initialize(label)
    @label = label
  end

  def workflow_metadata
    @metadata ||= Workflow::ActionMetadata.new(
      expected_keys: [:item],
      promised_keys: [:item]
    )
  end

  def call(ctx)
    ctx[:item] = "#{ctx[:item]}[#{@label}]"
  end
end

# ── 1. ReduceIf ─────────────────────────────────────────────────────
# Run steps only when a condition is true.

class ConditionalPipeline
  include Workflow::Organizer

  def initialize
    @double = DoubleValue.new
  end

  def call(value:, verbose: false)
    with(value: value, verbose: verbose).reduce(
      reduce_if(->(ctx) { ctx[:verbose] }, [@double])
    )
  end
end

puts "=== ReduceIf ==="
r1 = ConditionalPipeline.new.call(value: 5, verbose: true)
puts "verbose=true: value=#{r1[:value]}"  # 10

r2 = ConditionalPipeline.new.call(value: 5, verbose: false)
puts "verbose=false: value=#{r2[:value]}" # 5 (unchanged)

# ── 2. ReduceIfElse ─────────────────────────────────────────────────
# Branch between two paths.

class TieredDiscount
  include Workflow::Organizer

  def initialize
    @gold = MultiplyBy.new(0.8)
    @standard = MultiplyBy.new(0.95)
  end

  def call(number:, tier:)
    with(number: number, tier: tier).reduce(
      Workflow::Steps::ReduceIfElse.new(
        ->(ctx) { ctx[:tier] == :gold },
        [@gold],
        [@standard]
      )
    )
  end
end

puts "\n=== ReduceIfElse ==="
puts "gold:     #{TieredDiscount.new.call(number: 100, tier: :gold)[:number]}"     # 80.0
puts "standard: #{TieredDiscount.new.call(number: 100, tier: :standard)[:number]}"  # 95.0

# ── 3. Iterate ──────────────────────────────────────────────────────
# Run steps for each item in a collection.

class ProcessCollection
  include Workflow::Organizer

  def initialize
    @label = AppendLabel.new("processed")
  end

  def call(items:)
    with(items: items).reduce(
      iterate(:items, [@label])
    )
  end
end

puts "\n=== Iterate ==="
result = ProcessCollection.new.call(items: ["a", "b", "c"])
puts "items: #{result[:items].inspect}"
puts "last item: #{result[:item]}" # "c[processed]" (ctx.item holds last iteration)

# ── 4. ReduceWhile ──────────────────────────────────────────────────
# Loop while a condition is true.

puts "\n=== ReduceWhile ==="
incrementer = IncrementCount.new
step = Workflow::Steps::ReduceWhile.new(
  ->(ctx) { ctx[:count] < 5 },
  [incrementer]
)
ctx = Workflow::Context.new(count: 0)
step.call(ctx)
puts "count after ReduceWhile: #{ctx[:count]}" # 5

# ── 5. ReduceUntil ──────────────────────────────────────────────────
# Loop until a condition is true.

puts "\n=== ReduceUntil ==="
step = Workflow::Steps::ReduceUntil.new(
  ->(ctx) { ctx[:count] >= 10 },
  [incrementer]
)
ctx = Workflow::Context.new(count: 5)
step.call(ctx)
puts "count after ReduceUntil: #{ctx[:count]}" # 10

# ── 6. ReduceCase ───────────────────────────────────────────────────
# Branch on a value (like a switch statement).

puts "\n=== ReduceCase ==="
step = Workflow::Steps::ReduceCase.new(
  ->(ctx) { ctx[:role] },
  {
    admin: [MultiplyBy.new(100)],
    editor: [MultiplyBy.new(10)],
    viewer: [MultiplyBy.new(1)]
  }
)

ctx = Workflow::Context.new(role: :admin, number: 1)
step.call(ctx)
puts "admin: #{ctx[:number]}"  # 100

ctx = Workflow::Context.new(role: :editor, number: 1)
step.call(ctx)
puts "editor: #{ctx[:number]}" # 10

# ── 7. Execute ──────────────────────────────────────────────────────
# Inline block as a step.

puts "\n=== Execute ==="
step = Workflow::Steps::Execute.new(->(ctx) {
  ctx[:timestamp] = Time.now.utc.to_i
  ctx
})
ctx = Workflow::Context.new
step.call(ctx)
puts "timestamp: #{ctx[:timestamp]}"

# ── 8. AddToContext ─────────────────────────────────────────────────
# Inject key-value pairs into the context.

puts "\n=== AddToContext ==="
step = Workflow::Steps::AddToContext.new(status: "pending", retry_count: 0)
ctx = Workflow::Context.new(order_id: "ord_1")
step.call(ctx)
puts "context: #{ctx.to_h.inspect}"

# ── 9. AddAliases ───────────────────────────────────────────────────
# Register key aliases so ctx[:alias] resolves to ctx[:original].

puts "\n=== AddAliases ==="
step = Workflow::Steps::AddAliases.new(name: :full_name)
ctx = Workflow::Context.new(full_name: "Alice")
step.call(ctx)
puts "ctx[:name] resolves to ctx[:full_name]: #{ctx[:name]}"
puts "ctx[:full_name]: #{ctx[:full_name]}"

# ── 10. WithCallback ────────────────────────────────────────────────
# Run steps, then store a callback for later invocation.

puts "\n=== WithCallback ==="
step = Workflow::Steps::WithCallback.new(
  :on_complete,
  [Workflow::Steps::AddToContext.new(setup_done: true)],
  [Workflow::Steps::AddToContext.new(notified: true)]
)

ctx = Workflow::Context.new
step.call(ctx)
puts "after immediate steps: setup_done=#{ctx[:setup_done]}"
puts "callback stored: #{ctx[:on_complete].is_a?(Proc)}"

# Invoke the callback later
ctx[:on_complete].call(ctx)
puts "after callback: notified=#{ctx[:notified]}"

# ── Composition ──────────────────────────────────────────────────────
# All steps compose naturally inside an organizer.

class ComplexPipeline
  include Workflow::Organizer

  def initialize
  end

  def call(numbers:, verbose: false)
    with(numbers: numbers, verbose: verbose).reduce(
      Workflow::Steps::AddToContext.new(total: 0),
      reduce_if(->(ctx) { ctx[:verbose] }, [
        Workflow::Steps::Execute.new(->(ctx) {
          ctx[:log] = "Starting"
          ctx
        })
      ]),
      iterate(:numbers, [
        Workflow::Steps::Execute.new(->(ctx) {
          ctx[:number] = ctx[:number] * 2
          ctx[:total] = ctx[:total] + ctx[:number]
          ctx
        })
      ])
    )
  end
end

puts "\n=== Composition ==="
result = ComplexPipeline.new.call(numbers: [1, 2, 3], verbose: true)
puts "numbers: #{result[:numbers].inspect}" # [2, 4, 6]
puts "total:   #{result[:total]}"           # 12
puts "log:     #{result[:log]}"             # "Starting"
