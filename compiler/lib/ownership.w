# Ownership analysis — classify each value as ESCAPED or locally owned.
# Runs after SSA conversion, before emit. Walks SSA'd WIRE IR in RPO.

use runtime_types
use wire
use cfg

# Does block `a` dominate block `b`? `idom` is compute_dominators' array:
# idom[entry] = entry and -1 marks an unreachable block.
-> block_dominates?(idom, a, b)
  if a == b || a == 0
    return true
  cur = b
  while cur != 0 && cur != -1
    cur = idom[cur]
    if cur == a
      return true
  false

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
  # Dominators are built lazily, only when a scope holds a producer from a
  # block other than the block of its scope_pop.
  idom = nil
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
          # A producer born in a block that does not dominate this pop — the
          # right operand of a short-circuit `&&`/`||`, for instance, which
          # lowers into its own block — is defined on only some paths here.
          # Releasing it at the pop broke SSA dominance ("Instruction does not
          # dominate all uses" from LLVM). Keep only producers whose block
          # dominates the pop's block; the rest stay with the collector.
          kept = []
          ti = 0
          while ti < scope[:temps].size()
            temp = scope[:temps][ti]
            pb = producers[temp][:block]
            if pb == bi
              kept.push(temp)
            else
              if idom == nil
                idom = compute_dominators(build_cfg(func))
              if block_dominates?(idom, pb, bi)
                kept.push(temp)
            ti += 1
          scope_locals[scope[:id]] = kept
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
            producers[wire_get(inst, :temp)] = {op: op, block: bi, class: producer_class, instruction: inst}
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

# Choose the matching release for a dead producer. A source instance whose
# guarded constructor arm is known to run can return its shell to the bounded
# object pool. Marking the allocation arm here keeps the optimization tied to
# the same escape proof that inserts the release; `TUNGSTEN_FREE=0` therefore
# retains ordinary allocation as well as omitting release calls.
-> release_dead_producer(temp, producer)
  if producer[:class] != nil && producer[:instruction] != nil
    wire_set(producer[:instruction], :construct_recycle, true)
    return wire_make_recycle_object(temp)
  wire_make_free_value(temp)

# Insert releases at scope_pop for non-escaped heap-produced values.
# Modifies WIRE blocks in place before scope_pop and each dominated return.
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
              new_instrs.push(release_dead_producer(temp, producers[temp]))
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
            new_instrs.push(release_dead_producer(temp, producers[temp]))
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
      if env("TUNGSTEN_LOOP_RELEASE") != "0"
        ignored = loop_carried_releases(func)
    fi += 1

# ---------------------------------------------------------------------------
# Loop-carried integer releases.
#
# The pass above frees only known constructors, and SSA conversion (cfg.w)
# deliberately leaves every variable that needs a merge phi in its memory
# slot, so a loop that carries an integer
#
#   while ...
#     x = (x * x) % m
#
# kept every iteration's BigInt (and the x * x intermediate) until the process
# exited: 40 KB per iteration at 100,000 bits, or a few hundred GB for one
# long modular-squaring loop.
#
# For a variable slot V and a natural loop with one back edge (the latch ends
# in a plain branch to the header, and the header has one predecessor outside
# the loop), V qualifies when:
#   - V is only loaded and stored (never address-taken or passed anywhere);
#   - the loop body stores V exactly once, in a block that dominates the
#     latch, and the stored value `next` is an integer-arithmetic helper result
#     computed in the loop;
#   - S, the set holding every value loaded from V in the loop plus `next`,
#     closed under results of arithmetic helpers that read a member, is read
#     only inside the loop and only by those helpers, by non-retaining
#     consumers (comparisons, ...), or by the one store of `next` into V.
#     Any other use - a store elsewhere, a method call, a return - and V is
#     left alone.
# The arithmetic helpers (`+ - * % / << >>` on WValues) never retain an
# operand: they return a fresh value, an inline integer, or the operand with
# its BigInt shared count raised.  The pass loads V's entry value at the end
# of the preheader (`init`) and V's old value right before the store (`prev`),
# then at the end of the latch calls w_value_release_loop (runtime.c), which
# releases prev and up to two intermediates of S whose definitions dominate
# the latch.  It skips the release when prev is init (the first iteration,
# where init may be borrowed) or when any of the values is not an integer at
# run time (a Rational or Complex result could hold an operand).
# TUNGSTEN_LOOP_RELEASE=0 disables the pass.
# ---------------------------------------------------------------------------

-> loop_release_arith?(name)
  name in ("__w_add_fast" "__w_sub_fast" "__w_mul_fast" "__w_mod_fast" "__w_div_fast" "__w_shl_fast" "__w_shr_fast" "w_add" "w_sub" "w_mul" "w_mod" "w_div" "w_bit_shl" "w_bit_shr")

# Temp-like operand strings an instruction reads (its own :temp excluded), or
# nil when a field holds a structure this scan does not understand.
-> loop_release_operands(inst)
  out = []
  if ccall_nobox("w_is_wire_extern", inst) == 1
    count = wire_field_count(inst)
    fi = 0
    while fi < count
      sym = wire_field_symbol_at(inst, fi)
      value = wire_field_value_at(inst, fi)
      if sym != :temp && value != nil
        if wire_sequence_field?(sym)
          si = 0
          while si < wire_sequence_size(value)
            item = wire_sequence_get(value, si)
            if type(item) == "String"
              out.push(item)
            elsif type(item) == "Hash"
              if type(item[:value]) == "String"
                out.push(item[:value])
            elsif type(item) == "Array"
              return nil
            si += 1
        elsif type(value) == "String"
          out.push(value)
        elsif type(value) == "Array" || type(value) == "Hash"
          return nil
      fi += 1
    return out
  if type(inst) != "Hash"
    return nil
  keys = inst.keys()
  ki = 0
  while ki < keys.size()
    key = keys[ki]
    value = inst[key]
    if key != :temp && key != :op && value != nil
      if type(value) == "String"
        out.push(value)
      elsif type(value) == "Array"
        ai = 0
        while ai < value.size()
          item = value[ai]
          if type(item) == "String"
            out.push(item)
          elsif type(item) == "Array" || type(item) == "Hash"
            return nil
          ai += 1
      elsif type(value) == "Hash"
        return nil
    ki += 1
  out

# Blocks of the natural loop of the back edge tail -> header.
-> loop_release_body(cfg, header, tail)
  body = {}
  body[header] = true
  stack = [tail]
  while stack.size() > 0
    b = stack.pop()
    if body[b] != true
      body[b] = true
      preds = cfg[:preds][b]
      pi = 0
      while pi < preds.size()
        stack.push(preds[pi])
        pi += 1
  body

-> loop_carried_releases(func)
  blocks = func[:blocks]
  slots = func[:var_slots]
  return 0 if slots == nil || blocks.size() < 2 || has_setjmp(func)
  slot_ptr = {}
  snames = slots.keys()
  sn = 0
  while sn < snames.size()
    slot_ptr[slots[snames[sn]]] = true
    sn += 1
  return 0 if snames.size() == 0

  # Cheap pre-filter, linear and without a CFG: some arithmetic-helper result
  # must be stored into a slot.  Most functions stop here.  (A store that
  # precedes its definition in block order is missed, which only skips the
  # optimization.)
  arith_temps = {}
  candidate = false
  bi = 0
  while bi < blocks.size() && !candidate
    instrs = blocks[bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      k = wire_kind(inst)
      if k == :call_direct_i64
        if loop_release_arith?(wire_get(inst, :name)) && wire_get(inst, :temp) != nil
          arith_temps[wire_get(inst, :temp)] = true
      elsif k == :store_i64
        if slot_ptr[wire_get(inst, :ptr)] == true && arith_temps[wire_get(inst, :value)] == true
          candidate = true
          break
      ii += 1
    bi += 1
  return 0 if !candidate

  cfg = build_cfg(func)
  idom = compute_dominators(cfg)
  # Back edges: retreating edges in reverse postorder whose target dominates
  # the source.  Only retreating edges pay for a dominator walk; the generic
  # find_loop_back_edges walks one for every edge, which took minutes on the
  # largest functions of the bits.
  rpo = compute_rpo(cfg)
  rpo_index = rpo[:index]
  edges = []
  bi = 0
  while bi < blocks.size()
    bri = rpo_index[bi]
    if bri != nil
      succs = cfg[:succs][bi]
      si = 0
      while si < succs.size()
        target = succs[si]
        tri = rpo_index[target]
        if tri != nil && tri <= bri && block_dominates?(idom, target, bi)
          edges.push({header: target, tail: bi})
        si += 1
    bi += 1
  return 0 if edges.size() == 0
  back_count = {}
  ei = 0
  while ei < edges.size()
    h = edges[ei][:header]
    back_count[h] = back_count[h] == nil ? 1 : back_count[h] + 1
    ei += 1

  # One scan: temp definitions, operand uses, slot loads/stores, and slots
  # referenced any other way (those are never candidates).
  defs = {}
  uses = {}
  opaque = {}
  loads = {}
  stores = {}
  bad_slot = {}
  bi = 0
  while bi < blocks.size()
    instrs = blocks[bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      k = wire_kind(inst)
      t = wire_get(inst, :temp)
      if t != nil
        defs[t] = [bi, ii]
      slot_access = nil
      if k in (:load_i64 :store_i64)
        sp = wire_get(inst, :ptr)
        if sp != nil && slot_ptr[sp] == true
          slot_access = sp
          if k == :load_i64
            if loads[sp] == nil
              loads[sp] = []
            loads[sp].push([bi, ii, t])
          else
            if stores[sp] == nil
              stores[sp] = []
            stores[sp].push([bi, ii, wire_get(inst, :value)])
      refs = loop_release_operands(inst)
      if refs == nil
        opaque[bi] = true
      else
        ri = 0
        while ri < refs.size()
          r = refs[ri]
          if slot_ptr[r] == true && r != slot_access
            bad_slot[r] = true
          if uses[r] == nil
            uses[r] = []
          uses[r].push([bi, ii])
          ri += 1
      ii += 1
    bi += 1

  dbg = env("TUNGSTEN_LOOP_RELEASE_DEBUG") == "1"
  inserted = 0
  before_inst = {}
  before_term = {}
  ei = 0
  while ei < edges.size()
    h = edges[ei][:header]
    l = edges[ei][:tail]
    ei += 1
    next if back_count[h] != 1
    latch_instrs = blocks[l][:instructions]
    next if latch_instrs.size() == 0
    term = latch_instrs[latch_instrs.size() - 1]
    next if wire_kind(term) != :br || wire_get(term, :label) != blocks[h][:label]
    body = loop_release_body(cfg, h, l)
    outside = []
    hp = cfg[:preds][h]
    hpi = 0
    while hpi < hp.size()
      outside.push(hp[hpi]) if body[hp[hpi]] != true
      hpi += 1
    next if outside.size() != 1
    pre = outside[0]
    clean = true
    bkeys = body.keys()
    bk = 0
    while bk < bkeys.size()
      clean = false if opaque[bkeys[bk]] == true
      bk += 1
    next if !clean

    pkeys = stores.keys()
    pk = 0
    while pk < pkeys.size()
      ptr = pkeys[pk]
      pk += 1
      next if bad_slot[ptr] == true
      body_store = nil
      store_count = 0
      sl = stores[ptr]
      sj = 0
      while sj < sl.size()
        if body[sl[sj][0]] == true
          store_count += 1
          body_store = sl[sj]
        sj += 1
      next if store_count != 1
      sb = body_store[0]
      nxt = body_store[2]
      next if nxt == nil || !block_dominates?(idom, sb, l)
      def_at = defs[nxt]
      next if def_at == nil || body[def_at[0]] != true
      def_inst = blocks[def_at[0]][:instructions][def_at[1]]
      next if wire_kind(def_inst) != :call_direct_i64 || !loop_release_arith?(wire_get(def_inst, :name))

      members = {}
      work = [nxt]
      members[nxt] = true
      ll = loads[ptr]
      lj = 0
      while ll != nil && lj < ll.size()
        if body[ll[lj][0]] == true && ll[lj][2] != nil && members[ll[lj][2]] != true
          members[ll[lj][2]] = true
          work.push(ll[lj][2])
        lj += 1
      inter = []
      ok = true
      while work.size() > 0 && ok
        v = work.pop()
        vuses = uses[v]
        if vuses != nil
          ui = 0
          while ui < vuses.size() && ok
            ub = vuses[ui][0]
            uinst = blocks[ub][:instructions][vuses[ui][1]]
            ui += 1
            if body[ub] != true
              ok = false
              next
            uk = wire_kind(uinst)
            if uk == :store_i64
              ok = false unless wire_get(uinst, :ptr) == ptr && wire_get(uinst, :value) == nxt && v == nxt
            elsif uk == :call_direct_i64
              uname = wire_get(uinst, :name)
              if loop_release_arith?(uname)
                r = wire_get(uinst, :temp)
                if r == nil
                  ok = false
                elsif members[r] != true
                  members[r] = true
                  work.push(r)
                  if r != nxt && block_dominates?(idom, ub, l)
                    inter.push(r)
              elsif !is_nonretaining_consumer(uname)
                ok = false
            else
              ok = false
      if dbg
        ignored = ccall("w_eputs", "loop-release " + func[:name].to_s() + " slot=" + ptr.to_s() + " header=" + blocks[h][:label].to_s() + " ok=" + ok.to_s() + " members=" + members.keys().size().to_s() + " inter=" + inter.size().to_s())
      next if !ok

      init_tmp = next_temp(func)
      prev_tmp = next_temp(func)
      extra = inter.size()
      extra = 2 if extra > 2
      t1 = extra >= 1 ? inter[0] : "0"
      t2 = extra >= 2 ? inter[1] : "0"
      if before_term[pre] == nil
        before_term[pre] = []
      before_term[pre].push(wire_make_load_i64(ptr, init_tmp))
      skey = sb.to_s() + ":" + body_store[1].to_s()
      if before_inst[skey] == nil
        before_inst[skey] = []
      before_inst[skey].push(wire_make_load_i64(ptr, prev_tmp))
      if before_term[l] == nil
        before_term[l] = []
      before_term[l].push(wire_make_call_direct_void([extra.to_s(), init_tmp, prev_tmp, nxt, t1, t2], "w_value_release_loop"))
      inserted += 1

  return 0 if inserted == 0
  bi = 0
  while bi < blocks.size()
    instrs = blocks[bi][:instructions]
    terms = before_term[bi]
    touched = terms != nil
    ii = 0
    while ii < instrs.size() && !touched
      touched = true if before_inst[bi.to_s() + ":" + ii.to_s()] != nil
      ii += 1
    if touched
      rebuilt = []
      ii = 0
      while ii < instrs.size()
        extra_before = before_inst[bi.to_s() + ":" + ii.to_s()]
        if extra_before != nil
          ei2 = 0
          while ei2 < extra_before.size()
            rebuilt.push(extra_before[ei2])
            ei2 += 1
        if terms != nil && ii == instrs.size() - 1
          ti = 0
          while ti < terms.size()
            rebuilt.push(terms[ti])
            ti += 1
        rebuilt.push(instrs[ii])
        ii += 1
      blocks[bi][:instructions] = rebuilt
    bi += 1
  inserted
