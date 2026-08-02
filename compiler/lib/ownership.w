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
  # Known heap-allocating runtime calls. w_int_to_s (typed-receiver to_s
  # route) is here and w_to_s is NOT: w_to_s returns its argument for
  # string inputs and a rope's cached flat for rope inputs, so freeing
  # its "fresh" result can free storage someone else still owns.
  # w_int_to_s guarantees an independent result for every input.
  if op == :call_direct_i64
    name = inst[:name]
    return name in ("w_string" "w_hash_new" "w_array_new" "w_strbuf_new" "w_str_concat" "w_str_concat_free_rhs" "w_str_concat_free_lhs" "w_int_to_s")
  false

# Runtime calls that only READ their arguments: no argument pointer is
# stored anywhere, so passing a value to one of these must not pin it as
# escaped. Grown case-by-case, each name verified against the C body:
#   w_string_byte_length — reads the length (flattens a rope in place,
#     which allocates INTO the rope; the argument itself is not retained)
#   w_hash_get — probes by hash + eq; the key is compared, never stored
#   w_eq / w_neq / cmp fast helpers — pure comparisons
#   w_string_index / w_string_rindex / w_string_count — read-only scans
# NOT here, deliberately: w_str_concat (retains both sides in a rope
# node past 61 bytes), w_str_append (may realloc its receiver's buffer
# into the result), w_hash_set / w_array_push (store the value).
-> is_nonretaining_consumer(name)
  name in ("w_string_byte_length" "w_hash_get" "w_eq" "w_neq" "__w_streq_fast" "__w_streq2_fast" "__w_eq_fast" "__w_neq_fast" "__w_lt_fast" "__w_gt_fast" "__w_lte_fast" "__w_gte_fast" "w_string_index" "w_string_rindex" "w_string_count")

# Mark temps that escape through this instruction.
-> mark_escapes(inst, escaped)
  op = inst[:op]

  if op in (:call_direct_i64 :call_direct_void)
    # All args escape, except for whitelisted read-only consumers —
    # without the whitelist, `s = i.to_s(); use(s.size())` pinned every
    # transient string as escaped and no loop string was ever freed.
    if op == :call_direct_i64 && is_nonretaining_consumer(inst[:name])
      return nil
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

  # Inline ivar store (constructor fast path: raw gep + store). Same
  # semantics as :ivar_set — the stored value now lives in the object.
  if op == :ivar_set_idx
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

  # Lowering-emitted phi (safe-nav merge, rescue-expression merge, inlined
  # iterator carry): same dominance argument as :phi_ssa above, different
  # shape — two (value, label) pairs instead of an incoming list.
  if op == :phi_i64
    escaped[inst[:temp]] = true
    if inst[:a_value] != nil
      escaped[inst[:a_value]] = true
    if inst[:b_value] != nil
      escaped[inst[:b_value]] = true
    return nil

  # Stores that retain the value past the scope: class variables, `- data`
  # view fields (w64/scalar slots hold a boxed WValue), memo-table globals,
  # class objects, and the constructor slab fast path's sibling.
  if op in (:store_cvar :view_store_field :store_memo_ptr :class_store :slab_node_set_idx)
    escaped[inst[:value]] = true
    return nil

  # Inline container element stores — a WValue written into an array slot
  # without a runtime call the arg-escape arm above would see.
  if op in (:small_array_set_inline :typed_array_set_inline :typed_array_compound_op_inline)
    escaped[inst[:value]] = true
    return nil
  if op in (:bool_array_set_inline :bool_array_set_byte_inline)
    escaped[inst[:val]] = true
    return nil

  # Runtime retention the free pass cannot see: the raise-unwind cleanup
  # stack holds the value (free + cleanup-recycle would double-free), and
  # the recycle ops hand the buffer to a pool.
  if op in (:cleanup_push_hash :cleanup_push_array :cleanup_push_typed :cleanup_push_strbuf :call_recycle_hash :call_recycle_array :call_recycle_typed :call_recycle_strbuf)
    escaped[inst[:value]] = true
    return nil

  # Remaining call shapes: today these carry raw pointers/slots rather than
  # boxed WValues, but nothing enforces that — escape their args so a future
  # WValue-carrying use fails safe (a leak, not a UAF).
  if op in (:call_direct_i128 :call_direct_i64_ptr1 :call_direct_void_ptr1 :call_direct_ptr :call_fused_out_reuse)
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
