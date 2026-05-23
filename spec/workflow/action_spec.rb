# frozen_string_literal: true

require "actionflow"

RSpec.describe Workflow::Action do
  before do
    # Define a fresh test action class for each test
    stub_const("TestAction", Class.new do
      include Workflow::Action

      expects :input
      promises :output

      def call(ctx)
        ctx[:output] = ctx[:input] * 2
      end
    end)
  end

  describe "expects DSL" do
    it "registers expected keys on the class" do
      klass = Class.new { include Workflow::Action; expects :a, :b }
      expect(klass.workflow_metadata.expected_keys).to eq(%i[a b])
    end

    it "supports default values" do
      klass = Class.new { include Workflow::Action; expects :flag, default: true }
      meta = klass.workflow_metadata
      expect(meta.expected_keys).to include(:flag)
      expect(meta.defaults[:flag]).to eq(true)
    end

    it "supports callable defaults" do
      klass = Class.new { include Workflow::Action; expects :flag, default: ->(ctx) { ctx[:base] + 1 } }
      meta = klass.workflow_metadata
      expect(meta.defaults[:flag]).to respond_to(:call)
    end

    it "accumulates from multiple expects calls" do
      klass = Class.new {
        include Workflow::Action
        expects :a
        expects :b
      }
      expect(klass.workflow_metadata.expected_keys).to eq(%i[a b])
    end
  end

  describe "promises DSL" do
    it "registers promised keys" do
      klass = Class.new { include Workflow::Action; promises :result }
      expect(klass.workflow_metadata.promised_keys).to eq(%i[result])
    end

    it "accumulates from multiple promises calls" do
      klass = Class.new {
        include Workflow::Action
        promises :a
        promises :b
      }
      expect(klass.workflow_metadata.promised_keys).to eq(%i[a b])
    end
  end

  describe "workflow_metadata" do
    it "instance delegates to class" do
      action = TestAction.new
      expect(action.workflow_metadata).to equal(TestAction.workflow_metadata)
    end
  end

  describe "#execute" do
    it "delegates to ActionRunner and returns ctx" do
      action = TestAction.new
      ctx = Workflow::Context.new(input: 5)
      result = action.execute(ctx)
      expect(result).to equal(ctx)
      expect(result[:output]).to eq(10)
    end

    it "verifies expected keys" do
      action = TestAction.new
      ctx = Workflow::Context.new
      expect { action.execute(ctx) }.to raise_error(Workflow::ExpectedKeysMissing)
    end

    it "verifies promised keys" do
      klass = Class.new {
        include Workflow::Action
        promises :missing_key

        def call(ctx)
          # intentionally don't set :missing_key
        end
      }
      action = klass.new
      expect { action.execute(Workflow::Context.new) }.to raise_error(Workflow::PromisedKeysMissing)
    end

    it "defaults to a new Context when no arg given" do
      klass = Class.new {
        include Workflow::Action

        def call(ctx)
          ctx[:set] = true
        end
      }
      action = klass.new
      result = action.execute
      expect(result[:set]).to eq(true)
    end
  end

  describe "rollback" do
    it "action can define rollback" do
      klass = Class.new {
        include Workflow::Action

        def call(ctx); end

        def rollback(ctx)
          ctx[:rolled_back] = true
        end
      }
      action = klass.new
      expect(action).to respond_to(:rollback)
    end

    it "action without rollback returns false for respond_to?" do
      klass = Class.new {
        include Workflow::Action

        def call(ctx); end
      }
      action = klass.new
      expect(action.respond_to?(:rollback)).to eq(false)
    end
  end

  describe "instance-specific metadata" do
    it "allows overriding workflow_metadata for parameterized actions" do
      klass = Class.new {
        include Workflow::Action

        def initialize(from:, to:)
          @from = from
          @to = to
        end

        def workflow_metadata
          Workflow::ActionMetadata.new(
            expected_keys: [@from],
            promised_keys: [@to]
          )
        end

        def call(ctx)
          ctx[@to] = ctx[@from].to_s.upcase
        end
      }

      action = klass.new(from: :name, to: :normalized)
      expect(action.workflow_metadata.expected_keys).to eq([:name])
      expect(action.workflow_metadata.promised_keys).to eq([:normalized])

      ctx = Workflow::Context.new(name: "alice")
      result = action.execute(ctx)
      expect(result[:normalized]).to eq("ALICE")
    end
  end
end
