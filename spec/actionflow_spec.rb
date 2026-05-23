# frozen_string_literal: true

RSpec.describe Actionflow do
  it "has a version number" do
    expect(Actionflow::VERSION).to eq("0.1.0")
  end

  it "exposes the Workflow namespace" do
    expect(Workflow).to be_a(Module)
    expect(Workflow::Context).to be_a(Class)
    expect(Workflow::Action).to be_a(Module)
    expect(Workflow::Organizer).to be_a(Module)
  end
end
