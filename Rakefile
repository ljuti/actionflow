# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "standard/rake"

task default: %i[spec standard]

desc "Run mutation testing (pass SUBJECT to narrow scope, e.g. SUBJECT='Workflow::Context#')"
task :mutant do
  subject = ENV.fetch("SUBJECT", "Workflow*")
  sh "bundle", "exec", "mutant", "run", "--usage", "opensource", "--", subject
end
