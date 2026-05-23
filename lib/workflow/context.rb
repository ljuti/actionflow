# frozen_string_literal: true

module Workflow
  class Context
    attr_reader :data
    attr_accessor :message, :error_code, :current_step, :organized_by

    def initialize(data = nil)
      @data = data.to_h.transform_keys(&:to_sym)
      @success = true
      @skip_remaining = false
      @skip_all_remaining = false
      @aliases = {}
    end

    def [](key)
      @data[resolve_alias(key)]
    end

    def []=(key, value)
      @data[resolve_alias(key)] = value
    end

    def key?(key)
      @data.key?(resolve_alias(key))
    end

    def keys
      @data.keys
    end

    def to_h
      @data.dup
    end

    def success?
      @success
    end

    def failure?
      !success?
    end

    def fail!(message = nil, error_code: nil, **options)
      @success = false
      @error_code = error_code
      @message = localize(message, options)
    end

    def succeed!(message = nil)
      @success = true
      @message = message
    end

    def skip_remaining!(message = nil)
      @message = message
      @skip_remaining = true
    end

    def skip_all_remaining!(message = nil)
      @message = message
      @skip_all_remaining = true
    end

    def skip_remaining?
      @skip_remaining
    end

    def skip_all_remaining?
      @skip_all_remaining
    end

    def stop_processing?
      failure? || skip_remaining? || skip_all_remaining?
    end

    def reset_skip_remaining!
      @skip_remaining = false
      @message = nil
    end

    def assign_aliases(aliases)
      @aliases.merge!(aliases.transform_keys(&:to_sym).transform_values(&:to_sym))
    end

    def fail_with_rollback!(message = nil, error_code: nil)
      fail!(message, error_code: error_code)
      raise FailWithRollback
    end

    def method_missing(name, value = nil, *)
      if name.end_with?("=")
        self[name.to_s.delete_suffix("=")] = value
      elsif key?(name)
        self[name]
      else
        super
      end
    end

    def respond_to_missing?(name, _include_private)
      key?(name.to_s.delete_suffix("="))
    end

    private

    def resolve_alias(key)
      key = key.to_sym
      @aliases.fetch(key, key)
    end

    def localize(message, options)
      adapter = Workflow.configuration.localization_adapter
      return message if adapter.nil?

      adapter.failure(message, nil, options)
    end
  end
end
