# frozen_string_literal: true

require_relative "lib/actionflow/version"

Gem::Specification.new do |spec|
  spec.name = "actionflow"
  spec.version = Actionflow.gem_version
  spec.authors = ["Lauri Jutila"]
  spec.email = ["ljuti@nmux.dev"]

  spec.summary = "Dependency-injected, object-composed workflow orchestration for Ruby"
  spec.description = "Actionflow is a Ruby workflow gem inspired by LightService, " \
    "built around ordinary objects with constructor dependency injection, " \
    "explicit context-based data flow, and composable control-flow steps."
  spec.homepage = "https://github.com/ljuti/actionflow"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ljuti/actionflow"
  spec.metadata["changelog_uri"] = "https://github.com/ljuti/actionflow/blob/main/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .standard.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
