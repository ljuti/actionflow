# frozen_string_literal: true

# Hooks Example
#
# Demonstrates before_each, after_each, and around_each hooks.
# Hooks are registered on the OrganizerSession and fire for each
# workflow action (not for plain lambdas or control-flow steps).
#
# Run:  ruby -Ilib examples/05_hooks.rb

require "actionflow"

# ── Actions ──────────────────────────────────────────────────────────

class FetchUser
  include Workflow::Action

  expects :user_id
  promises :user

  def initialize(db:)
    @db = db
  end

  def call(ctx)
    ctx[:user] = @db.fetch(ctx[:user_id])
  end
end

class EnrichUser
  include Workflow::Action

  expects :user
  promises :enriched_user

  def call(ctx)
    ctx[:enriched_user] = ctx[:user].merge(enriched: true)
  end
end

class FormatOutput
  include Workflow::Action

  expects :enriched_user
  promises :output

  def call(ctx)
    ctx[:output] = "User: #{ctx[:enriched_user][:name]} (enriched=#{ctx[:enriched_user][:enriched]})"
  end
end

# ── Organizer with hooks ────────────────────────────────────────────

class UserPipeline
  include Workflow::Organizer

  def initialize(db:, logger:)
    @db = db
    @logger = logger
    @fetch = FetchUser.new(db: @db)
    @enrich = EnrichUser.new
    @format = FormatOutput.new
  end

  def call(user_id:)
    with(user_id: user_id)
      .before_each(method(:log_before))
      .after_each(method(:log_after))
      .reduce(@fetch, @enrich, @format)
  end

  private

  def log_before(action, ctx)
    @logger.info("[BEFORE] #{action.class.name}")
  end

  def log_after(action, ctx)
    @logger.info("[AFTER]  #{action.class.name} success=#{ctx.success?}")
  end
end

# ── Around hooks ────────────────────────────────────────────────────
# Around hooks wrap the action execution. Must yield to continue.

class MeasureDuration
  def initialize(logger:)
    @logger = logger
  end

  def call(action, ctx)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    @logger.info("[DURATION] #{action.class.name}: #{(elapsed * 1000).round(2)}ms")
    result
  end
end

# Multiple around hooks compose: outer → middle → inner → action

class AuditTrail
  def initialize(logger:)
    @logger = logger
  end

  def call(action, ctx, &blk)
    @logger.info("[AUDIT ENTER] #{action.class.name}")
    result = blk.call
    @logger.info("[AUDIT EXIT]  #{action.class.name}")
    result
  end
end

# ── Fake services ────────────────────────────────────────────────────

class SimpleLogger
  def initialize
    @lines = []
  end

  def info(message)
    @lines << message
    puts "  #{message}"
  end

  attr_reader :lines
end

FakeDb = Struct.new(:records) do
  def fetch(id)
    records.fetch(id)
  end
end

# ── Run: before + after hooks ────────────────────────────────────────

db = FakeDb.new({"u1" => {name: "Alice", email: "alice@example.com"}})
logger = SimpleLogger.new

pipeline = UserPipeline.new(db: db, logger: logger)

puts "=== Before + After Hooks ==="
result = pipeline.call(user_id: "u1")

puts "\nResult: #{result[:output]}"
puts "Log entries: #{logger.lines.size}"

# ── Run: around hooks ────────────────────────────────────────────────

puts "\n=== Around Hooks (timing + audit) ==="

logger2 = SimpleLogger.new
measure = MeasureDuration.new(logger: logger2)
audit = AuditTrail.new(logger: logger2)

fetch = FetchUser.new(db: db)
enrich = EnrichUser.new
format = FormatOutput.new

result2 = UserPipeline.new(db: db, logger: SimpleLogger.new)
  .with(user_id: "u1")
  .around_each(measure)
  .around_each(audit)
  .reduce(fetch, enrich, format)

puts "Result: #{result2[:output]}"
puts "success: #{result2.success?}"
