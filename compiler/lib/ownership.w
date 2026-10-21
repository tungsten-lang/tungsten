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
    # w_array_new_empty backs `[]`: a fresh owned WArray (or a recycled one
    # reset to fresh), freed like w_array_new.
    return name in ("w_string" "w_hash_new" "w_array_new" "w_array_new_empty" "w_array_new_uninit_sized" "w_strbuf_new" "w_str_concat" "w_str_concat_free_rhs" "w_str_concat_free_lhs" "w_str_concat_own" "w_str_concat_i64" "w_i64_concat_str" "w_str_concat_int_wv" "w_int_wv_concat_str" "w_int_to_s" "w_string_repeat")
  if op == :load_i64 || op == :call_method_i64 || op == :string_i64 || op == :symbol_i64 || op == :load_global || op == :load_class || op == :icmp_i64 || op == :add_i64 || op == :sub_i64 || op == :truthy_inline
    return false
  # string_i64 creates interned slab strings — NOT freeable
  # class_new creates classes that live forever — NOT freeable
  if op == :closure_new
    return true
  if op in (:const_float :const_decimal :const_currency :const_quantity :const_duration_ns :const_duration_months_ms :const_uuid)
    return true
  false

# Container writes: the container keeps the stored key/value but not itself,
# and the result (nil or the stored value) never aliases the container.
# Index of the first argument the container retains, or nil.
-> container_store_first_kept(name)
  if name == "w_array_push"
    return 1
  if name == "w_hash_set"
    return 1
  if name == "w_array_set"
    return 2
  nil

# A direct call to a source function that returns a fresh heap value nothing
# else holds (fresh_heap_returns), so the caller owns the result.
-> fresh_heap_call?(inst, mod)
  if mod == nil || wire_kind(inst) != :call_direct_i64
    return false
  fresh = mod[:fresh_heap_fns]
  fresh != nil && fresh[wire_get(inst, :name)] == true

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
# Element reads (w_array_get and its typed fast forms) return an element or
# nil, never the array or a view of it (views come only from slice_view).
-> is_nonretaining_consumer(name)
  name in ("w_array_get" "w_array_get_i64" "w_array_idx_i64" "__w_array_get_i64_fast" "__w_array_idx_i64_fast" "w_string_byte_length" "w_hash_get" "w_eq" "w_neq" "w_eq_lit" "w_neq_lit" "__w_streq_fast" "__w_streq2_fast" "__w_eq_fast" "__w_neq_fast" "__w_eq_lit_fast" "__w_neq_lit_fast" "__w_lt_fast" "__w_gt_fast" "__w_lte_fast" "__w_gte_fast" "w_string_index" "w_string_rindex" "w_string_count" "w_string_repeat" "__w_string_byte_length_fast" "w_wire_sequence_from_array")

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
# A fresh core Array/String/Hash argument (a known producer) is judged by the
# summary for its kind (escape.w kind_stored_escs: stored assuming that kind,
# so read-only core methods on it keep nothing) plus ret_escs (returned).
-> mark_args_by_summary(args, first, summary, escaped, producers = nil, mod = nil)
  if args == nil
    return nil
  escs = summary[:escs]
  kinds = summary[:kind_stored_escs]
  rets = summary[:ret_escs]
  i = 0
  while i < wire_sequence_size(args)
    pi = first + i
    arg = wire_sequence_get(args, i)
    kind = nil
    if producers != nil && producers[arg] != nil && kinds != nil && rets != nil
      kind = heap_producer_kind(producers[arg][:instruction], mod)
    if kind != nil
      ks = kinds[kind]
      if ks == nil || pi >= ks.size() || ks[pi] == true || pi >= rets.size() || rets[pi] == true
        escaped[arg] = true
    elsif escs == nil || pi >= escs.size() || escs[pi] == true
      escaped[arg] = true
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
# :array / :string / :hash for a known constructor's result -- or a fresh
# heap function's, whose kind fresh_heap_returns records -- else nil.
-> heap_producer_kind(inst, mod = nil)
  if inst == nil || wire_kind(inst) != :call_direct_i64
    return nil
  name = wire_get(inst, :name)
  if mod != nil && mod[:fresh_heap_kinds] != nil && mod[:fresh_heap_kinds][name] != nil
    return mod[:fresh_heap_kinds][name]
  if name in ("w_array_new" "w_array_new_empty" "w_array_new_uninit_sized")
    return :array
  if name in ("w_string" "w_str_concat" "w_str_concat_free_rhs" "w_str_concat_free_lhs" "w_str_concat_own" "w_int_to_s" "w_string_repeat")
    return :string
  if name == "w_hash_new"
    return :hash
  nil

-> mark_escapes(inst, escaped, mod, producers, names = nil)
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
      mark_args_by_summary(wire_get(inst, :args), 0, summary, escaped, producers, mod)
      return nil
    if op == :call_direct_i64
      kept = container_store_first_kept(wire_get(inst, :name))
      if kept != nil
        args = wire_get(inst, :args)
        i = kept
        while args != nil && i < wire_sequence_size(args)
          escaped[wire_sequence_get(args, i)] = true
          i += 1
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
    # A read-only core method on a fresh Array/String/Hash keeps nothing of
    # the receiver (the arguments still escape below).
    reader = false
    if receiver != nil && producers != nil && producers[receiver] != nil && names != nil && mod != nil && mod[:container_contract_intact] == true
      kind = heap_producer_kind(producers[receiver][:instruction], mod)
      mv = wire_get(inst, :method_name_val)
      mname = names[mv]
      if mname == nil && mod[:string_texts] != nil && type(mv) == "String" && mv.starts_with?("u0x")
        mname = mod[:string_texts][mv]
      reader = kind != nil && mname != nil && container_reader_method?(kind, mname)
      if reader
        ai = 0
        args = wire_get(inst, :args)
        while args != nil && ai < wire_sequence_size(args)
          reader = false if wire_sequence_get(args, ai) == receiver
          ai += 1
    # Receiver and all args escape (dynamic dispatch)
    if receiver != nil && !reader
      escaped[receiver] = true
    args = wire_get(inst, :args)
    if args != nil
      i = 0
      while i < wire_sequence_size(args)
        escaped[wire_sequence_get(args, i)] = true
        i += 1
    return nil

  if op == :store_i64
    # Non-promoted var store: value escapes (can't track through memory)
    escaped[wire_get(inst, :value)] = true
    return nil

  if op == :load_i64 || op == :br || op == :cond_br || op == :ret_void || op == :string_i64 || op == :symbol_i64 || op == :call_loc_set_col || op == :load_global || op == :load_class || op == :icmp_i64 || op == :add_i64 || op == :sub_i64 || op == :truthy_inline || op == :nanbox_int || op == :nanunbox_int || op == :nanbox_bool
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
    wo = mod == nil ? nil : mod[:write_only_globals]
    if wo == nil || wo[wire_get(inst, :name)] != true
      escaped[wire_get(inst, :value)] = true
    return nil

  if op == :store_ptr
    escaped[wire_get(inst, :value)] = true
    return nil

  if op == :closure_new
    if wire_get(inst, :captures_ptr) != nil
      escaped[wire_get(inst, :captures_ptr)] = true
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

  if op in (:load_i64 :alloca_i64 :nanbox_int :nanunbox_int :nanbox_bool :truthy_inline :icmp_i64 :add_i64 :sub_i64 :mul_i64 :sdiv_i64 :srem_i64 :and_i64 :or_i64 :xor_i64 :shl_i64 :ashr_i64 :lshr_i64 :br :cond_br :string_i64 :symbol_i64 :load_global :load_class :load_ptr :and_i1 :or_i1 :not_i1 :zext_i1_i64)
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
  # method-name constant temp -> text, for mark_escapes (immediate u0x... names
  # are looked up directly in mod[:string_texts]).
  names = {}
  texts = mod == nil ? nil : mod[:string_texts]

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
      if op in (:string_i64 :symbol_i64) && wire_get(inst, :temp) != nil && texts != nil
        names[wire_get(inst, :temp)] = texts[wire_get(inst, :string_id)]

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
          is_producer = is_heap_producer(inst) || fresh_heap_call?(inst, mod)
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
        mark_escapes(inst, escaped, mod, producers, names)

      ii += 1
    bi += 1

  func[:ownership] = {escaped: escaped, producers: producers, scope_locals: scope_locals, func_scope: func_scope_temps}

# Entry point: analyze all functions in the module.
-> ownership_pass(mod)
  if mod[:string_texts] == nil
    mod[:string_texts] = int_temp_string_texts(mod)
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
  if mod[:string_texts] == nil
    mod[:string_texts] = int_temp_string_texts(mod)
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
  if producers.size() == 0
    return nil
  scope_locals = own[:scope_locals]
  func_scope = own[:func_scope]
  has_freeable_func_scope = false
  if func_scope != nil
    fi = 0
    while fi < func_scope.size()
      temp = func_scope[fi]
      if escaped[temp] != true && producers[temp] != nil
        has_freeable_func_scope = true
        break
      fi += 1
  if !has_freeable_func_scope && scope_locals.size() == 0
    return nil

  blocks = func[:blocks]
  bi = 0
  while bi < blocks.size()
    instrs = blocks[bi][:instructions]
    new_instrs = nil
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      op = wire_kind(inst)
      if op == :scope_pop
        # Free non-escaped heap values from this scope
        sid = wire_get(inst, :id)
        locals = scope_locals[sid]
        if locals != nil
          li = 0
          while li < locals.size()
            temp = locals[li]
            if escaped[temp] != true && producers[temp] != nil
              if new_instrs == nil
                new_instrs = []
                ci = 0
                while ci < ii
                  new_instrs.push(instrs[ci])
                  ci += 1
              new_instrs.push(release_dead_producer(temp, producers[temp]))
            li += 1
      # Function-body scope: free non-escaped entry-block producers right
      # before each return. The entry block dominates every ret, so these
      # values are defined on all paths and (being non-escaped) dead here.
      # Only one ret runs per call, so freeing before each is not a double
      # free at runtime.
      elsif has_freeable_func_scope && (op == :ret_i64 || op == :ret_i32 || op == :ret_void)
        fi = 0
        while fi < func_scope.size()
          temp = func_scope[fi]
          if escaped[temp] != true && producers[temp] != nil
            if new_instrs == nil
              new_instrs = []
              ci = 0
              while ci < ii
                new_instrs.push(instrs[ci])
                ci += 1
            new_instrs.push(release_dead_producer(temp, producers[temp]))
          fi += 1
      if new_instrs != nil
        new_instrs.push(inst)
      ii += 1
    if new_instrs != nil
      blocks[bi][:instructions] = new_instrs
    bi += 1

# Entry point for free insertion across all functions.
-> free_insertion_pass(mod)
  int_temps = nil
  strings = nil
  fresh = nil
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    if func[:blocks].size() > 0 && func[:incremental_core_frozen] != true
      insert_frees(func)
      if env("TUNGSTEN_LOOP_RELEASE") != "0"
        ignored = loop_carried_releases(func)
      if int_temps == nil
        int_temps = env("TUNGSTEN_INT_TEMP_RELEASE") != "0" && mod[:integer_contract_intact] == true
        if int_temps
          strings = mod[:string_texts]
          if strings == nil
            strings = int_temp_string_texts(mod)
          mod[:method_table] = module_method_table(mod, strings)
          fresh = int_fresh_returns(mod)
      if int_temps && env("TUNGSTEN_SLOT_RELEASE") != "0"
        ignored = owned_slot_releases(func, mod, fresh, strings)
      if int_temps
        ignored = int_temp_releases(func, strings, fresh, mod)
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
    op = wire_kind(inst)
    if op == :call_direct_i64 || op == :call_direct_void || op == :call_direct_ptr || op == :call_direct_i128
      args = wire_get(inst, :args)
      if args != nil
        si = 0
        while si < wire_sequence_size(args)
          item = wire_sequence_get(args, si)
          if type(item) == "String" && item.size() > 0 && item.byte_at(0) == 37
            out.push(item)
          si += 1
      return out
    if op == :load_i64 || op == :load_double || op == :load_float || op == :load_i128
      ptr = wire_get(inst, :ptr)
      if type(ptr) == "String" && ptr.size() > 0 && ptr.byte_at(0) == 37
        out.push(ptr)
      return out
    if op == :store_i64 || op == :store_double || op == :store_float || op == :store_i128
      ptr = wire_get(inst, :ptr)
      if type(ptr) == "String" && ptr.size() > 0 && ptr.byte_at(0) == 37
        out.push(ptr)
      val = wire_get(inst, :value)
      if type(val) == "String" && val.size() > 0 && val.byte_at(0) == 37
        out.push(val)
      return out
    if op == :br || op == :ret_void || op == :string_i64 || op == :symbol_i64 || op == :call_loc_set_col || op == :load_class || op == :load_global || op == :scope_push || op == :scope_pop || op == :cleanup_pop
      return out
    if op == :cond_br
      cond = wire_get(inst, :cond)
      if type(cond) == "String" && cond.size() > 0 && cond.byte_at(0) == 37
        out.push(cond)
      return out
    if op == :call_method_i64
      rec = wire_get(inst, :receiver)
      if type(rec) == "String" && rec.size() > 0 && rec.byte_at(0) == 37
        out.push(rec)
      mv = wire_get(inst, :method_name_val)
      if type(mv) == "String" && mv.size() > 0 && mv.byte_at(0) == 37
        out.push(mv)
      tav = wire_get(inst, :temp_args_val)
      if type(tav) == "String" && tav.size() > 0 && tav.byte_at(0) == 37
        out.push(tav)
      args = wire_get(inst, :args)
      if args != nil
        si = 0
        while si < wire_sequence_size(args)
          item = wire_sequence_get(args, si)
          if type(item) == "String" && item.size() > 0 && item.byte_at(0) == 37
            out.push(item)
          si += 1
      return out
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
              if item.size() > 0 && item.byte_at(0) == 37
                out.push(item)
            elsif type(item) == "Hash"
              iv = item[:value]
              if type(iv) == "String" && iv.size() > 0 && iv.byte_at(0) == 37
                out.push(iv)
            elsif type(item) == "Array"
              return nil
            si += 1
        elsif type(value) == "String"
          if value.size() > 0 && value.byte_at(0) == 37
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
  return 0 if slots == nil || slots.size() == 0 || blocks.size() < 2
  slot_ptr = {}
  snames = slots.keys()
  sn = 0
  while sn < snames.size()
    slot_ptr[slots[snames[sn]]] = true
    sn += 1

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
      if k == :setjmp
        return 0
      if k == :call_direct_i64
        if loop_release_arith?(wire_get(inst, :name)) && wire_get(inst, :temp) != nil
          arith_temps[wire_get(inst, :temp)] = true
      elsif k == :store_i64
        if slot_ptr[wire_get(inst, :ptr)] == true && arith_temps[wire_get(inst, :value)] == true
          candidate = true
          break
      ii += 1
    bi += 1
  return 0 if !candidate || has_setjmp(func)

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

# ---------------------------------------------------------------------------
# Dead integer temporaries.
#
# An integer-arithmetic result that is only read dies at its last read, but
# nothing released it: `y = x * x + 1` dropped x * x, `if a * 3 < a * 2`
# dropped both products, `(x * x).bit_length` dropped the square.  Each
# stayed allocated until the process exited -- about 10 GB/s in a sweep that
# lived on such expressions.
#
# For a temp t defined by an arithmetic helper whose every use sits in t's
# own block and only reads t -- another arithmetic helper, a comparison, a
# truthiness test, to_s, or a known read-only Integer method on t -- the pass
# calls __w_int_temp_release right after the last use (right after the
# definition when t is never read).  The runtime releases t only when it is
# a BigInt and every witness is an integer: the operands t was computed from
# and the other operands of the arithmetic helpers that read it.  With
# integer operands the helpers run core integer arithmetic, which never
# retains an operand (see loop_carried_releases above), so t is dead; any
# other kind skips the release.  Uses by anything else -- a store, a phi, a
# return, a call that might keep t -- leave t alone, which also keeps clear
# of the releases the passes above insert (w_value_release_loop's operands
# are uses of exactly that kind).  A release that cannot run because a read
# raised only leaks.  Functions with setjmp, or with an instruction whose
# operands the scan cannot list, are skipped.
#
# Calls extend both ends.  t may be an argument of a direct call to a source
# function whose escape summary says it never stores that parameter when it
# is an Integer (escape.w int_stored_escs); the call's result is then a
# witness too, since a returned integer cannot contain t, and the runtime
# never releases t when a witness is t itself (an unmarked returned
# parameter).  And t may be the result of a call to a function whose every
# return is a fresh integer (int_fresh_returns below), so `sq(x)` dropped or
# only compared is released like `x * x`.
# TUNGSTEN_INT_TEMP_RELEASE=0 disables the pass.
# ---------------------------------------------------------------------------

# The arithmetic helpers plus the runtime's BigInt entries that core reaches
# through ccall (BigInt#bit_length's shift probes, ...): the same core
# arithmetic, so the same fresh-or-marked contract.
-> int_temp_arith?(name)
  loop_release_arith?(name) || name in ("__w_band_fast" "__w_bor_fast" "__w_bxor_fast" "w_bit_and" "w_bit_or" "w_bit_xor" "w_bigint_shr" "w_bigint_shl" "w_bigint_add" "w_bigint_sub" "w_bigint_div" "w_bigint_mod" "w_bigint_mul_builtin_exact")

# Direct calls, besides the arithmetic helpers, that read an Integer operand
# and return a value that does not hold it: comparisons and decimal text.
-> int_temp_reader?(name)
  name in ("w_eq" "w_neq" "w_eq_lit" "w_neq_lit" "w_lt" "w_gt" "w_lte" "w_gte" "__w_eq_fast" "__w_neq_fast" "__w_eq_lit_fast" "__w_neq_lit_fast" "__w_lt_fast" "__w_gt_fast" "__w_lte_fast" "__w_gte_fast" "__w_eq0_big_fast" "__w_lt0_big_fast" "__w_gt0_big_fast" "__w_lte0_big_fast" "__w_gte0_big_fast" "w_to_s" "w_int_to_s")

# string_id -> text, for reading the method name of a call_method_i64, plus
# immediate text -> name for the reader methods short enough to be inlined.
-> int_temp_string_texts(mod)
  texts = {}
  names = reader_method_names()
  ni = 0
  while ni < names.size()
    imm = inline_name_text(names[ni])
    texts[imm] = names[ni] if imm != nil
    ni += 1
  strs = mod[:strings]
  if strs == nil
    return texts
  si = 0
  while si < strs.size()
    texts[strs[si][:id]] = strs[si][:text]
    si += 1
  texts

# The method name a call_method_i64 names through a string/symbol constant
# or, for names of at most 5 bytes, an immediate.
-> int_temp_method_name(inst, defs, blocks, strings)
  mv = wire_get(inst, :method_name_val)
  if mv == nil
    return nil
  if type(mv) == "String" && mv.starts_with?("u0x")
    return strings[mv]
  if defs[mv] == nil
    return nil
  d = defs[mv]
  dinst = blocks[d[0]][:instructions][d[1]]
  if !(wire_kind(dinst) in (:string_i64 :symbol_i64))
    return nil
  strings[wire_get(dinst, :string_id)]

-> int_temp_producer?(name, fresh)
  int_temp_arith?(name) || (fresh != nil && fresh[name] == true)

-> int_temp_releases(func, strings, fresh, mod)
  blocks = func[:blocks]
  return 0 if blocks.size() == 0
  # Cheap pre-filter: most functions never produce an integer temporary.
  found = false
  bi = 0
  while bi < blocks.size() && !found
    instrs = blocks[bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      if ((wire_kind(inst) == :call_direct_i64 && int_temp_producer?(wire_get(inst, :name), fresh)) || int_fresh_source?(inst)) && wire_get(inst, :temp) != nil
        found = true
        break
      ii += 1
    bi += 1
  return 0 if !found || has_setjmp(func)

  defs = {}
  uses = {}
  known_int = {}
  arith = []
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
        if k == :nanbox_int
          known_int[t] = true
        elsif (k == :call_direct_i64 && int_temp_producer?(wire_get(inst, :name), fresh)) || int_fresh_source?(inst)
          arith.push(t)
      refs = loop_release_operands(inst)
      if refs == nil
        if env("TUNGSTEN_INT_TEMP_RELEASE_DEBUG") == "1"
          ignored = ccall("w_eputs", "int-temp " + func[:name].to_s() + " skipped: opaque " + k.to_s())
        return 0
      ri = 0
      while ri < refs.size()
        r = refs[ri]
        if uses[r] == nil
          uses[r] = []
        uses[r].push([bi, ii])
        ri += 1
      ii += 1
    bi += 1

  # after[block][index] = releases to insert after that instruction
  after = {}
  inserted = 0
  ai = 0
  while ai < arith.size()
    t = arith[ai]
    ai += 1
    tb = defs[t][0]
    tinst = blocks[tb][:instructions][defs[t][1]]
    witnesses = []
    # A fresh-returning callee sealed its result (int_fresh_returns) and a
    # parsed or literal BigInt is new, so only an arithmetic helper's
    # operands are witnesses.
    if wire_kind(tinst) == :call_direct_i64 && int_temp_arith?(wire_get(tinst, :name))
      targs = wire_get(tinst, :args)
      wi = 0
      while wi < wire_sequence_size(targs)
        witnesses.push(wire_sequence_get(targs, wi))
        wi += 1
    last = defs[t][1]
    ok = true
    tuses = uses[t]
    ui = 0
    while tuses != nil && ui < tuses.size() && ok
      ub = tuses[ui][0]
      uix = tuses[ui][1]
      ui += 1
      if ub != tb || uix <= defs[t][1]
        ok = false
        next
      last = uix if uix > last
      uinst = blocks[ub][:instructions][uix]
      uk = wire_kind(uinst)
      if uk == :truthy_inline
        next
      if uk == :call_direct_void && wire_get(uinst, :name) in ("__w_int_result_seal" "__w_int_alias_seal")
        next
      if mod[:write_only_globals] != nil && dead_global_store?(uinst, mod[:write_only_globals])
        next
      if uk == :call_direct_i64
        uname = wire_get(uinst, :name)
        if int_temp_arith?(uname)
          uargs = wire_get(uinst, :args)
          wj = 0
          while wj < wire_sequence_size(uargs)
            witnesses.push(wire_sequence_get(uargs, wj))
            wj += 1
          next
        next if int_temp_reader?(uname)
        # A source function that keeps no Integer argument in this position.
        summary = fn_escape_summary(mod, uname)
        ints = summary == nil ? nil : summary[:int_stored_escs]
        uargs = wire_get(uinst, :args)
        if ints == nil || uargs == nil
          ok = false
          next
        wj = 0
        while ok && wj < wire_sequence_size(uargs)
          if wire_sequence_get(uargs, wj) == t && (wj >= ints.size() || ints[wj] == true)
            ok = false
          wj += 1
        if ok && wire_get(uinst, :temp) != nil
          witnesses.push(wire_get(uinst, :temp))
        next
      if uk == :call_method_i64
        how = int_method_read?(uinst, t, mod, strings, defs, blocks)
        if how != nil
          # receiver (when t is only an argument) and result are witnesses
          witnesses.push(how) if how != true
          witnesses.push(wire_get(uinst, :temp)) if wire_get(uinst, :temp) != nil
          next
        ok = false if wire_get(uinst, :receiver) != t
        uargs = wire_get(uinst, :args)
        wj = 0
        while ok && wj < wire_sequence_size(uargs)
          ok = false if wire_sequence_get(uargs, wj) == t
          wj += 1
        ok = false if ok && wire_get(uinst, :temp_args_val) == t
        if ok
          mname = int_temp_method_name(uinst, defs, blocks, strings)
          ok = false if mname == nil || !int_temp_reader_method?(mname)
        next
      ok = false
    next if !ok

    # Integer constants need no check; t itself is checked anyway.
    checks = []
    wi = 0
    while wi < witnesses.size()
      w = witnesses[wi]
      wi += 1
      next if w == t || known_int[w] == true || checks.include?(w)
      checks.push(w)
    if checks.size() > 3
      if env("TUNGSTEN_INT_TEMP_RELEASE_DEBUG") == "1"
        ignored = ccall("w_eputs", "int-temp " + func[:name].to_s() + " " + t + ": " + checks.size().to_s() + " witnesses")
      next
    args = [checks.size().to_s(), t]
    wi = 0
    while wi < 3
      args.push(wi < checks.size() ? checks[wi] : "0")
      wi += 1
    key = tb.to_s() + ":" + last.to_s()
    if after[key] == nil
      after[key] = []
    after[key].push(wire_make_call_direct_void(args, "__w_int_temp_release"))
    inserted += 1

  return 0 if inserted == 0
  bi = 0
  while bi < blocks.size()
    instrs = blocks[bi][:instructions]
    touched = false
    ii = 0
    while ii < instrs.size() && !touched
      touched = true if after[bi.to_s() + ":" + ii.to_s()] != nil
      ii += 1
    if touched
      rebuilt = []
      ii = 0
      while ii < instrs.size()
        rebuilt.push(instrs[ii])
        extra = after[bi.to_s() + ":" + ii.to_s()]
        if extra != nil
          ei = 0
          while ei < extra.size()
            rebuilt.push(extra[ei])
            ei += 1
        ii += 1
      blocks[bi][:instructions] = rebuilt
    bi += 1
  if env("TUNGSTEN_INT_TEMP_RELEASE_DEBUG") == "1"
    ignored = ccall("w_eputs", "int-temp " + func[:name].to_s() + " released " + inserted.to_s())
  inserted

# Functions whose every return is a fresh integer: the result of an integer
# arithmetic helper or of another such function, read in the function only
# by the integer readers int_temp_releases accepts.  Their callers may then
# release the result (`sq(x)` dropped, compared, fed to arithmetic) like a
# helper's.  An arithmetic result whose operands were not both integers may
# be an unmarked alias handed back by a user operator, so right after each
# returned helper result the function calls __w_int_result_seal, which marks
# a BigInt result shared in that case; the release then only drops the mark.
# Returns name -> true.  Memoized calls go through memo_call_*, never a
# direct call, so a cached result is never taken for a fresh one.
-> int_fresh_returns(mod)
  fresh = {}
  cands = []
  funcs = mod[:functions]
  fn_names = {}
  fi = 0
  while fi < funcs.size()
    func = funcs[fi]
    fi += 1
    if func[:blocks].size() > 0 && func[:incremental_core_frozen] != true
      fn_names[func[:name]] = true
  fi = 0
  while fi < funcs.size()
    func = funcs[fi]
    fi += 1
    next if func[:blocks].size() == 0 || func[:incremental_core_frozen] == true
    cand = int_fresh_candidate(func, fn_names)
    if cand != nil
      cands.push(cand)
  # Optimistic fixed point would admit mutual recursion with no base case;
  # grow from nothing instead, a callee at a time.
  changed = true
  while changed
    changed = false
    ci = 0
    while ci < cands.size()
      c = cands[ci]
      ci += 1
      next if fresh[c[:name]] == true
      ok = true
      ki = 0
      while ok && ki < c[:callees].size()
        ok = false if fresh[c[:callees][ki]] != true
        ki += 1
      if ok
        fresh[c[:name]] = true
        changed = true
  ci = 0
  while ci < cands.size()
    c = cands[ci]
    ci += 1
    if fresh[c[:name]] == true
      int_fresh_insert_seals(c)
  fresh

# {name:, func:, callees: [...], seals: [[block, index, temp, args], ...]} when
# every ret_i64 returns an arithmetic-helper result or a direct call's result
# (fresh only if every callee turns out fresh), each read here only by
# integer readers; nil otherwise.
-> int_fresh_candidate(func, fn_names = nil)
  blocks = func[:blocks]
  rets = []
  defs = {}
  bi = 0
  while bi < blocks.size()
    instrs = blocks[bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      k = wire_kind(inst)
      if k == :ret_i64
        rets.push(wire_get(inst, :value))
      elsif k == :ret_void || k == :ret_i32 || k == :setjmp
        return nil
      elsif k == :call_direct_i64
        t = wire_get(inst, :temp)
        if t != nil
          defs[t] = [bi, ii]
      ii += 1
    bi += 1
  return nil if rets.size() == 0
  ret_set = {}
  ri = 0
  while ri < rets.size()
    rv = rets[ri]
    d = defs[rv]
    return nil if d == nil
    dinst = blocks[d[0]][:instructions][d[1]]
    dname = wire_get(dinst, :name)
    return nil if dname == func[:name]
    if fn_names != nil && !int_temp_arith?(dname) && fn_names[dname] != true
      return nil
    ret_set[rv] = true
    ri += 1
  uses = {}
  bi = 0
  while bi < blocks.size()
    instrs = blocks[bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      refs = loop_release_operands(inst)
      return nil if refs == nil
      ri = 0
      while ri < refs.size()
        r = refs[ri]
        if ret_set[r] == true
          if uses[r] == nil
            uses[r] = []
          uses[r].push([bi, ii])
        ri += 1
      ii += 1
    bi += 1
  callees = []
  seals = []
  ri = 0
  while ri < rets.size()
    v = rets[ri]
    ri += 1
    d = defs[v]
    return nil if d == nil
    dinst = blocks[d[0]][:instructions][d[1]]
    return nil if wire_kind(dinst) != :call_direct_i64
    dname = wire_get(dinst, :name)
    vuses = uses[v]
    ui = 0
    while vuses != nil && ui < vuses.size()
      uinst = blocks[vuses[ui][0]][:instructions][vuses[ui][1]]
      ui += 1
      uk = wire_kind(uinst)
      next if uk == :ret_i64 || uk == :truthy_inline
      if uk == :call_direct_i64
        uname = wire_get(uinst, :name)
        next if int_temp_arith?(uname) || int_temp_reader?(uname)
      return nil
    if int_temp_arith?(dname)
      args = wire_get(dinst, :args)
      a = wire_sequence_size(args) > 0 ? wire_sequence_get(args, 0) : v
      b = wire_sequence_size(args) > 1 ? wire_sequence_get(args, 1) : a
      dup = false
      sj = 0
      while sj < seals.size()
        dup = true if seals[sj][2] == v
        sj += 1
      seals.push([d[0], d[1], v, a, b]) if !dup
    elsif dname == func[:name]
      return nil
    else
      callees.push(dname) if !callees.include?(dname)
  {name: func[:name], func: func, callees: callees, seals: seals}

-> int_fresh_insert_seals(c)
  blocks = c[:func][:blocks]
  after = {}
  si = 0
  while si < c[:seals].size()
    sl = c[:seals][si]
    si += 1
    key = sl[0].to_s() + ":" + sl[1].to_s()
    if after[key] == nil
      after[key] = []
    after[key].push(wire_make_call_direct_void([sl[2], sl[3], sl[4]], "__w_int_result_seal"))
  bi = 0
  while bi < blocks.size()
    instrs = blocks[bi][:instructions]
    touched = false
    ii = 0
    while ii < instrs.size() && !touched
      touched = true if after[bi.to_s() + ":" + ii.to_s()] != nil
      ii += 1
    if touched
      rebuilt = []
      ii = 0
      while ii < instrs.size()
        rebuilt.push(instrs[ii])
        extra = after[bi.to_s() + ":" + ii.to_s()]
        if extra != nil
          ei = 0
          while ei < extra.size()
            rebuilt.push(extra[ei])
            ei += 1
        ii += 1
      blocks[bi][:instructions] = rebuilt
    bi += 1
  nil

# ---------------------------------------------------------------------------
# Owned variable slots.
#
# cfg.w keeps every variable that needs a merge phi in its memory slot, so a
# local assigned in a loop -- `y = sq(x)`, `a = zeros(12)`, `s = label(i)` --
# is a slot, and the passes above see only stores and loads.  Every value
# such a slot ever held stayed allocated until the process exited.
#
# A slot V of a function owns its values when:
#   - V is only loaded and stored: not a closure cell, not referenced by any
#     other instruction;
#   - every stored value is fresh -- an integer temporary (an arithmetic
#     helper's result or a fresh-returning call's) or a known heap
#     constructor's result (is_heap_producer), never both kinds in one slot --
#     or nil, and its only other uses read it without keeping it;
#   - every value loaded from V is only read: for integers, by the readers
#     int_temp_releases accepts (arithmetic helpers, comparisons, read-only
#     Integer methods, calls that keep no Integer argument); for heap values,
#     by is_nonretaining_consumer calls and by calls whose escape summary
#     neither stores nor returns that argument.  A load that is returned,
#     stored, captured or passed anywhere else disqualifies V.
# The pass then stores nil into V at entry, releases V's old value right
# after each store, and releases its final value before each return.  An
# integer stored from a helper is sealed first (__w_int_result_seal, so an
# alias from non-integer operands carries a mark), and a load read by a
# helper with operands not known to be integers, or passed to a call, is
# marked shared when the read could have kept it (__w_int_result_seal on the
# load, __w_int_alias_seal with the call's result): the later release then
# only drops the mark.  Heap values go through w_value_free.  Slots that the
# assignment-time releases (assign.w), the BigInt _dest/_mut entries or the
# loop-carried pass above already manage read V's loads through calls that
# are none of the above, so they never qualify.  A path that leaves through a
# raise skips the releases and only leaks.
# TUNGSTEN_SLOT_RELEASE=0 disables the pass.
# ---------------------------------------------------------------------------

-> owned_slot_releases(func, mod, fresh, strings)
  blocks = func[:blocks]
  slots = func[:var_slots]
  return 0 if slots == nil || slots.size() == 0 || blocks.size() < 1
  heap_cells = func[:heap_slot_names]
  promoted = func[:promoted_vars]
  cand = {}
  has_cand = false
  names = slots.keys()
  ni = 0
  while ni < names.size()
    ptr = slots[names[ni]]
    if ptr.starts_with?("%v") && (heap_cells == nil || heap_cells[names[ni]] != true) && (promoted == nil || promoted[ptr] == nil)
      cand[ptr] = true
      has_cand = true
    ni += 1
  return 0 if !has_cand
  producer_temps = {}
  has_producer = false
  stored_vals = []
  bi = 0
  while bi < blocks.size()
    instrs = blocks[bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      k = wire_kind(inst)
      if k == :setjmp
        return 0
      if k == :store_i64 && cand[wire_get(inst, :ptr)] == true
        stored_vals.push(wire_get(inst, :value))
      elsif k == :bigint_literal_i64 && wire_get(inst, :temp) != nil
        producer_temps[wire_get(inst, :temp)] = true
        has_producer = true
      elsif k == :call_direct_i64 && wire_get(inst, :temp) != nil
        cname = wire_get(inst, :name)
        if int_temp_producer?(cname, fresh) || is_heap_producer(inst) || fresh_heap_call?(inst, mod) || cname == "w_bigint_from_dec_str"
          producer_temps[wire_get(inst, :temp)] = true
          has_producer = true
      ii += 1
    bi += 1
  return 0 if !has_producer || stored_vals.size() == 0
  has_producer_store = false
  svi = 0
  while svi < stored_vals.size()
    if producer_temps[stored_vals[svi]] == true
      has_producer_store = true
      break
    svi += 1
  return 0 if !has_producer_store
  wo = mod[:write_only_globals]
  wo = {} if wo == nil

  defs = {}
  uses = {}
  loads = {}
  stores = {}
  bad = {}
  rets = []
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
      if k in (:ret_i64 :ret_i32 :ret_void)
        rets.push([bi, ii])
      access = nil
      if k in (:load_i64 :store_i64)
        sp = wire_get(inst, :ptr)
        if sp != nil && cand[sp] == true
          access = sp
          if k == :load_i64
            loads[sp] = [] if loads[sp] == nil
            loads[sp].push([bi, ii, t])
          else
            stores[sp] = [] if stores[sp] == nil
            stores[sp].push([bi, ii, wire_get(inst, :value)])
      refs = loop_release_operands(inst)
      return 0 if refs == nil
      ri = 0
      while ri < refs.size()
        r = refs[ri]
        bad[r] = true if cand[r] == true && r != access
        uses[r] = [] if uses[r] == nil
        uses[r].push([bi, ii])
        ri += 1
      ii += 1
    bi += 1
  return 0 if rets.size() == 0

  known_int = {}
  dk = defs.keys()
  di = 0
  while di < dk.size()
    d = defs[dk[di]]
    known_int[dk[di]] = true if wire_kind(blocks[d[0]][:instructions][d[1]]) == :nanbox_int
    di += 1

  ctx = {blocks: blocks, defs: defs, uses: uses, cand: cand, wo: wo, known_int: known_int, fresh: fresh, strings: strings, mod: mod}
  info = {}
  sk = stores.keys()
  si = 0
  while si < sk.size()
    ptr = sk[si]
    si += 1
    next if bad[ptr] == true
    plan = owned_slot_plan(ptr, stores[ptr], loads[ptr], ctx)
    info[ptr] = plan if plan != nil
  # A cell sharing values with a cell that is not owned loses them too.
  changed = true
  while changed
    changed = false
    ik = info.keys()
    ki = 0
    while ki < ik.size()
      ptr = ik[ki]
      ki += 1
      next if info[ptr] == nil
      dl = info[ptr][:deps].keys()
      dj = 0
      while dj < dl.size()
        if info[dl[dj]] == nil
          info[ptr] = nil
          changed = true
          break
        dj += 1
  owned = []
  ik = info.keys()
  ki = 0
  while ki < ik.size()
    owned.push(ik[ki]) if info[ik[ki]] != nil
    ki += 1
  return 0 if owned.size() == 0

  # Edits, keyed "block:index": before[] / after[] lists of instructions.
  before = {}
  after = {}
  sealed = {}
  shared = {}
  oi = 0
  while oi < owned.size()
    ptr = owned[oi]
    plan = info[ptr]
    oi += 1
    heap = plan[:kind] == :heap
    # nil at entry: the final release must never read an unset slot
    owned_slot_edit(before, "0:0", wire_make_store_i64(ptr, "0"))
    pm = 0
    while pm < plan[:pre_marks].size()
      owned_slot_edit(before, plan[:pre_marks][pm][0], plan[:pre_marks][pm][1])
      pm += 1
    sl = stores[ptr]
    sj = 0
    while sj < sl.size()
      st = sl[sj]
      sj += 1
      key = st[0].to_s() + ":" + st[1].to_s()
      v = st[2]
      seal = plan[:seals][v]
      if seal != nil && sealed[v] != true && defs[v] != nil
        sealed[v] = true
        dkey = defs[v][0].to_s() + ":" + defs[v][1].to_s()
        owned_slot_edit(after, dkey, wire_make_call_direct_void([v, seal[0], seal[1]], "__w_int_result_seal"))
      # an integer stored in several owned cells: one shared mark per extra
      # cell, right after its definition (dominates every store)
      n = plan[:cells_of][v]
      if n != nil && n > 1 && shared[v] != true && defs[v] != nil
        shared[v] = true
        dkey = defs[v][0].to_s() + ":" + defs[v][1].to_s()
        mi = 1
        while mi < n
          owned_slot_edit(after, dkey, wire_make_call_direct_void([v, v], "__w_int_alias_seal"))
          mi += 1
      old = next_temp(func)
      owned_slot_edit(before, key, wire_make_load_i64(ptr, old))
      owned_slot_edit(after, key, owned_slot_release(old, heap))
    ri = 0
    while ri < rets.size()
      key = rets[ri][0].to_s() + ":" + rets[ri][1].to_s()
      ri += 1
      next if plan[:transfers][key] == true
      fin = next_temp(func)
      owned_slot_edit(before, key, wire_make_load_i64(ptr, fin))
      owned_slot_edit(before, key, owned_slot_release(fin, heap))
    ci = 0
    while ci < plan[:marks].size()
      m = plan[:marks][ci]
      ci += 1
      owned_slot_edit(after, m[0], m[1])

  bi = 0
  while bi < blocks.size()
    instrs = blocks[bi][:instructions]
    rebuilt = []
    ii = 0
    while ii < instrs.size()
      key = bi.to_s() + ":" + ii.to_s()
      pre = before[key]
      if pre != nil
        pj = 0
        while pj < pre.size()
          rebuilt.push(pre[pj])
          pj += 1
      rebuilt.push(instrs[ii])
      post = after[key]
      if post != nil
        pj = 0
        while pj < post.size()
          rebuilt.push(post[pj])
          pj += 1
      ii += 1
    blocks[bi][:instructions] = rebuilt
    bi += 1
  if env("TUNGSTEN_SLOT_RELEASE_DEBUG") == "1"
    ignored = ccall("w_eputs", "slot-release " + func[:name].to_s() + " owned " + owned.size().to_s())
  owned.size()

-> owned_slot_edit(table, key, inst)
  table[key] = [] if table[key] == nil
  table[key].push(inst)
  nil

-> owned_slot_release(value, heap)
  if heap
    return wire_make_free_value(value)
  wire_make_call_direct_void(["0", value, "0", "0", "0"], "__w_int_temp_release")

# A fresh integer that is not an arithmetic result: a parsed or literal BigInt.
-> int_fresh_source?(inst)
  k = wire_kind(inst)
  return true if k == :bigint_literal_i64
  k == :call_direct_i64 && wire_get(inst, :name) == "w_bigint_from_dec_str"

# Is `inst` a store of a value into a global nothing ever loads?
-> dead_global_store?(inst, wo)
  wire_kind(inst) == :store_global && wo[wire_get(inst, :name)] == true

# nil, or {kind: :int|:heap, seals: {stored temp -> [a, b]}, marks: [[key, inst]],
# deps: {other cell -> true}, cells_of: {stored temp -> owned stores of it}}
-> owned_slot_plan(ptr, sl, ll, ctx)
  blocks = ctx[:blocks]
  defs = ctx[:defs]
  uses = ctx[:uses]
  cand = ctx[:cand]
  wo = ctx[:wo]
  kind = :nil
  seals = {}
  marks = []
  pre_marks = []
  borrowed = []
  transfers = {}
  deps = {}
  cells_of = {}
  si = 0
  while si < sl.size()
    v = sl[si][2]
    skey = sl[si][0].to_s() + ":" + sl[si][1].to_s()
    si += 1
    next if v == "0"
    d = defs[v]
    if d == nil
      # a parameter: borrowed, see below
      borrowed.push([skey, v])
      next
    dinst = blocks[d[0]][:instructions][d[1]]
    dk = wire_kind(dinst)
    vkind = nil
    if dk == :nanbox_int
      next
    elsif dk == :load_i64 && cand[wire_get(dinst, :ptr)] == true
      # a copy of another cell's integer: one more holder, so one more mark;
      # that cell's plan checks the load's other uses
      vkind = :int
      deps[wire_get(dinst, :ptr)] = true
      lkey = d[0].to_s() + ":" + d[1].to_s()
      marks.push([lkey, wire_make_call_direct_void([v, v], "__w_int_alias_seal")])
      return nil if kind != :nil && kind != vkind
      kind = vkind
      next
    elsif dk == :call_direct_i64 && int_temp_producer?(wire_get(dinst, :name), ctx[:fresh])
      vkind = :int
      if int_temp_arith?(wire_get(dinst, :name))
        args = wire_get(dinst, :args)
        a = wire_sequence_size(args) > 0 ? wire_sequence_get(args, 0) : v
        b = wire_sequence_size(args) > 1 ? wire_sequence_get(args, 1) : a
        seals[v] = [a, b]
    elsif int_fresh_source?(dinst)
      vkind = :int
    elsif dk == :call_direct_i64 && (is_heap_producer(dinst) || fresh_heap_call?(dinst, ctx[:mod]))
      vkind = :heap
    else
      # Not fresh (a parameter, a call's or method's result, ...): an integer
      # cell may still hold it as one more counted holder -- a shared mark
      # right before the store, so the cell's release only drops that mark.
      # Marks and releases touch BigInts only, so a non-integer is unaffected.
      borrowed.push([skey, v])
      next
    return nil if kind != :nil && kind != vkind
    kind = vkind
    # the stored temp: plain reads, plus stores into owned cells (one per
    # cell for a heap value)
    vuses = uses[v]
    n = 0
    ui = 0
    while vuses != nil && ui < vuses.size()
      uinst = blocks[vuses[ui][0]][:instructions][vuses[ui][1]]
      ui += 1
      if wire_kind(uinst) == :store_i64
        return nil if wire_get(uinst, :value) != v
        target = wire_get(uinst, :ptr)
        return nil if cand[target] != true
        deps[target] = true if target != ptr
        n += 1
        next
      next if dead_global_store?(uinst, wo)
      return nil if !owned_slot_plain_read?(uinst, v, kind, ctx[:strings], defs, blocks, ctx[:mod])
      if kind == :int && wire_kind(uinst) == :call_method_i64
        how = int_method_read?(uinst, v, ctx[:mod], ctx[:strings], defs, blocks)
        if how != nil
          vkey = vuses[ui - 1][0].to_s() + ":" + vuses[ui - 1][1].to_s()
          if how != true
            marks.push([vkey, wire_make_call_direct_void([v, how, how], "__w_int_result_seal")])
          if wire_get(uinst, :temp) != nil
            marks.push([vkey, wire_make_call_direct_void([v, wire_get(uinst, :temp)], "__w_int_alias_seal")])
      elsif kind == :int && wire_kind(uinst) == :call_direct_i64 && wire_get(uinst, :temp) != nil && !int_temp_arith?(wire_get(uinst, :name)) && !int_temp_reader?(wire_get(uinst, :name))
        vkey = vuses[ui - 1][0].to_s() + ":" + vuses[ui - 1][1].to_s()
        marks.push([vkey, wire_make_call_direct_void([v, wire_get(uinst, :temp)], "__w_int_alias_seal")])
    return nil if n < 1 || (kind == :heap && n != 1)
    cells_of[v] = n
  return nil if kind == :nil
  if borrowed.size() > 0
    return nil if kind != :int
    bi2 = 0
    while bi2 < borrowed.size()
      pre_marks.push([borrowed[bi2][0], wire_make_call_direct_void([borrowed[bi2][1], borrowed[bi2][1]], "__w_int_alias_seal")])
      bi2 += 1
  li = 0
  while ll != nil && li < ll.size()
    l = ll[li][2]
    li += 1
    next if l == nil
    luses = uses[l]
    ui = 0
    while luses != nil && ui < luses.size()
      ub = luses[ui][0]
      uix = luses[ui][1]
      ui += 1
      uinst = blocks[ub][:instructions][uix]
      key = ub.to_s() + ":" + uix.to_s()
      uk = wire_kind(uinst)
      next if dead_global_store?(uinst, wo)
      if uk == :ret_i64 && wire_get(uinst, :value) == l
        # returned: the caller takes the current value over, so that return
        # skips this cell's final release; earlier values are still ours
        transfers[key] = true
        next
      if uk == :store_i64 && wire_get(uinst, :value) == l
        # copied into another cell: fine for integers when that cell is owned
        target = wire_get(uinst, :ptr)
        return nil if kind != :int || cand[target] != true
        deps[target] = true
        next
      if kind == :int && uk == :call_direct_i64
        uname = wire_get(uinst, :name)
        if int_temp_arith?(uname)
          # other operands not known to be integers: mark the load if one is not
          others = []
          uargs = wire_get(uinst, :args)
          wj = 0
          while wj < wire_sequence_size(uargs)
            o = wire_sequence_get(uargs, wj)
            others.push(o) if o != l && ctx[:known_int][o] != true
            wj += 1
          if others.size() > 0
            b = others.size() > 1 ? others[1] : others[0]
            marks.push([key, wire_make_call_direct_void([l, others[0], b], "__w_int_result_seal")])
          next
        next if int_temp_reader?(uname)
      if !owned_slot_plain_read?(uinst, l, kind, ctx[:strings], defs, blocks, ctx[:mod])
        return nil
      if uk == :call_direct_i64 && wire_get(uinst, :temp) != nil && !(kind == :int && int_temp_reader?(wire_get(uinst, :name)))
        if kind == :int
          marks.push([key, wire_make_call_direct_void([l, wire_get(uinst, :temp)], "__w_int_alias_seal")])
      if uk == :call_method_i64 && kind == :int
        how = int_method_read?(uinst, l, ctx[:mod], ctx[:strings], defs, blocks)
        if how != nil
          if how != true
            # an argument: kept only if the receiver was not an Integer
            marks.push([key, wire_make_call_direct_void([l, how, how], "__w_int_result_seal")])
          if wire_get(uinst, :temp) != nil
            marks.push([key, wire_make_call_direct_void([l, wire_get(uinst, :temp)], "__w_int_alias_seal")])
  {kind: kind, seals: seals, marks: marks, pre_marks: pre_marks, deps: deps, cells_of: cells_of, transfers: transfers}

# Does `inst` only read `v` (a value of a slot of `kind`) without keeping it?
-> owned_slot_plain_read?(inst, v, kind, strings, defs, blocks, mod)
  k = wire_kind(inst)
  return true if k == :truthy_inline
  if k == :call_direct_i64
    name = wire_get(inst, :name)
    if kind == :int
      return true if int_temp_arith?(name) || int_temp_reader?(name)
    else
      return true if is_nonretaining_consumer(name)
    summary = fn_escape_summary(mod, name)
    return false if summary == nil
    flags = kind == :int ? summary[:int_stored_escs] : summary[:escs]
    return false if flags == nil
    args = wire_get(inst, :args)
    return false if args == nil
    ai = 0
    while ai < wire_sequence_size(args)
      if wire_sequence_get(args, ai) == v && (ai >= flags.size() || flags[ai] == true)
        return false
      ai += 1
    return true
  if k == :call_method_i64 && kind == :int
    if wire_get(inst, :receiver) == v
      args = wire_get(inst, :args)
      plain = true
      ai = 0
      while ai < wire_sequence_size(args)
        plain = false if wire_sequence_get(args, ai) == v
        ai += 1
      plain = false if wire_get(inst, :temp_args_val) == v
      mname = int_temp_method_name(inst, defs, blocks, strings)
      return true if plain && mname != nil && int_temp_reader_method?(mname)
    return int_method_read?(inst, v, mod, strings, defs, blocks) != nil
  false


# ---------------------------------------------------------------------------
# Fresh heap results.
#
# `a = zeros(12)`, `c = copy_list(base)`, `s = label(i)`: the callee builds a
# new array or string and returns it, and the caller drops it -- but only
# known runtime constructors counted as producers, so every such result was
# kept until exit.  A source function returns a fresh heap value when every
# ret_i64 returns either a known constructor's result (is_heap_producer) or
# the result of another such function, and nothing in the function other
# than the return lets that value escape (mark_escapes over every other
# instruction, with the escape summaries).  Callers then treat its result as
# a producer: freed at scope end when it does not escape there, or owned by
# a variable slot (owned_slot_releases).  Computed callee first, growing from
# nothing, so recursion without a base case never qualifies.  Memoized calls
# go through memo_call_*, never a direct call.  Sets mod[:fresh_heap_fns].
# ---------------------------------------------------------------------------
-> fresh_heap_returns(mod)
  fresh = {}
  kinds = {}
  mod[:fresh_heap_fns] = fresh
  mod[:fresh_heap_kinds] = kinds
  return fresh if env("TUNGSTEN_FREE") == "0" || env("TUNGSTEN_FRESH_HEAP") == "0"
  cands = []
  funcs = mod[:functions]
  fi = 0
  while fi < funcs.size()
    func = funcs[fi]
    fi += 1
    next if func[:blocks].size() == 0 || func[:incremental_core_frozen] == true
    cand = fresh_heap_candidate(func, mod)
    cands.push(cand) if cand != nil
  changed = true
  while changed
    changed = false
    ci = 0
    while ci < cands.size()
      c = cands[ci]
      ci += 1
      next if fresh[c[:name]] == true
      ok = true
      ki = 0
      while ok && ki < c[:callees].size()
        ok = false if fresh[c[:callees][ki]] != true
        ki += 1
      if ok
        fresh[c[:name]] = true
        changed = true
        # one kind for every return (own constructors and fresh callees
        # alike), else unknown
        kind = c[:own_kind]
        ki = 0
        while ki < c[:callees].size()
          ck = kinds[c[:callees][ki]]
          if ck == nil
            kind = :mixed
          elsif kind == nil
            kind = ck
          elsif ck != kind
            kind = :mixed
          ki += 1
        kinds[c[:name]] = kind if kind != nil && kind != :mixed
  fresh

-> fresh_heap_candidate(func, mod)
  blocks = func[:blocks]
  rets = []
  defs = {}
  bi = 0
  while bi < blocks.size()
    instrs = blocks[bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      k = wire_kind(inst)
      if k == :ret_i64
        rets.push(wire_get(inst, :value))
      elsif k in (:ret_void :ret_i32 :setjmp)
        return nil
      elsif k == :call_direct_i64
        t = wire_get(inst, :temp)
        defs[t] = inst if t != nil
      ii += 1
    bi += 1
  return nil if rets.size() == 0
  callees = []
  own_kind = nil
  mixed = false
  ri = 0
  while ri < rets.size()
    d = defs[rets[ri]]
    ri += 1
    return nil if d == nil || wire_kind(d) != :call_direct_i64
    if is_heap_producer(d)
      k = heap_producer_kind(d)
      if own_kind == nil
        own_kind = k
      elsif k != own_kind
        mixed = true
      next
    name = wire_get(d, :name)
    return nil if name == func[:name] || fn_escape_summary(mod, name) == nil
    callees.push(name) if !callees.include?(name)
  # Every use but the returns: does a returned value escape?
  escaped = {}
  bi = 0
  while bi < blocks.size()
    instrs = blocks[bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      k = wire_kind(inst)
      if k == :phi_ssa
        incoming = wire_get(inst, :incoming)
        pi = 0
        while incoming != nil && pi < wire_sequence_size(incoming)
          escaped[wire_sequence_get(incoming, pi)] = true
          pi += 2
      elsif k != :ret_i64
        mark_escapes(inst, escaped, mod, nil)
      ii += 1
    bi += 1
  ri = 0
  while ri < rets.size()
    return nil if escaped[rets[ri]] == true
    ri += 1
  own_kind = :mixed if mixed
  {name: func[:name], callees: callees, own_kind: own_kind}

# Globals some function stores and no function ever loads.  A top-level
# variable is a module global mirrored into a local slot of main, which then
# reads only the slot, so its global copy is a dead write: storing a value
# there neither keeps it alive for anyone nor needs releasing.  The globals
# are internal to the module, so its functions (frozen core ones included)
# are every possible reader.  Sets mod[:write_only_globals].
-> write_only_globals(mod)
  stored = {}
  loaded = {}
  funcs = mod[:functions]
  fi = 0
  while fi < funcs.size()
    blocks = funcs[fi][:blocks]
    fi += 1
    bi = 0
    while bi < blocks.size()
      instrs = blocks[bi][:instructions]
      ii = 0
      while ii < instrs.size()
        k = wire_kind(instrs[ii])
        if k == :store_global
          stored[wire_get(instrs[ii], :name)] = true
        elsif k == :load_global
          loaded[wire_get(instrs[ii], :name)] = true
        ii += 1
      bi += 1
  wo = {}
  sk = stored.keys()
  si = 0
  while si < sk.size()
    wo[sk[si]] = true if loaded[sk[si]] != true
    si += 1
  mod[:write_only_globals] = wo
  wo

# ---------------------------------------------------------------------------
# Integer values passed to methods.
#
# A loop that calls a program's own BigInt method on its values -- a script
# reopening BigInt with `-> mulmod(m)` and calling `x.mulmod(m)` -- pinned
# every value it called it on.  Releases only ever act on BigInts, so the
# method that matters is the one a BigInt receiver dispatches to, which the
# module registers with class_add_method.  module_method_table collects
# those registrations; int_method_read? accepts the call when:
#   - the value is the receiver: BigInt's definition (else Integer's) of that
#     name and arity is the only candidate and its escape summary keeps
#     neither an Integer self nor the value as an argument;
#   - the value is an argument: every BigInt / Integer / Int definition of
#     that name and arity keeps nothing in that position, and the caller
#     marks the value at run time when the receiver turns out not to be an
#     Integer (so a user class's method can never be the one that kept it).
# The caller also marks the value when the call's result may be it.  A module
# that defines method_missing or adds methods at run time gets none of this.
# ---------------------------------------------------------------------------
-> module_method_table(mod, texts)
  table = {}
  funcs = mod[:functions]
  fi = 0
  while fi < funcs.size()
    blocks = funcs[fi][:blocks]
    fi += 1
    cls_of = nil
    bi = 0
    while bi < blocks.size()
      instrs = blocks[bi][:instructions]
      ii = 0
      while ii < instrs.size()
        inst = instrs[ii]
        ii += 1
        k = wire_kind(inst)
        if k == :call_direct_i64
          if table[:dynamic] != true
            cn = wire_get(inst, :name)
            if cn != nil && (cn.index("define_method") != nil || cn.index("add_method") != nil || cn.index("method_missing") != nil)
              table[:dynamic] = true
        elsif k == :load_class
          t = wire_get(inst, :temp)
          if t != nil
            cls_of = {} if cls_of == nil
            cls_of[t] = wire_get(inst, :class_name)
        elsif k == :class_new
          t = wire_get(inst, :temp)
          if t != nil
            cls_of = {} if cls_of == nil
            cls_of[t] = texts[wire_get(inst, :name_str_id)]
        elsif k == :class_add_method
          name = texts[wire_get(inst, :method_str_id)]
          if name == nil || name == "method_missing" || name == "respond_to_missing?"
            table[:dynamic] = true
          else
            table[name] = [] if table[name] == nil
            cls_name = cls_of != nil ? cls_of[wire_get(inst, :class_temp)] : nil
            table[name].push({cls: cls_name, fname: wire_get(inst, :fn_name), arity: wire_get(inst, :arity), min: wire_get(inst, :min_arity), splat: wire_get(inst, :splat_index)})
            imm = inline_name_text(name)
            texts[imm] = name if imm != nil
      bi += 1
  table

# The registrations of `name` on class `cls` that take `arity` arguments
# (self included).
-> method_entries_for(table, name, cls, arity)
  out = []
  es = table[name]
  return out if es == nil
  ei = 0
  while ei < es.size()
    e = es[ei]
    ei += 1
    next if e[:cls] != cls
    hi = e[:arity]
    lo = e[:min] == nil ? hi : e[:min]
    if e[:splat] != nil && e[:splat] >= 0
      out.push(e) if arity >= lo
    elsif arity >= lo && arity <= hi
      out.push(e)
  out

# Does the method keep nothing in parameter position `pos` (0 = self) when
# that argument is an Integer?
-> method_keeps_no_int?(mod, e, pos)
  return false if e[:splat] != nil && e[:splat] >= 0
  summary = fn_escape_summary(mod, e[:fname])
  return false if summary == nil
  ints = summary[:int_stored_escs]
  ints != nil && pos < ints.size() && ints[pos] != true

# nil when the call may keep `v`; else the receiver when `v` is only an
# argument (the caller marks `v` unless the receiver is an Integer), or
# true when `v` is the receiver.
-> int_method_read?(inst, v, mod, strings, defs, blocks)
  table = mod[:method_table]
  return nil if table == nil || table[:dynamic] == true
  name = int_temp_method_name(inst, defs, blocks, strings)
  return nil if name == nil
  args = wire_get(inst, :args)
  argc = wire_sequence_size(args)
  arity = argc + 1
  return nil if wire_get(inst, :temp_args_val) == v
  positions = []
  ai = 0
  while ai < argc
    positions.push(ai + 1) if wire_sequence_get(args, ai) == v
    ai += 1
  receiver = wire_get(inst, :receiver)
  if receiver == v
    targets = method_entries_for(table, name, "BigInt", arity)
    targets = method_entries_for(table, name, "Integer", arity) if targets.size() == 0
    return nil if targets.size() != 1
    return nil if !method_keeps_no_int?(mod, targets[0], 0)
    pi = 0
    while pi < positions.size()
      return nil if !method_keeps_no_int?(mod, targets[0], positions[pi])
      pi += 1
    return true
  return nil if positions.size() == 0
  all = []
  ci = 0
  classes = ["BigInt", "Integer", "Int"]
  while ci < classes.size()
    es = method_entries_for(table, name, classes[ci], arity)
    ej = 0
    while ej < es.size()
      all.push(es[ej])
      ej += 1
    ci += 1
  return nil if all.size() == 0
  ei = 0
  while ei < all.size()
    pi = 0
    while pi < positions.size()
      return nil if !method_keeps_no_int?(mod, all[ei], positions[pi])
      pi += 1
    ei += 1
  receiver
