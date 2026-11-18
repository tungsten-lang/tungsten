# Scope chain for variable bindings

+ Environment
  -> new(@parent = nil, @barrier = false)
    @has_children = false
    if @parent != nil
      @parent.note_child()
    @bindings = {}
    # Per-name integer policy for the tree walker: "int"/"bigint" promote,
    # "i64"/"u64" wrap. Missing means the compiled default (wrap +/-/*,
    # promote untyped <<).
    @hints = {}
    # Closure capture set (capture_only): when non-nil, only these names
    # write through to the parent; any other assignment is a local of this
    # scope even if an ancestor binds the name by the time the body runs.
    @captured = nil

  -> get(name)
    if @bindings.has_key?(name)
      return @bindings[name]
    if @parent != nil
      return @parent.get(name)
    raise "Undefined variable '[name]'"

  -> set(name, value)
    if @bindings.has_key?(name)
      @bindings[name] = value
    elsif writes_through?(name)
      @parent.set(name, value)
    else
      @bindings[name] = value

  -> define(name, value)
    @bindings[name] = value

  # Does an assignment to a name unbound here land on an ancestor?
  -> writes_through?(name)
    if @barrier || @parent == nil
      return false
    if @captured != nil && !@captured.has_key?(name)
      return false
    @parent.defined?(name)

  # Restrict write-through to `names` (a Hash of name → true): the scope of a
  # body that runs later than it was written — a `go` goroutine — captures
  # the variables visible where it was spawned, like a compiled closure
  # captures the slots in scope at its definition, and treats everything
  # else as its own local.
  -> capture_only(names)
    @captured = names
    self

  # Every name bound in this scope or an ancestor, added to `into`.
  -> collect_visible_names(into)
    @bindings.keys.each -> (k)
      into[k] = true
    if @parent != nil
      @parent.collect_visible_names(into)
    into

  -> set_hint(name, hint)
    if @bindings.has_key?(name)
      @hints[name] = hint
    elsif writes_through?(name)
      @parent.set_hint(name, hint)
    else
      @hints[name] = hint

  -> get_hint(name)
    if @bindings.has_key?(name)
      if @hints.has_key?(name)
        return @hints[name]
      return nil
    if @parent != nil
      return @parent.get_hint(name)
    nil

  # The hint on the binding an assignment to `name` would write (the slot
  # `set` resolves to), or nil when that binding is new or unhinted. Unlike
  # get_hint this stops where `set` stops, so a method-local or goroutine
  # local never inherits an outer binding's fixed width.
  -> slot_hint(name)
    if @bindings.has_key?(name)
      if @hints.has_key?(name)
        return @hints[name]
      return nil
    if writes_through?(name)
      return @parent.slot_hint(name)
    nil

  # Reuse one invocation scope when the interpreter has proved that no nested
  # closure can retain it. The runtime reset preserves the table allocation,
  # while making block locals fresh exactly as Environment.new would.
  -> clear_bindings
    ccall("w_hash_clear_reuse", @bindings)
    ccall("w_hash_clear_reuse", @hints)
    self

  # A closure or goroutine can still read this frame through its child scope.
  -> note_child
    @has_children = true

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

  ro :parent, :has_children
