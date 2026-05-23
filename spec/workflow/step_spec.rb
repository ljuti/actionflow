# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Step do
  describe "#call" do
    it "raises NotImplementedError on bare Step" do
      ctx = Workflow::Context.new
      expect { described_class.new.call(ctx) }.to raise_error(
        NotImplementedError,
        "Workflow::Step must implement #execute"
      )
    end

    it "does not run execute when stopped by failure" do
      step = Class.new(described_class) do
        private

        def execute(ctx)
          ctx[:executed] = true
        end
      end.new

      ctx = Workflow::Context.new
      ctx.fail!("stopped")
      result = step.call(ctx)

      expect(result).to equal(ctx)
      expect(ctx.key?(:executed)).to eq(false)
      expect(ctx).to be_failure
    end

    it "does not run execute when stopped by skip_remaining" do
      step = Class.new(described_class) do
        private

        def execute(ctx)
          ctx[:executed] = true
        end
      end.new

      ctx = Workflow::Context.new
      ctx.skip_remaining!
      result = step.call(ctx)

      expect(result).to equal(ctx)
      expect(ctx.key?(:executed)).to eq(false)
    end

    it "does not run execute when stopped by skip_all_remaining" do
      step = Class.new(described_class) do
        private

        def execute(ctx)
          ctx[:executed] = true
        end
      end.new

      ctx = Workflow::Context.new
      ctx.skip_all_remaining!
      result = step.call(ctx)

      expect(result).to equal(ctx)
      expect(ctx.key?(:executed)).to eq(false)
    end

    it "runs execute and returns ctx when not stopped" do
      step = Class.new(described_class) do
        private

        def execute(ctx)
          ctx[:executed] = true
        end
      end.new

      ctx = Workflow::Context.new
      result = step.call(ctx)

      expect(result).to equal(ctx)
      expect(ctx[:executed]).to eq(true)
    end
  end

  describe "#scoped_reduce" do
    let(:step) { described_class.new }

    it "runs steps through the reducer" do
      ran = false
      ctx = Workflow::Context.new
      step.send(:scoped_reduce, ctx, [->(c) {
        ran = true
        c
      }])
      expect(ran).to eq(true)
    end

    it "runs workflow actions through ActionRunner" do
      action = Class.new do
        include Workflow::Action

        promises :result

        def call(ctx)
          ctx[:result] = :done
        end

        def workflow_metadata
          Workflow::ActionMetadata.new(promised_keys: [:result])
        end
      end.new

      ctx = Workflow::Context.new
      step.send(:scoped_reduce, ctx, [action])
      expect(ctx[:result]).to eq(:done)
    end

    it "resets skip_remaining on scope exit" do
      ctx = Workflow::Context.new
      step.send(:scoped_reduce, ctx, [->(c) {
        c.skip_remaining!
        c
      }])
      expect(ctx).not_to be_skip_remaining
    end

    it "preserves failure message by not resetting skip_remaining" do
      ctx = Workflow::Context.new
      step.send(:scoped_reduce, ctx, [->(c) {
        c.fail!("err")
        c
      }])
      expect(ctx).to be_failure
      expect(ctx.message).to eq("err")
    end

    it "preserves skip_all_remaining message by not resetting skip_remaining" do
      ctx = Workflow::Context.new
      step.send(:scoped_reduce, ctx, [->(c) {
        c.skip_all_remaining!("msg")
        c
      }])
      expect(ctx).to be_skip_all_remaining
      expect(ctx.message).to eq("msg")
    end
  end
end
