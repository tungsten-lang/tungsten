# Spec::Hooks — before/after each/all hook storage
# Hooks are collected from the context ancestry chain and run in order.

in Tungsten:Spec

+ Hooks
  ro :registry

  -> new
    @registry = {
      before_each: [],
      after_each:  [],
      before_all:  [],
      after_all:   []
    }

  -> add(type, block)
    @registry[type].push(block)
    self

  -> get(type)
    @registry[type] || []

  -> empty?
    @registry.values.all?(v -> v.empty?)
