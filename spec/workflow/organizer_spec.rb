# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Organizer do
  let(:organizer_class) do
    Class.new do
      include Workflow::Organizer
    end
  end

  let(:organizer) { organizer_class.new }

  describe "#with" do
    it "creates OrganizerSession with Context from hash" do
      session = organizer.with(foo: 1)
      expect(session).to be_a(Workflow::OrganizerSession)
    end

    it "uses Context directly when given one" do
      ctx = Workflow::Context.new(foo: 1)
      session = organizer.with(ctx)
      expect(session).to be_a(Workflow::OrganizerSession)
    end

    it "sets ctx.organized_by to self" do
      session = organizer.with(foo: 1)
      # Access the internal context via reduce
      result = session.reduce([])
      expect(result.organized_by).to equal(organizer)
    end

    it "returns OrganizerSession" do
      expect(organizer.with({})).to be_a(Workflow::OrganizerSession)
    end
  end

  describe "#reduce" do
    it "shortcut works without explicit with" do
      result = organizer.reduce(->(ctx) {
        ctx[:set] = true
        ctx
      })
      expect(result[:set]).to eq(true)
    end
  end

  describe "control-flow helpers" do
    it "reduce_if returns a ReduceIf step" do
      step = organizer.reduce_if(->(ctx) { true }, [])
      expect(step).to be_a(Workflow::Steps::ReduceIf)
    end

    it "reduce_if_else returns a ReduceIfElse step" do
      step = organizer.reduce_if_else(->(ctx) { true }, [], [])
      expect(step).to be_a(Workflow::Steps::ReduceIfElse)
    end

    it "iterate returns an Iterate step" do
      step = organizer.iterate(:items, [])
      expect(step).to be_a(Workflow::Steps::Iterate)
    end

    it "execute returns an Execute step" do
      step = organizer.execute { |ctx| ctx }
      expect(step).to be_a(Workflow::Steps::Execute)
    end
  end
end
