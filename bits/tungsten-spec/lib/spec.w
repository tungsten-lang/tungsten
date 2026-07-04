# Tungsten Spec — a behavior-driven testing framework for Tungsten
# Inspired by RSpec. Provides describe/context/it blocks, expectations,
# matchers, hooks, mocks, and a configurable test runner.
#
# Usage:
#   use Tungsten:Spec
#
#   describe Calculator ->
#     context "addition" ->
#       it "adds two numbers" ->
#         expect(Calculator.add(2, 3)).to eq(5)

in Tungsten:Spec

use context
use expectation
use matchers
use runner
use hooks
use mock

VERSION = "0.1.0"

# Top-level describe — creates a root context and registers it with the runner
-> describe(subject, tags: [], &block)
  ctx = Context.new(subject.to_s, parent: nil, tags: tags)
  ctx.instance_eval(&block)
  Runner.register(ctx)
  ctx

# Configuration DSL
-> configure(&block)
  Config.instance.instance_eval(&block)

# Run all registered specs
-> run(options = {})
  Runner.new(Config.instance.merge(options)).run


+ Config
  @@instance = nil

  -> .instance
    @@instance ||= self.new

  rw :format
  rw :color
  rw :fail_fast
  rw :seed
  rw :filter_tags

  -> new
    @format      = :dots
    @color       = true
    @fail_fast   = false
    @seed        = nil
    @filter_tags = []

  -> merge(options)
    options.each -> (key, value)
      self.send("#{key}=", value) if value
    self
