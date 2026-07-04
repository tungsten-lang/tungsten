# Scope chain for variable bindings

+ Environment
  -> new(@parent = nil, @barrier = false)
    @bindings = {}

  -> get(name)
    if @bindings.has_key?(name)
      return @bindings[name]
    if @parent != nil
      return @parent.get(name)
    raise "Undefined variable '[name]'"

  -> set(name, value)
    if @bindings.has_key?(name)
      @bindings[name] = value
    elsif !@barrier && @parent != nil && @parent.defined?(name)
      @parent.set(name, value)
    else
      @bindings[name] = value

  -> define(name, value)
    @bindings[name] = value

  -> defined?(name)
    if @bindings.has_key?(name)
      return true
    if @parent != nil
      return @parent.defined?(name)
    false

  -> defined_locally?(name)
    @bindings.has_key?(name)

  -> parent
    @parent
