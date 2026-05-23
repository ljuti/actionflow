# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::ExpectedKeysMissing do
  it "inherits from StandardError" do
    expect(described_class).to be < StandardError
  end

  it "includes missing key names in the message" do
    error = described_class.new("Missing expected keys: [:user, :amount]")
    expect(error.message).to include("user")
    expect(error.message).to include("amount")
  end
end

RSpec.describe Workflow::PromisedKeysMissing do
  it "inherits from StandardError" do
    expect(described_class).to be < StandardError
  end

  it "includes missing key names in the message" do
    error = described_class.new("Missing promised keys: [:charge]")
    expect(error.message).to include("charge")
  end
end

RSpec.describe Workflow::FailWithRollback do
  it "inherits from StandardError" do
    expect(described_class).to be < StandardError
  end
end
