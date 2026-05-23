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

  it "returns ctx when match found" do
    step = described_class.new(
      ->(ctx) { ctx[:type] },
      {admin: [->(ctx) { ctx }]}
    )
    ctx = Workflow::Context.new(type: :admin)
    expect(step.call(ctx)).to equal(ctx)
  end

  it "returns ctx when no match" do
    step = described_class.new(
      ->(ctx) { ctx[:type] },
      {admin: [->(ctx) { ctx }]}
    )
    ctx = Workflow::Context.new(type: :guest)
    expect(step.call(ctx)).to equal(ctx)
  end

  it "returns ctx when stop_processing?" do
    step = described_class.new(
      ->(ctx) { ctx[:type] },
      {admin: [->(ctx) { ctx }]}
    )
    ctx = Workflow::Context.new(type: :admin)
    ctx.fail!
    result = step.call(ctx)
    expect(result).to equal(ctx)
  end

  it "does not run steps when stop_processing?" do
    ran = false
    step = described_class.new(
      ->(ctx) { :admin },
      {admin: [->(ctx) {
        ran = true
        ctx
      }]}
    )
    ctx = Workflow::Context.new
    ctx.fail!
    step.call(ctx)
    expect(ran).to eq(false)
  end

  it "resets skip_remaining on scope exit" do
    step = described_class.new(
      ->(ctx) { :admin },
      {admin: [->(ctx) {
        ctx.skip_remaining!
        ctx
      }]}
    )
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx).not_to be_skip_remaining
  end

  it "does not reset skip_remaining on failure" do
    step = described_class.new(
      ->(ctx) { :admin },
      {admin: [->(ctx) {
        ctx.skip_remaining!
        ctx.fail!("case error")
        ctx
      }]}
    )
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx).to be_failure
    expect(ctx).to be_skip_remaining
  end

  it "preserves failure message when skip_remaining is not reset" do
    step = described_class.new(
      ->(ctx) { :admin },
      {admin: [->(ctx) {
        ctx.skip_remaining!
        ctx.fail!("case error")
        ctx
      }]}
    )
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx.message).to eq("case error")
  end

  it "does not reset skip_remaining when skip_all_remaining is set" do
    step = described_class.new(
      ->(ctx) { :admin },
      {admin: [->(ctx) {
        ctx.skip_remaining!
        ctx.skip_all_remaining!
        ctx
      }]}
    )
    ctx = Workflow::Context.new
    step.call(ctx)
    expect(ctx).to be_skip_all_remaining
    expect(ctx).to be_skip_remaining
  end
end
