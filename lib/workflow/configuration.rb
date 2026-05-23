# frozen_string_literal: true

module Workflow
  class Configuration
    attr_accessor :logger, :localization_adapter,
      :before_hooks, :after_hooks, :around_hooks, :capture_exceptions

    def initialize
      @before_hooks = []
      @after_hooks = []
      @around_hooks = []
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
