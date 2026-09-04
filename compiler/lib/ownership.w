# Ownership analysis — classify each value as ESCAPED or locally owned.
# Runs after SSA conversion, before emit. Walks SSA'd WIRE IR in RPO.

use runtime_types
use wire

# Does this instruction produce a value that definitely heap-allocates?
# Only track KNOWN constructors, not arbitrary call results.
-> is_heap_producer(inst)
  op = wire_kind(inst)
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
    name = wire_get(inst, :name)
    # w_string_repeat mallocs a fresh WString for results past the inline
    # limit (and returns an inline/slab value below it, which w_value_free
    # ignores) — an independent result for every call, like w_int_to_s.
    # w_array_new_uninit_sized backs `[a, b, c]` literals (slots filled by
    # __w_array_lit_store below): a fresh owned WArray, freed like w_array_new.
    return name in ("w_string" "w_hash_new" "w_array_new" "w_array_new_uninit_sized" "w_strbuf_new" "w_str_concat" "w_str_concat_free_rhs" "w_str_concat_free_lhs" "w_str_concat_own" "w_int_to_s" "w_string_repeat")
  false

# Runtime calls that only READ their arguments: no argument pointer is
# stored anywhere, so passing a value to one of these must not pin it as
# escaped. Grown case-by-case, each name verified against the C body:
#   w_string_byte_length — reads an inline mode or a slab/heap/rope length;
#     the argument is not retained
#   w_hash_get — probes by hash + eq; the key is compared, never stored
#   w_eq / w_neq / cmp fast helpers — pure comparisons
#   w_string_index / w_string_rindex / w_string_count — read-only scans
#   w_string_repeat — copies the receiver's bytes into a fresh buffer; the
#     receiver is not retained (rope receivers are flattened first)
#   __w_string_byte_length_fast — the alwaysinline IR helper behind
#     String#size on a known string: reads the header, memory(read)
# NOT here, deliberately: w_str_concat (retains both sides in a rope
# node past 61 bytes), w_str_append (may realloc its receiver's buffer
# into the result), w_hash_set / w_array_push (store the value).
-> is_nonretaining_consumer(name)
  name in ("w_string_byte_length" "w_hash_get" "w_eq" "w_neq" "w_eq_lit" "w_neq_lit" "__w_streq_fast" "__w_streq2_fast" "__w_eq_fast" "__w_neq_fast" "__w_eq_lit_fast" "__w_neq_lit_fast" "__w_lt_fast" "__w_gt_fast" "__w_lte_fast" "__w_gte_fast" "w_string_index" "w_string_rindex" "w_string_count" "w_string_repeat" "__w_string_byte_length_fast" "w_wire_sequence_from_array")

# Per-parameter escape summary of a source function (escape.w, run before
# this pass): {escs: [stored-or-returned per param], stored_escs: [stored
# per param], ...}. nil for runtime externs and anything escape.w skipped.
-> fn_escape_summary(mod, name)
  if mod == nil || name == nil
    return nil
  summaries = mod[:fn_escs]
  if summaries == nil
    return nil
  summaries[name]

# Mark the arguments of a direct call to a source function according to the
# callee's summary: an argument the callee neither stores nor returns is
# merely read and stays owned by the caller. Anything outside the summary's
# range escapes. `first` is the parameter index of args[0] (1 when the
# receiver was marked separately as parameter 0).
-> mark_args_by_summary(args, first, summary, escaped)
  if args == nil
    return nil
  escs = summary[:escs]
  i = 0
  while i < wire_sequence_size(args)
    pi = first + i
    if escs == nil || pi >= escs.size() || escs[pi] == true
      escaped[wire_sequence_get(args, i)] = true
    i += 1
  nil

# A guarded `Cls.new(...)` construct (call_method_i64 with :construct_fn):
# the fast arm calls w_object_new and then the plain initializer worker, and
# the op's result is that fresh WObject; the slow arm is the ordinary IC
# dispatch and its result is unknown. The slow arm is unreachable when the
# receiver is the load of the very class the guard compares against, so the
# result is a fresh, unaliased object exactly when the initializer never
# STORES `self` anywhere (returning self is fine — the result is self).
# Returns the class name when the result is such a producer, else nil.
-> construct_producer_class(inst, mod, class_temps)
  construct_fn = wire_get(inst, :construct_fn)
  if construct_fn == nil
    return nil
  construct_class = wire_get(inst, :construct_class)
  receiver = wire_get(inst, :receiver)
  if construct_class == nil || receiver == nil
    return nil
  if class_temps[receiver] == nil || class_temps[receiver] != construct_class
    return nil
  summary = fn_escape_summary(mod, construct_fn)
  if summary == nil
    return nil
  stored = summary[:stored_escs]
  if stored == nil || stored.size() < 1 || stored[0] == true
    return nil
  construct_class

# Mark temps that escape through this instruction. `producers` maps temps
# already classified as heap producers to {op:, block:, class:}; a guarded
# devirtualized call on a construct-produced receiver of the same class is
# certain to take its direct arm, so the callee's summary applies.
-> mark_escapes(inst, escaped, mod, producers)
  op = wire_kind(inst)

  if op in (:call_direct_i64 :call_direct_void)
    # All args escape, except for whitelisted read-only consumers —
    # without the whitelist, `s = i.to_s(); use(s.size())` pinned every
    # transient string as escaped and no loop string was ever freed.
    if op == :call_direct_i64 && is_nonretaining_consumer(wire_get(inst, :name))
      return nil
    # Direct call to a source function with an escape summary: only the
    # parameters it stores or returns pin their arguments.
    summary = fn_escape_summary(mod, wire_get(inst, :name))
    if summary != nil
      mark_args_by_summary(wire_get(inst, :args), 0, summary, escaped)
      return nil
    # `__w_array_lit_store(arr, idx, val)` writes val into a slot of the
    # array literal being built: the VALUE is retained (by the array), the
    # array itself is not. Marking the array escaped here pinned every
    # `[i, j, k]` literal in a loop (131 MB at 2M iterations).
    if op == :call_direct_i64 && wire_get(inst, :name) == "__w_array_lit_store"
      args = wire_get(inst, :args)
      if args != nil && wire_sequence_size(args) >= 3
        escaped[wire_sequence_get(args, 2)] = true
      return nil
    args = wire_get(inst, :args)
    if args != nil
      i = 0
      while i < wire_sequence_size(args)
        escaped[wire_sequence_get(args, i)] = true
        i += 1
    return nil

  if op == :call_method_i64
    # Guarded devirtualized call whose receiver is a construct-produced
    # object of the guarded class: the direct arm is certain, so the
    # target's summary decides (receiver is parameter 0, args follow).
    receiver = wire_get(inst, :receiver)
    devirt_fn = wire_get(inst, :devirt_fn)
    if devirt_fn != nil && receiver != nil && producers != nil && producers[receiver] != nil
      producer_class = producers[receiver][:class]
      if producer_class != nil && producer_class == wire_get(inst, :devirt_class)
        summary = fn_escape_summary(mod, devirt_fn)
        if summary != nil
          escs = summary[:escs]
          if escs == nil || escs.size() < 1 || escs[0] == true
            escaped[receiver] = true
          mark_args_by_summary(wire_get(inst, :args), 1, summary, escaped)
          return nil
    # Receiver and all args escape (dynamic dispatch)
    if receiver != nil
      escaped[receiver] = true
    args = wire_get(inst, :args)
    if args != nil
      i = 0
      while i < wire_sequence_size(args)
        escaped[wire_sequence_get(args, i)] = true
        i += 1
    return nil

  if op == :ret_i64
    escaped[wire_get(inst, :value)] = true
    return nil

  if op == :ivar_set
    escaped[wire_get(inst, :value)] = true
    return nil

  # Inline ivar store (constructor fast path: raw gep + store). Same
  # semantics as :ivar_set — the stored value now lives in the object.
  if op == :ivar_set_idx
    escaped[wire_get(inst, :value)] = true
    return nil

  if op == :store_global
    escaped[wire_get(inst, :value)] = true
    return nil

  if op == :store_ptr
    escaped[wire_get(inst, :value)] = true
    return nil

  if op == :closure_new
    if wire_get(inst, :captures_ptr) != nil
      escaped[wire_get(inst, :captures_ptr)] = true
    return nil

  if op == :store_i64
    # Non-promoted var store: value escapes (can't track through memory)
    escaped[wire_get(inst, :value)] = true
    return nil

  # I/O: puts and print consume their value argument
  if op in (:puts_i64 :print_i64)
    escaped[wire_get(inst, :value)] = true
    return nil

  # Select: both operands may be used, treat as escape
  if op == :select_i64
    escaped[wire_get(inst, :then_val)] = true
    escaped[wire_get(inst, :else_val)] = true
    return nil

  # Memo calls: args escape
  if op in (:memo_call0_i64 :memo_call1_i64 :memo_call2_i64)
    args = wire_get(inst, :args)
    if args != nil
      i = 0
      while i < wire_sequence_size(args)
        escaped[wire_sequence_get(args, i)] = true
        i += 1
    return nil

  # Lowering-emitted phi (safe-nav merge, rescue-expression merge, inlined
  # iterator carry): same dominance argument as :phi_ssa above, different
  # shape — two (value, label) pairs instead of an incoming list.
  if op == :phi_i64
    escaped[wire_get(inst, :temp)] = true
    if wire_get(inst, :a_value) != nil
      escaped[wire_get(inst, :a_value)] = true
    if wire_get(inst, :b_value) != nil
      escaped[wire_get(inst, :b_value)] = true
    return nil

  # Stores that retain the value past the scope: class variables, `- data`
  # view fields (w64/scalar slots hold a boxed WValue), memo-table globals,
  # class objects, and the constructor slab fast path's sibling.
  if op in (:store_cvar :view_store_field :store_memo_ptr :class_store :slab_node_set_idx)
    escaped[wire_get(inst, :value)] = true
    return nil

  # Inline container element stores — a WValue written into an array slot
  # without a runtime call the arg-escape arm above would see.
  if op in (:small_array_set_inline :typed_array_set_inline :typed_array_compound_op_inline)
    escaped[wire_get(inst, :value)] = true
    return nil
  if op in (:bool_array_set_inline :bool_array_set_byte_inline)
    escaped[wire_get(inst, :val)] = true
    return nil

  # Runtime retention the free pass cannot see: the raise-unwind cleanup
  # stack holds the value (free + cleanup-recycle would double-free), and
  # the recycle ops hand the buffer to a pool.
  if op in (:cleanup_push_hash :cleanup_push_array :cleanup_push_typed :cleanup_push_strbuf :call_recycle_hash :call_recycle_array :call_recycle_typed :call_recycle_strbuf)
    escaped[wire_get(inst, :value)] = true
    return nil

  # Remaining call shapes: today these carry raw pointers/slots rather than
  # boxed WValues, but nothing enforces that — escape their args so a future
  # WValue-carrying use fails safe (a leak, not a UAF).
  if op in (:call_direct_i128 :call_direct_i64_ptr1 :call_direct_void_ptr1 :call_direct_ptr :call_fused_out_reuse)
    args = wire_get(inst, :args)
    if args != nil
      i = 0
      while i < wire_sequence_size(args)
        escaped[wire_sequence_get(args, i)] = true
        i += 1
    # The ptr1 kinds carry their single payload in :arg, not :args.
    if wire_get(inst, :arg) != nil
      escaped[wire_get(inst, :arg)] = true
    return nil

  # Packed AST node constructor: every field value is frozen into the AST
  # arena and stored in the node (w_ast_freeze_if_array keeps the array it
  # is handed), so the node retains all of them.
  if op == :slab_alloc_init
    fields = wire_get(inst, :fields)
    if fields != nil
      i = 0
      while i < wire_sequence_size(fields)
        escaped[wire_sequence_get(fields, i)] = true
        i += 1
    return nil

  # Raw stores whose slot may hold a boxed WValue (w64[] typed arrays,
  # `- data` inline element slots).
  if op in (:typed_array_store_u64 :view_store_inline_elem)
    escaped[wire_get(inst, :value)] = true
    return nil

  # Catch-all: any other op carrying an argument list or receiver is a call
  # this pass does not know by name (typed raw-ABI ccall_rawargs targets are
  # emitted through wire_make_dynamic_N with a return-type-specific kind).
  # The callee may retain anything — w_wire_function_record_new keeps the
  # `params` array it is handed — so every operand escapes. escape.w
  # applies the same rule when it summarizes the callee.
  catch_args = wire_get(inst, :args)
  if catch_args != nil
    i = 0
    while i < wire_sequence_size(catch_args)
      escaped[wire_sequence_get(catch_args, i)] = true
      i += 1
  catch_recv = wire_get(inst, :receiver)
  if catch_recv != nil
    escaped[catch_recv] = true

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
  # temp → class name for :load_class results; construct_producer_class
  # needs to know that a construct's receiver IS the guarded class.
  class_temps = {}

  # Walk blocks in order (sufficient for monotonic analysis)
  bi = 0
  while bi < blocks.size()
    blk = blocks[bi]
    instrs = blk[:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      op = wire_kind(inst)

      if op == :load_class && wire_get(inst, :temp) != nil
        class_temps[wire_get(inst, :temp)] = wire_get(inst, :class_name)

      # Scope tracking
      if op == :scope_push
        scope_stack.push({id: wire_get(inst, :id), temps: []})
      elsif op == :scope_pop
        if scope_stack.size() > 0
          scope = scope_stack.pop()
          scope_locals[scope[:id]] = scope[:temps]
      elsif op == :phi_ssa
        # Treat the phi and every incoming value as one escaping group.  An
        # incoming producer may only dominate one branch, so freeing it at a
        # scope_pop would violate SSA dominance.  Marking the result here too
        # makes this independent of phi ordering, including loop backedges.
        incoming = wire_get(inst, :incoming)
        if incoming != nil
          escaped[wire_get(inst, :temp)] = true
          pi = 0
          while pi < wire_sequence_size(incoming)
            v = wire_sequence_get(incoming, pi)
            escaped[v] = true
            pi += 2
      else
        # Value producers: record and track in current scope
        if wire_get(inst, :temp) != nil
          producer_class = nil
          is_producer = is_heap_producer(inst)
          if !is_producer && op == :call_method_i64
            producer_class = construct_producer_class(inst, mod, class_temps)
            is_producer = producer_class != nil
          if is_producer
            producers[wire_get(inst, :temp)] = {op: op, block: bi, class: producer_class}
            if scope_stack.size() > 0
              scope_stack[scope_stack.size() - 1][:temps].push(wire_get(inst, :temp))
            elsif bi == 0
              # Function-body scope: a producer in the ENTRY block at scope
              # depth 0 has no enclosing if/while/with scope_pop to free it,
              # so straight-line helpers (e.g. `s = a + b.to_s(); use(s)`)
              # leaked every heap string/bigint they built. The entry block
              # dominates every ret, so such a value is defined on all paths;
              # if it's also non-escaped it's dead by the return and safe to
              # free there. Producers in NON-entry scope-0 blocks are skipped
              # (conservative — they may not dominate a given ret).
              func_scope_temps.push(wire_get(inst, :temp))
          # Loads from memory/globals: conservatively escaped
          if op in (:load_i64 :load_global :load_class :load_ptr)
            escaped[wire_get(inst, :temp)] = true
        # Mark escapes for this instruction
        mark_escapes(inst, escaped, mod, producers)

      ii += 1
    bi += 1

  func[:ownership] = {escaped: escaped, producers: producers, scope_locals: scope_locals, func_scope: func_scope_temps}

# Entry point: analyze all functions in the module.
-> ownership_pass(mod)
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    if func[:blocks].size() > 0 && func[:incremental_core_frozen] != true
      ownership_analyze(func, mod)
    fi += 1

# Ownership is purely per-function: it reads immutable instructions and writes
# one summary back to the same function record. Keep the parent on useful work
# while N-1 short-lived workers claim the rest. compile-batch already uses
# process workers, so nesting this team there would only oversubscribe the host.
-> ownership_parallel_job_count(mod)
  if env("TUNGSTEN_PARALLEL_MIDEND") == "0" || env("TUNGSTEN_PARALLEL_OWNERSHIP") == "0" || env("TUNGSTEN_BATCH_WORKER_PROCESS") == "1" || runtime_identity() != "compiled-runtime" || mod[:functions].size() < 512
    return 1
  requested = 0
  configured = env("TUNGSTEN_MIDEND_JOBS")
  if configured != nil && configured != "" && configured != "auto"
    requested = configured.to_i()
  if requested < 1
    requested = ccall("w_cpu_count")
    if requested > 8
      requested = 8
  if requested < 1
    requested = 1
  if requested > mod[:functions].size()
    requested = mod[:functions].size()
  if requested > 32
    requested = 32
  requested

-> ownership_parallel_worker(state)
  functions = state[:functions]
  index = ccall("w_atomic_add", state[:cursor], u0xFFFA000000000001)
  while index < functions.size()
    func = functions[index]
    if func[:blocks].size() > 0 && func[:incremental_core_frozen] != true
      ownership_analyze(func, state[:mod])
    index = ccall("w_atomic_add", state[:cursor], u0xFFFA000000000001)
  true

-> ownership_pass_parallel(mod, jobs)
  state = {
    functions: mod[:functions],
    mod: mod,
    cursor: ccall("w_atomic_new", u0xFFFA000000000000)
  }
  workers = []
  worker = 1
  while worker < jobs
    workers.push(Thread.new ->
      ownership_parallel_worker(state))
    worker += 1
  ownership_parallel_worker(state)
  worker = 0
  while worker < workers.size()
    ccall("w_thread_join_release", workers[worker])
    worker += 1
  nil

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
      if wire_kind(inst) == :scope_pop
        # Free non-escaped heap values from this scope
        sid = wire_get(inst, :id)
        locals = scope_locals[sid]
        if locals != nil
          li = 0
          while li < locals.size()
            temp = locals[li]
            if escaped[temp] != true && producers[temp] != nil
              new_instrs.push(wire_make_free_value(temp))
            li += 1
      # Function-body scope: free non-escaped entry-block producers right
      # before each return. The entry block dominates every ret, so these
      # values are defined on all paths and (being non-escaped) dead here.
      # Only one ret runs per call, so freeing before each is not a double
      # free at runtime.
      if wire_kind(inst) in (:ret_i64 :ret_i32 :ret_void) && func_scope != nil
        fi = 0
        while fi < func_scope.size()
          temp = func_scope[fi]
          if escaped[temp] != true && producers[temp] != nil
            new_instrs.push(wire_make_free_value(temp))
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
    if func[:blocks].size() > 0 && func[:incremental_core_frozen] != true
      insert_frees(func)
    fi += 1
