# frozen_string_literal: true

module Workflow
  class Configuration
    attr_accessor :logger, :localization_adapter, :strict_context_access

    def initialize
      @logger = nil
      @localization_adapter = nil
      @strict_context_access = false
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end
  end
end
