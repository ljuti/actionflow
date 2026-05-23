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

        def execute(ctx, action_runner:)
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

        def execute(ctx, action_runner:)
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

        def execute(ctx, action_runner:)
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

        def execute(ctx, action_runner:)
          ctx[:executed] = true
        end
      end.new

      ctx = Workflow::Context.new
      result = step.call(ctx)

      expect(result).to equal(ctx)
      expect(ctx[:executed]).to eq(true)
    end

    it "passes action_runner through to execute" do
      step = Class.new(described_class) do
        private

        def execute(ctx, action_runner:)
          ctx[:runner] = action_runner
        end
      end.new

      custom_runner = Workflow::ActionRunner.new
      ctx = Workflow::Context.new
      step.call(ctx, action_runner: custom_runner)

      expect(ctx[:runner]).to equal(custom_runner)
    end

    it "defaults to ActionRunner.default when no runner given" do
      step = Class.new(described_class) do
        private

        def execute(ctx, action_runner:)
          ctx[:runner_class] = action_runner.class
        end
      end.new

      ctx = Workflow::Context.new
      step.call(ctx)

      expect(ctx[:runner_class]).to eq(Workflow::ActionRunner)
    end
  end

  describe "#scoped_reduce" do
    let(:step) { described_class.new }
    let(:runner) { Workflow::ActionRunner.new }

    it "runs steps through the reducer" do
      ran = false
      ctx = Workflow::Context.new
      step.send(:scoped_reduce, ctx, [->(c) {
        ran = true
        c
      }], action_runner: runner)
      expect(ran).to eq(true)
    end

    it "runs workflow actions through the provided ActionRunner" do
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
      step.send(:scoped_reduce, ctx, [action], action_runner: runner)
      expect(ctx[:result]).to eq(:done)
    end

    it "resets skip_remaining on scope exit" do
      ctx = Workflow::Context.new
      step.send(:scoped_reduce, ctx, [->(c) {
        c.skip_remaining!
        c
      }], action_runner: runner)
      expect(ctx).not_to be_skip_remaining
    end

    it "preserves failure message by not resetting skip_remaining" do
      ctx = Workflow::Context.new
      step.send(:scoped_reduce, ctx, [->(c) {
        c.fail!("err")
        c
      }], action_runner: runner)
      expect(ctx).to be_failure
      expect(ctx.message).to eq("err")
    end

    it "preserves skip_all_remaining message by not resetting skip_remaining" do
      ctx = Workflow::Context.new
      step.send(:scoped_reduce, ctx, [->(c) {
        c.skip_all_remaining!("msg")
        c
      }], action_runner: runner)
      expect(ctx).to be_skip_all_remaining
      expect(ctx.message).to eq("msg")
    end
  end
end
