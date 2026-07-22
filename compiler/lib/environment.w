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

  # Frame-scoped lookup: like `defined?`, but stops at the method barrier, so
  # only the enclosing frame's own locals (and any block scopes nested inside
  # it) count. `get`/`defined?` deliberately read straight past the barrier to
  # reach top-level names, which makes them the wrong question for implicit
  # block-parameter inference: a caller frame's `i` would make the block's own
  # `i` look already-bound and silently demote an implicit parameter to a
  # capture. Mirrors the Ruby engine's
  # Environment#defined_locally_or_in_scope? (implementations/ruby).
  -> defined_locally_or_in_scope?(name)
    if @bindings.has_key?(name)
      return true
    if @barrier
      return false
    if @parent == nil
      return false
    @parent.defined_locally_or_in_scope?(name)

  -> parent
    @parent
