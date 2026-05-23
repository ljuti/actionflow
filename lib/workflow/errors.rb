# frozen_string_literal: true

module Workflow
  class ExpectedKeysMissing < StandardError; end
  class PromisedKeysMissing < StandardError; end
  class FailWithRollback < StandardError; end
end
