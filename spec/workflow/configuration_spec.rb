# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Configuration do
  subject(:config) { described_class.new }

  it "has nil logger by default" do
    expect(config.logger).to be_nil
  end

  it "has nil localization_adapter by default" do
    expect(config.localization_adapter).to be_nil
  end

  it "has empty before_hooks by default" do
    expect(config.before_hooks).to eq([])
  end

  it "has empty after_hooks by default" do
    expect(config.after_hooks).to eq([])
  end

  it "has empty around_hooks by default" do
    expect(config.around_hooks).to eq([])
  end

  it "allows setting logger" do
    logger = instance_double("Logger")
    config.logger = logger
    expect(config.logger).to eq(logger)
  end

  it "allows setting localization_adapter" do
    adapter = instance_double("LocalizationAdapter")
    config.localization_adapter = adapter
    expect(config.localization_adapter).to eq(adapter)
  end

  it "allows setting before_hooks" do
    hook = ->(*_) {}
    config.before_hooks = [hook]
    expect(config.before_hooks).to eq([hook])
  end

  it "allows setting after_hooks" do
    hook = ->(*_) {}
    config.after_hooks = [hook]
    expect(config.after_hooks).to eq([hook])
  end

  it "allows setting around_hooks" do
    hook = ->(*_, &blk) { blk.call }
    config.around_hooks = [hook]
    expect(config.around_hooks).to eq([hook])
  end
end

RSpec.describe "Workflow.configuration" do
  after do
    Workflow.instance_variable_set(:@configuration, nil)
  end

  it "returns a Configuration instance" do
    expect(Workflow.configuration).to be_a(Workflow::Configuration)
  end

  it "returns the same instance on repeated calls" do
    expect(Workflow.configuration).to equal(Workflow.configuration)
  end

  it "can be configured via Workflow.configure" do
    Workflow.configure do |c|
      c.logger = :test_logger
    end

    expect(Workflow.configuration.logger).to eq(:test_logger)
  end
end
