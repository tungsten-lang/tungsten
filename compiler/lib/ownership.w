# Ownership analysis — classify each value as ESCAPED or locally owned.
# Runs after SSA conversion, before emit. Walks SSA'd WIRE IR in RPO.

use runtime_types

# Does this instruction produce a value that definitely heap-allocates?
# Only track KNOWN constructors, not arbitrary call results.
-> is_heap_producer(inst)
  op = inst[:op]
  # string_i64 creates interned slab strings — NOT freeable
  # class_new creates classes that live forever — NOT freeable
  if op == :closure_new
    return true
  if op in (:const_float :const_decimal :const_currency :const_quantity :const_duration_ns :const_duration_months_ms :const_uuid)
    return true
  # Known heap-allocating runtime calls
  if op == :call_direct_i64
    name = inst[:name]
    return name in ("w_string" "w_hash_new" "w_array_new" "w_strbuf_new" "w_str_concat" "w_to_s")
  false

# Mark temps that escape through this instruction.
-> mark_escapes(inst, escaped)
  op = inst[:op]

  if op in (:call_direct_i64 :call_direct_void)
    # All args escape (conservative v1)
    args = inst[:args]
    if args != nil
      i = 0
      while i < args.size()
        escaped[args[i]] = true
        i += 1
    return nil

  if op == :call_method_i64
    # Receiver and all args escape (dynamic dispatch)
    if inst[:receiver] != nil
      escaped[inst[:receiver]] = true
    args = inst[:args]
    if args != nil
      i = 0
      while i < args.size()
        escaped[args[i]] = true
        i += 1
    return nil

  if op == :ret_i64
    escaped[inst[:value]] = true
    return nil

  if op == :ivar_set
    escaped[inst[:value]] = true
    return nil

  if op == :store_global
    escaped[inst[:value]] = true
    return nil

  if op == :store_ptr
    escaped[inst[:value]] = true
    return nil

  if op == :closure_new
    if inst[:captures_ptr] != nil
      escaped[inst[:captures_ptr]] = true
    return nil

  if op == :store_i64
    # Non-promoted var store: value escapes (can't track through memory)
    escaped[inst[:value]] = true
    return nil

  # I/O: puts and print consume their value argument
  if op in (:puts_i64 :print_i64)
    escaped[inst[:value]] = true
    return nil

  # Select: both operands may be used, treat as escape
  if op == :select_i64
    escaped[inst[:then_val]] = true
    escaped[inst[:else_val]] = true
    return nil

  # Memo calls: args escape
  if op in (:memo_call0_i64 :memo_call1_i64 :memo_call2_i64)
    args = inst[:args]
    if args != nil
      i = 0
      while i < args.size()
        escaped[args[i]] = true
        i += 1
    return nil

  nil

# Analyze one function: classify all value-producing temps.
-> ownership_analyze(func, mod)
  blocks = func[:blocks]
  if blocks.size() == 0
    return nil

  escaped = {}
  producers = {}
  scope_locals = {}
  scope_stack = []
  func_scope_temps = []

  # Walk blocks in order (sufficient for monotonic analysis)
  bi = 0
  while bi < blocks.size()
    blk = blocks[bi]
    instrs = blk[:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      op = inst[:op]

      # Scope tracking
      if op == :scope_push
        scope_stack.push({id: inst[:id], temps: []})
      elsif op == :scope_pop
        if scope_stack.size() > 0
          scope = scope_stack.pop()
          scope_locals[scope[:id]] = scope[:temps]
      elsif op == :phi_ssa
        # Treat the phi and every incoming value as one escaping group.  An
        # incoming producer may only dominate one branch, so freeing it at a
        # scope_pop would violate SSA dominance.  Marking the result here too
        # makes this independent of phi ordering, including loop backedges.
        incoming = inst[:incoming]
        if incoming != nil
          escaped[inst[:temp]] = true
          pi = 0
          while pi < incoming.size()
            v = incoming[pi]
            escaped[v] = true
            pi += 2
      else
        # Value producers: record and track in current scope
        if inst[:temp] != nil
          if is_heap_producer(inst)
            producers[inst[:temp]] = {op: op, block: bi}
            if scope_stack.size() > 0
              scope_stack[scope_stack.size() - 1][:temps].push(inst[:temp])
            elsif bi == 0
              # Function-body scope: a producer in the ENTRY block at scope
              # depth 0 has no enclosing if/while/with scope_pop to free it,
              # so straight-line helpers (e.g. `s = a + b.to_s(); use(s)`)
              # leaked every heap string/bigint they built. The entry block
              # dominates every ret, so such a value is defined on all paths;
              # if it's also non-escaped it's dead by the return and safe to
              # free there. Producers in NON-entry scope-0 blocks are skipped
              # (conservative — they may not dominate a given ret).
              func_scope_temps.push(inst[:temp])
          # Loads from memory/globals: conservatively escaped
          if op in (:load_i64 :load_global :load_class :load_ptr)
            escaped[inst[:temp]] = true
        # Mark escapes for this instruction
        mark_escapes(inst, escaped)

      ii += 1
    bi += 1

  func[:ownership] = {escaped: escaped, producers: producers, scope_locals: scope_locals, func_scope: func_scope_temps}

# Entry point: analyze all functions in the module.
-> ownership_pass(mod)
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    if func[:blocks].size() > 0
      ownership_analyze(func, mod)
    fi += 1

# Insert free calls at scope_pop for non-escaped heap-produced values.
# Modifies WIRE blocks in place: injects :free_value instructions before scope_pop.
-> insert_frees(func)
  own = func[:ownership]
  if own == nil
    return nil
  escaped = own[:escaped]
  producers = own[:producers]
  scope_locals = own[:scope_locals]
  func_scope = own[:func_scope]

  blocks = func[:blocks]
  bi = 0
  while bi < blocks.size()
    instrs = blocks[bi][:instructions]
    new_instrs = []
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      if inst[:op] == :scope_pop
        # Free non-escaped heap values from this scope
        sid = inst[:id]
        locals = scope_locals[sid]
        if locals != nil
          li = 0
          while li < locals.size()
            temp = locals[li]
            if escaped[temp] != true && producers[temp] != nil
              new_instrs.push({op: :free_value, value: temp})
            li += 1
      # Function-body scope: free non-escaped entry-block producers right
      # before each return. The entry block dominates every ret, so these
      # values are defined on all paths and (being non-escaped) dead here.
      # Only one ret runs per call, so freeing before each is not a double
      # free at runtime.
      if inst[:op] in (:ret_i64 :ret_i32 :ret_void) && func_scope != nil
        fi = 0
        while fi < func_scope.size()
          temp = func_scope[fi]
          if escaped[temp] != true && producers[temp] != nil
            new_instrs.push({op: :free_value, value: temp})
          fi += 1
      new_instrs.push(inst)
      ii += 1
    blocks[bi][:instructions] = new_instrs
    bi += 1

# Entry point for free insertion across all functions.
-> free_insertion_pass(mod)
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    if func[:blocks].size() > 0
      insert_frees(func)
    fi += 1
