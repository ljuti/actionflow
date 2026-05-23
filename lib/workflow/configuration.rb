# frozen_string_literal: true

module Workflow
  class Configuration
    attr_accessor :logger, :localization_adapter
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
