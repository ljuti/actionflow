# frozen_string_literal: true

# Basic Usage Example
#
# Demonstrates the minimum viable workflow: a single action with an
# expects/promises contract, and an organizer that composes it.
#
# Run:  ruby -Ilib examples/01_basic_usage.rb

require "actionflow"

# ── Actions ──────────────────────────────────────────────────────────
# An action is an ordinary Ruby object that includes Workflow::Action.
# Dependencies (services, repos) go in the constructor.
# Business data flows through the context.

class GreetUser
  include Workflow::Action

  expects :name                    # context must contain :name
  promises :greeting               # action will set :greeting

  def initialize(formatter:)
    @formatter = formatter
  end

  def call(ctx)
    ctx[:greeting] = @formatter.call("Hello, #{ctx[:name]}!")
  end
end

class AppendTimestamp
  include Workflow::Action

  expects :greeting
  promises :result

  def call(ctx)
    ctx[:result] = "#{ctx[:greeting]} [#{Time.now.utc.iso8601}]"
  end
end

# ── Organizer ────────────────────────────────────────────────────────
# An organizer composes action instances. It is also a plain object —
# inject dependencies through the constructor.

class GreetingPipeline
  include Workflow::Organizer

  def initialize(formatter:)
    @greet = GreetUser.new(formatter: formatter)
    @stamp = AppendTimestamp.new
  end

  def call(name:)
    with(name: name).reduce(@greet, @stamp)
  end
end

# ── Run ──────────────────────────────────────────────────────────────

formatter = ->(s) { s.upcase }
pipeline = GreetingPipeline.new(formatter: formatter)

result = pipeline.call(name: "Ruby")

puts "Success? #{result.success?}"
puts "Result:   #{result[:result]}"
puts "Keys:     #{result.keys.inspect}"
puts "Full ctx: #{result.to_h.inspect}"
