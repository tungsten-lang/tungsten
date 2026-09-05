# Scope chain for variable bindings

+ Environment
  -> new(@parent = nil, @barrier = false)
    @bindings = {}
    # Machine-width ascriptions (`x = 0 ## i64`) recorded per binding, so the
    # interpreter can mirror the compiled engine's fixed-width slots: every
    # later read of `x` in arithmetic wraps at that width. Lazily allocated —
    # most scopes never see a hint.
    @hints = nil

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

  # Record `hint` for the binding `set` would write: this scope if the name
  # is bound (or unbound) here, else the owning ancestor. Same barrier rule
  # as `set`, so a hint lands where the value does.
  -> set_hint(name, hint)
    if @bindings.has_key?(name) || @barrier || @parent == nil || !@parent.defined?(name)
      if @hints == nil
        @hints = {}
      @hints[name] = hint
    else
      @parent.set_hint(name, hint)

  # The machine hint on the binding `get` would read, or nil. A binding
  # found without a hint answers nil without consulting ancestors (a
  # shadowing block local is a different variable from an outer typed one).
  -> hint(name)
    if @hints != nil && @hints.has_key?(name)
      return @hints[name]
    if @bindings.has_key?(name)
      return nil
    if @parent != nil
      return @parent.hint(name)
    nil

  # Reuse one invocation scope when the interpreter has proved that no nested
  # closure can retain it. The runtime reset preserves the table allocation,
  # while making block locals fresh exactly as Environment.new would.
  -> clear_bindings
    ccall("w_hash_clear_reuse", @bindings)
    @hints = nil
    self

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
