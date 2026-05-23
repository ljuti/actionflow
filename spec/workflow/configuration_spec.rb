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

  it "has strict_context_access false by default" do
    expect(config.strict_context_access).to eq(false)
  end

  it "has strict_context_access as exactly false (not nil)" do
    expect(config.strict_context_access).to be(false)
    expect(config.strict_context_access).not_to be_nil
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

  it "allows setting strict_context_access" do
    config.strict_context_access = true
    expect(config.strict_context_access).to eq(true)
  end
end

RSpec.describe "Workflow.configuration" do
  after do
    # Reset to defaults after each test
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
      c.strict_context_access = true
    end

    expect(Workflow.configuration.strict_context_access).to eq(true)
  end
end
