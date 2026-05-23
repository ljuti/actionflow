# frozen_string_literal: true

module Workflow
  class ActionRunner
    def self.default
      new
    end

    def initialize(before_hooks: [], after_hooks: [], around_hooks: [], logger: nil, capture_exceptions: false)
      @before_hooks = before_hooks
      @after_hooks = after_hooks
      @around_hooks = around_hooks
      @logger = logger
      @capture_exceptions = capture_exceptions
    end

    def call(action, ctx)
      return ctx if ctx.stop_processing?

      ctx.current_step = action

      log("executing #{action.class.name}")

      apply_defaults(action, ctx)
      verify_expected_keys!(action, ctx)

      run_before_hooks(action, ctx)

      execute_action(action, ctx)

      verify_promised_keys!(action, ctx)
      run_after_hooks(action, ctx)

      ctx
    end

    private

    def execute_action(action, ctx)
      if @capture_exceptions
        begin
          run_around_hooks(action, ctx) do
            action.call(ctx)
          end
        rescue Workflow::FailWithRollback
          raise
        rescue => e
          ctx.fail!(e.message, error_code: e.class.name.to_sym)
        end
      else
        run_around_hooks(action, ctx) do
          action.call(ctx)
        end
      end
    end

    def metadata_for(action)
      action.workflow_metadata
    end

    def apply_defaults(action, ctx)
      metadata_for(action).defaults.each do |key, default|
        next if ctx.key?(key)

        ctx[key] = default.respond_to?(:call) ? default.call(ctx) : default
      end
    end

    def verify_expected_keys!(action, ctx)
      missing = metadata_for(action).expected_keys.reject { |key| ctx.key?(key) }
      raise ExpectedKeysMissing, "Missing expected keys: #{missing}" unless missing.empty?
    end

    def verify_promised_keys!(action, ctx)
      return if ctx.failure?

      missing = metadata_for(action).promised_keys.reject { |key| ctx.key?(key) }
      raise PromisedKeysMissing, "Missing promised keys: #{missing}" unless missing.empty?
    end

    def run_before_hooks(action, ctx)
      @before_hooks.each { |hook| hook.call(action, ctx) }
    end

    def run_after_hooks(action, ctx)
      @after_hooks.each { |hook| hook.call(action, ctx) }
    end

    def run_around_hooks(action, ctx, &block)
      chain = @around_hooks.reverse.reduce(block) do |next_block, hook|
        -> { hook.call(action, ctx, &next_block) }
      end

      chain.call
    end

    def log(message)
      return unless @logger

      @logger.call("[Workflow] #{message}")
    end
  end
end
