# frozen_string_literal: true

require_relative "actionflow/version"

module Workflow
  autoload :ActionMetadata, "workflow/action_metadata"
  autoload :Configuration, "workflow/configuration"
  autoload :Context, "workflow/context"
  autoload :Action, "workflow/action"
  autoload :ActionRunner, "workflow/action_runner"
  autoload :OrganizerSession, "workflow/organizer_session"
  autoload :Reducer, "workflow/reducer"
  autoload :RollbackStrategy, "workflow/rollback_strategy"
  autoload :Localization, "workflow/localization"

  module Steps
    autoload :ReduceIf, "workflow/steps/reduce_if"
    autoload :ReduceIfElse, "workflow/steps/reduce_if_else"
    autoload :ReduceWhile, "workflow/steps/reduce_while"
    autoload :ReduceUntil, "workflow/steps/reduce_until"
    autoload :ReduceCase, "workflow/steps/reduce_case"
    autoload :Iterate, "workflow/steps/iterate"
    autoload :Execute, "workflow/steps/execute"
    autoload :AddToContext, "workflow/steps/add_to_context"
    autoload :AddAliases, "workflow/steps/add_aliases"
    autoload :WithCallback, "workflow/steps/with_callback"
  end

  module Ai
    autoload :Capability, "workflow/ai/capability"
    autoload :CapabilityRegistry, "workflow/ai/capability_registry"
    autoload :Plan, "workflow/ai/plan"
    autoload :PlanValidator, "workflow/ai/plan_validator"
    autoload :PlanCompiler, "workflow/ai/plan_compiler"
    autoload :DynamicOrganizer, "workflow/ai/dynamic_organizer"
  end

  module Testing
    autoload :ContextFactory, "workflow/testing/context_factory"
  end
end

require "workflow/errors"
