# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Steps::ReduceCase do
  it "runs steps matching the value" do
    ran = false
    step = described_class.new(
      ->(ctx) { ctx[:type] },
      {admin: [->(ctx) {
        ran = true
        ctx
      }], user: []}
    )
    ctx = Workflow::Context.new(type: :admin)
    step.call(ctx)
    expect(ran).to eq(true)
  end

  it "does not run steps when no match" do
    ran = false
    step = described_class.new(
      ->(ctx) { ctx[:type] },
      {admin: [->(ctx) {
        ran = true
        ctx
      }]}
    )
    ctx = Workflow::Context.new(type: :guest)
    step.call(ctx)
    expect(ran).to eq(false)
  end

  it "only runs the matching branch, not all" do
    admin_ran = false
    user_ran = false
    step = described_class.new(
      ->(ctx) { ctx[:type] },
      {admin: [->(ctx) do
        admin_ran = true
        ctx
      end], user: [->(ctx) do
        user_ran = true
        ctx
      end]}
    )
    ctx = Workflow::Context.new(type: :admin)
    step.call(ctx)
    expect(admin_ran).to eq(true)
    expect(user_ran).to eq(false)
  end
end
