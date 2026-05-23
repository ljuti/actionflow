# frozen_string_literal: true

module Workflow
  class ActionMetadata
    attr_reader :expected_keys, :promised_keys, :defaults

    def initialize(
      expected_keys: [],
      promised_keys: [],
      defaults: {}
    )
      @expected_keys = expected_keys
      @promised_keys = promised_keys
      @defaults = defaults
    end
  end
end
