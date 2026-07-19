# WIRE — Tungsten IR data model and function builder
# WIRE is a non-SSA IR using named variable slots with load/store,
# plus SSA-like temps for intermediates. Functions have basic blocks;
# blocks have instruction lists. Instructions are hashes with an :op key.

# -- Module --

-> wire_module(source_path)
  {
    source_path:      source_path,
    functions:        [],
    strings:          [],
    string_ids_by_text: {},
    # Build-time constants from `bin/tungsten -D NAME=VALUE`.
    # Populated by lower_ast from the TUNGSTEN_DEFINES env var. lower_var
    # consults this map BEFORE normal var resolution; if a name is in
    # build_defines its value is emitted as an i64 literal (e.g. w_true
    # for "true"), so `if FAST_MATH` constant-folds at LLVM level into
    # an unconditional branch — no runtime global load.
    build_defines:    {},
    known_classes:    {},
    # `constant_alias "WC"` directives, collected in lowering's
    # registration prepass: alias → namespace ("WC" → "Tungsten:Carbide").
    # lower_var rewrites the first segment of a qualified class reference
    # through this map before the exact known_classes lookup.
    constant_aliases: {},
    known_traits:     {},
    known_calls:      {},
    block_method_names: {},
    known_static_methods: {},
    known_fn_param_counts: {},
    known_fn_overloads: {},
    known_typed_overload_counts: {},
    known_unique_typed_overload_keys: {},
    known_unique_typed_overload_param_types: {},
    raw_fn_param_kinds: {},
    known_pure_calls: {},
    fn_return_types:  {},
    class_methods:    {},
    cvar_globals:     {},
    fn_memo_tables:   {},
    fn_memo_table_order: [],
    used_memo_tables: {},
    used_memo_table_order: [],
    top_level_vars:   {},
    top_level_var_types: {},
    top_level_static_types: {},
    next_string:      0,
    next_block:       0,
    next_ic:          0,
    next_call_site:   0,
    reuse_sites:     [],
    next_reuse_site: 0,
    custom_units:    {},
    # IDs 256..2047 are generated from the Ruby reference unit registry.
    # User-defined/unknown units live above that range and are heap-boxed.
    next_custom_unit_id: 2048
  }

-> next_call_site_id(mod)
  id = mod[:next_call_site]
  mod[:next_call_site] = id + 1
  id

-> module_string_constant(mod, text)
  existing = mod[:string_ids_by_text][text]
  if existing != nil
    return existing

  id = mod[:next_string]
  mod[:next_string] = id + 1
  mod[:strings].push({id: id, text: text})
  mod[:string_ids_by_text][text] = id
  id

# -- Function builder --

-> build_function(name, params, return_type, is_toplevel, extra_params)
  result = {
    name:         name,
    original_name: name,
    params:       params,
    extra_params: extra_params,
    return_type:  return_type,
    is_toplevel:  is_toplevel,
    blocks:       [],
    var_slots:    {},
    var_slot_types: {},
    next_temp:    0,
    next_label:   0,
    next_var:     0,
    next_scope:   0,
    loop_stack:   [],
    # Number of lexically-open begin/rescue exception frames at the current
    # lowering position. Every control transfer that leaves a protected try
    # region without reaching its fall-through pop (return/break/next/recase)
    # must emit one w_exception_pop per abandoned frame, or the frame goes
    # stale on w_exception_stack and a later raise longjmps into a dead
    # stack frame (SIGSEGV / corrupted dispatch).
    eh_depth:     0,
    # Stack of enclosing `case` contexts that contain a `recase`. Each entry:
    # {subj_ptr, subject_node, redispatch_label}. `recase` targets the top.
    case_stack:   [],
    # Stack of recycle-tracking lists, one per open scope.
    # Each entry: [{temp: "%tN", kind: :array|:hash|:typed|:strbuf}, ...]
    # On scope_pop, emit w_*_recycle for each tracked temp, then pop the stack.
    scope_recycle_stack: [nil],
    # Map: var slot name → {kind, temp} for ## recycle vars. Used to detect
    # reassignment and emit recycle of the old value before the new assign.
    recycle_vars: {},
    is_memoized:  false,
    exit_label:   nil,
    result_slot:  nil
  }

  start_block(result, "__entry")
  result

-> next_temp(f)
  n = f[:next_temp]
  f[:next_temp] = n + 1
  "%t" + n.to_s()

-> next_label(f, prefix)
  n = f[:next_label]
  f[:next_label] = n + 1
  prefix + "." + n.to_s()

-> next_scope_id(f)
  n = f[:next_scope]
  f[:next_scope] = n + 1
  n

-> ensure_var_slot(f, name, slot_type = "i64")
  existing = f[:var_slots][name]
  if existing != nil
    if f[:var_slot_types][name] == nil
      f[:var_slot_types][name] = slot_type
    return existing
  n = f[:next_var]
  f[:next_var] = n + 1
  # Dotted name: valid in LLVM, impossible as a Tungsten identifier — a
  # user param/local literally named v<N> would otherwise collide with
  # the minted slot ("multiple definition of local value named 'v1'").
  ptr = "%vs." + n.to_s()
  f[:var_slots][name] = ptr
  f[:var_slot_types][name] = slot_type
  ptr

# -- Basic blocks --

-> start_block(f, label)
  f[:blocks].push({label: label, instructions: []})

-> current_block(f)
  f[:blocks][f[:blocks].size() - 1]

-> emit_instruction(f, instruction)
  current_block(f)[:instructions].push(instruction)

# Early-return emitter. Ordinary implicit/final returns are emitted only after
# their function body has been lowered and need no per-site metadata. Keeping
# this work out of emit_instruction leaves the universal hot path unchanged.
-> emit_return_instruction(f, instruction)
  # Capture how many function-body values are live at THIS return site.
  # Recording the prefix length now prevents a later sibling allocation from being
  # retroactively inserted ahead of an earlier return where its temp neither
  # exists nor dominates. The entries are append-only, so a count is enough;
  # this avoids allocating a copied Array for every return. Nested scopes are
  # handled at the transfer itself.
  stack = f[:scope_recycle_stack]
  count = 0
  if stack.size() > 0 && stack[0] != nil && stack[0].size() > 0
    count = stack[0].size()
  # Zero is meaningful: a later sibling allocation must not be attached to
  # this earlier return by the finalizer's ordinary full-list fallback.
  instruction[:function_recycle_count] = count
  emit_instruction(f, instruction)

# -- Scope-aware push/pop with ## recycle tracking --
# Each scope's recycle-tracked vars are emitted as w_*_recycle calls before
# scope_pop. The top of scope_recycle_stack is the current scope's list.

-> emit_scope_push(f, id)
  emit_instruction(f, {op: :scope_push, id: id})
  f[:scope_recycle_stack].push(nil)

# Emit normal-path cleanup for every recycle value in scopes deeper than
# `keep_depth`. The compile-time scope stack is deliberately left untouched:
# control-flow lowerers use this immediately before a return/break/next, then
# the enclosing lexical lowerer restores its own path-local stack snapshot.
#
# `keep_depth` is a COUNT, not an index. With the initial function-body entry
# at depth 1, passing 1 cleans nested lexical scopes while leaving function-
# body cleanup to the existing per-ret finalizer; passing 0 cleans everything
# for a non-local block return, which never reaches a ret in this function.
-> emit_recycles_above_depth(f, keep_depth)
  stack = f[:scope_recycle_stack]
  depth = keep_depth
  if depth < 0
    depth = 0
  if depth > stack.size()
    depth = stack.size()

  si = stack.size() - 1
  while si >= depth
    entries = stack[si]
    if entries != nil
      # Both the scope stack and each scope's entries unwind in LIFO order.
      ei = entries.size() - 1
      while ei >= 0
        entry = entries[ei]
        emit_instruction(f, {op: :cleanup_pop})
        emit_instruction(f, {op: recycle_op_for_kind(entry[:kind]), value: entry[:temp]})
        ei -= 1
    si -= 1

# Restore only the compiler's lexical bookkeeping after a path terminates.
# Runtime cleanup has already happened either at the explicit normal transfer
# (return/break/next) or in w_raise's exception unwind. Emitting cleanup here
# would duplicate it; failing to discard these entries poisons sibling paths.
-> restore_recycle_scope_depth(f, depth)
  stack = f[:scope_recycle_stack]
  target = depth
  if target < 1
    target = 1
  while stack.size() > target
    stack.pop()

-> emit_recycles_for_current_scope(f)
  stack = f[:scope_recycle_stack]
  if stack.size() == 0
    return nil
  # Preserve the old fast path for the overwhelmingly common empty scope.
  if stack[stack.size() - 1] == nil
    return nil
  emit_recycles_above_depth(f, stack.size() - 1)

-> emit_scope_pop(f, id)
  emit_recycles_for_current_scope(f)
  if f[:scope_recycle_stack].size() > 0
    f[:scope_recycle_stack].pop()
  emit_instruction(f, {op: :scope_pop, id: id})

-> track_recycle_temp(f, temp, kind)
  stack = f[:scope_recycle_stack]
  if stack.size() == 0
    return nil
  idx = stack.size() - 1
  top = stack[idx]
  if top == nil
    top = []
    stack[idx] = top
  # Emit cleanup_push so raise unwind can recycle this value even if normal
  # scope-exit code doesn't run.
  push_op = :cleanup_push_array
  if kind == :hash
    push_op = :cleanup_push_hash
  elsif kind == :typed
    push_op = :cleanup_push_typed
  elsif kind == :strbuf
    push_op = :cleanup_push_strbuf
  emit_instruction(f, {op: push_op, value: temp})
  top.push({temp: temp, kind: kind})

-> block_terminated(f)
  blk = current_block(f)
  instrs = blk[:instructions]
  if instrs.size() == 0
    return false
  last = instrs[instrs.size() - 1]
  op = last[:op]
  op in (:ret_i64 :ret_i32 :ret_void :br :cond_br :switch_i64 :unreachable)

# Remove empty blocks (SSA may leave blocks with no instructions).
# Redirects branches that target empty blocks to the next non-empty block.
-> prune_empty_blocks(f)
  blocks = f[:blocks]
  # Build redirect map: empty block label → next non-empty block label
  redirect = {}
  bi = 0
  while bi < blocks.size()
    if blocks[bi][:instructions].size() == 0
      # Find next non-empty block
      ni = bi + 1
      while ni < blocks.size() && blocks[ni][:instructions].size() == 0
        ni += 1
      if ni < blocks.size()
        redirect[blocks[bi][:label]] = blocks[ni][:label]
    bi += 1
  if redirect.keys().size() == 0
    return nil
  # Rewrite branch targets
  bi = 0
  while bi < blocks.size()
    instrs = blocks[bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      if inst[:label] != nil && redirect[inst[:label]] != nil
        inst[:label] = redirect[inst[:label]]
      if inst[:then_label] != nil && redirect[inst[:then_label]] != nil
        inst[:then_label] = redirect[inst[:then_label]]
      if inst[:else_label] != nil && redirect[inst[:else_label]] != nil
        inst[:else_label] = redirect[inst[:else_label]]
      # Phi incoming labels
      if inst[:incoming] != nil
        pi = 0
        while pi < inst[:incoming].size()
          lbl = inst[:incoming][pi + 1]
          if redirect[lbl] != nil
            inst[:incoming][pi + 1] = redirect[lbl]
          pi += 2
      ii += 1
    bi += 1
  # Remove empty blocks
  new_blocks = []
  bi = 0
  while bi < blocks.size()
    if blocks[bi][:instructions].size() > 0
      new_blocks.push(blocks[bi])
    bi += 1
  f[:blocks] = new_blocks

# -- Loop context --

# Both loop pushes record the exception-frame depth at loop entry so
# break/next can pop the frames of any begin/rescue regions they abandon
# (frames opened inside the loop body enclosing the break/next).
-> push_loop(f, break_label, next_label, redo_label)
  f[:loop_stack].push({break_label: break_label, next_label: next_label, redo_label: redo_label, eh_depth: f[:eh_depth]})

# Structured while/with loops introduce a lexical body scope. Record the
# outer depth so break/next can clean every abandoned body/branch value.
-> push_loop_with_recycle_depth(f, break_label, next_label, redo_label, recycle_depth)
  f[:loop_stack].push({break_label: break_label, next_label: next_label, redo_label: redo_label, recycle_depth: recycle_depth, eh_depth: f[:eh_depth]})

-> pop_loop(f)
  f[:loop_stack].pop()

-> current_loop(f)
  stack = f[:loop_stack]
  if stack.size() == 0
    return nil
  stack[stack.size() - 1]

# -- Case context (for `recase`) --

-> push_case(f, info)
  # Record the exception-frame depth so `recase` (a branch back to the case
  # header) can pop frames of begin regions it abandons within the case arms.
  info[:eh_depth] = f[:eh_depth]
  f[:case_stack].push(info)

-> pop_case(f)
  f[:case_stack].pop()

-> current_case(f)
  stack = f[:case_stack]
  if stack.size() == 0
    return nil
  stack[stack.size() - 1]

# -- Typed values --
# A typed value is {type: :i64 | :i1 | :raw_int | :raw_i64 | :raw_u64 | :raw_i128 | :raw_u128 | :raw_f32 | :raw_f64, value: "%t3" | "42"}

-> typed_value(type, value)
  {type: type, value: value}

-> ensure_i64_value(f, tv)
  if tv[:type] == :i64
    return tv[:value]
  # raw_int -> i64: nanbox int
  if tv[:type] == :raw_int
    temp_masked = next_temp(f)
    temp = next_temp(f)
    emit_instruction(f, {op: :nanbox_int, temp: temp, temp_masked: temp_masked, raw: tv[:value]})
    return temp
  # :char -> i64: nanbox as int (char codepoint fits in i48 trivially).
  # The typed_value's :value is the literal codepoint string, not a temp.
  if tv[:type] == :char
    temp_masked = next_temp(f)
    temp = next_temp(f)
    emit_instruction(f, {op: :nanbox_int, temp: temp, temp_masked: temp_masked, raw: tv[:value]})
    return temp
  # raw_i64 -> i64: box via runtime (promotes to bigint when needed)
  if tv[:type] == :raw_i64
    temp = next_temp(f)
    emit_instruction(f, {op: :call_direct_i64, temp: temp, name: "w_int", args: [tv[:value]]})
    return temp
  # raw_u64 -> i64: box via unsigned runtime bridge
  if tv[:type] == :raw_u64
    temp = next_temp(f)
    emit_instruction(f, {op: :call_direct_i64, temp: temp, name: "w_u64", args: [tv[:value]]})
    return temp
  # raw_i128/raw_u128 -> i64: box via bigint-capable runtime bridges
  if tv[:type] == :raw_i128
    temp = next_temp(f)
    emit_instruction(f, {op: :call_direct_i64, temp: temp, name: "w_i128", args: [tv[:value]], arg_types: ["i128"]})
    return temp
  if tv[:type] == :raw_u128
    temp = next_temp(f)
    emit_instruction(f, {op: :call_direct_i64, temp: temp, name: "w_u128", args: [tv[:value]], arg_types: ["i128"]})
    return temp
  # raw_f32/raw_f64 -> i64: box at the Tungsten value boundary.
  if tv[:type] == :raw_f32
    raw64 = next_temp(f)
    emit_instruction(f, {op: :fpext_f32_f64, temp: raw64, value: tv[:value]})
    temp_bits = next_temp(f)
    temp = next_temp(f)
    emit_instruction(f, {op: :nanbox_float, temp: temp, temp_bits: temp_bits, raw: raw64})
    return temp
  if tv[:type] == :raw_f64
    temp_bits = next_temp(f)
    temp = next_temp(f)
    emit_instruction(f, {op: :nanbox_float, temp: temp, temp_bits: temp_bits, raw: tv[:value]})
    return temp
  # i1 -> i64: nanbox bool (select i1 → W_TRUE/W_FALSE)
  temp = next_temp(f)
  emit_instruction(f, {op: :nanbox_bool, temp: temp, value: tv[:value]})
  temp

-> ensure_i1_value(f, tv)
  if tv[:type] == :i1
    return tv[:value]
  # i64 -> i1: icmp ne 0
  temp = next_temp(f)
  emit_instruction(f, {op: :icmp_ne_zero, temp: temp, value: tv[:value]})
  temp

# -- Finalize --

# Map a recycle-kind symbol to its runtime recycle op. Shared by the
# scope-exit emitter and the per-ret function-scope flush below.
-> recycle_op_for_kind(kind)
  if kind == :hash
    return :call_recycle_hash
  if kind == :typed
    return :call_recycle_typed
  if kind == :strbuf
    return :call_recycle_strbuf
  :call_recycle_array

# Flush the FUNCTION-BODY scope's ## recycle vars before every ret, not just
# the implicit fall-through return. Mirrors the free pass (insert_frees),
# which injects :free_value ahead of each ret for the same reason: an explicit
# `return` terminates its block without running the fall-through recycle code,
# so its pooled buffers leaked. Explicit/early returns carry the function-body
# prefix length captured when emitted; later sibling allocations are therefore
# never inserted on a path where their temps do not dominate. Final/implicit
# returns have no count and use the complete list after lowering. Nested lexical
# values are cleaned at the transfer itself, so the sets do not overlap.
-> insert_function_scope_recycles(f)
  # Preserve the old overwhelmingly-common fast path: no function-body
  # recycle declaration means no ret can carry a function_recycle_count.
  stack = f[:scope_recycle_stack]
  if stack.size() == 0 || stack[0] == nil || stack[0].size() == 0
    return nil
  bi = 0
  while bi < f[:blocks].size()
    instrs = f[:blocks][bi][:instructions]
    new_instrs = []
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      if inst[:op] == :ret_i64 || inst[:op] == :ret_i32 || inst[:op] == :ret_void
        fnbody = stack[0]
        recycle_count = inst[:function_recycle_count]
        if recycle_count == nil
          recycle_count = fnbody.size()
        # LIFO order, matching emit_recycles_for_current_scope.
        if fnbody != nil && recycle_count > 0
          ri = recycle_count - 1
          while ri >= 0
            entry = fnbody[ri]
            new_instrs.push({op: :cleanup_pop})
            new_instrs.push({op: recycle_op_for_kind(entry[:kind]), value: entry[:temp]})
            ri -= 1
      new_instrs.push(inst)
      ii += 1
    f[:blocks][bi][:instructions] = new_instrs
    bi += 1

-> finalize_function(f)
  if !block_terminated(f)
    if f[:return_type] == "i64"
      emit_instruction(f, {op: :ret_i64, value: w_nil.to_s})
    elsif f[:return_type] == "i32"
      emit_instruction(f, {op: :ret_i32, value: "0"})
    else
      emit_instruction(f, {op: :ret_void})
  # Per-ret flush of function-body ## recycle vars (fall-through AND explicit
  # returns). Runs before optimize_function, exactly like the old inline
  # fall-through emit did.
  insert_function_scope_recycles(f)
  optimize_function(f)

# -- Optimization passes --
# Run CSE (store-load forwarding), dead store elimination, and dead alloca
# pruning on each function after lowering. These are block-local passes that
# clean up the store/load/alloca patterns inherent in non-SSA variable slots.

-> optimize_function(f)
  # Pass 1: Store-load forwarding within each basic block. A forwarded
  # load's temp can be USED in a later block (e.g. the fused-pipeline loop
  # body reads a receiver hoisted from the entry block via a raw-text
  # array_get_inline). cse_block only rewrites uses within its own block,
  # so those cross-block uses would dangle once the load is eliminated.
  # Accumulate every forwarding substitution into a function-wide map and
  # reapply it to all blocks below. Sound: the forwarded value is a store
  # earlier in the eliminated load's block, so it dominates the load —
  # hence dominates any block the load's temp reaches in valid SSA.
  global_subst = {}
  i = 0
  while i < f[:blocks].size()
    cse_block(f[:blocks][i], global_subst)
    i += 1

  # Reapply the accumulated substitutions function-wide so cross-block uses
  # of eliminated-load temps get rewritten too. Chains (a → b where b was
  # itself forwarded) are resolved by following the map to a fixpoint.
  if global_subst.keys().size() > 0
    resolved = resolve_subst_chains(global_subst)
    rcount = resolved.keys().size()
    bi = 0
    while bi < f[:blocks].size()
      instrs = f[:blocks][bi][:instructions]
      ii = 0
      while ii < instrs.size()
        instrs[ii] = apply_subst(instrs[ii], resolved, rcount)
        ii += 1
      bi += 1

  # Pass 2: Dead store elimination within each basic block
  i = 0
  while i < f[:blocks].size()
    dead_store_elim(f[:blocks][i])
    i += 1

  # Pass 3: Dead alloca pruning (function-wide)
  prune_dead_allocas(f)

# Follow substitution chains to a fixpoint: if a → b and b → c, map a → c.
# The forwarding map can chain when a load's forwarded value is itself a
# temp that a later same-block load forwarded. Bounded by the map size
# (each step shortens at least one chain); guarded against cycles.
-> resolve_subst_chains(subst)
  resolved = {}
  keys = subst.keys()
  ki = 0
  while ki < keys.size()
    k = keys[ki]
    v = subst[k]
    steps = 0
    while subst[v] != nil && v != subst[v] && steps < 1000
      v = subst[v]
      steps += 1
    resolved[k] = v
    ki += 1
  resolved

# -- Pass 1: Store-load forwarding (CSE) --
# Within a single basic block, track known values after store_i64 instructions.
# When a load_i64 reads from a slot with a known value, eliminate the load and
# substitute the known value into all subsequent uses of the load's temp.

-> cse_block(block, global_subst = nil)
  known = {}
  escaped = {}
  subst = {}
  subst_count = 0
  new_instrs = []

  i = 0
  instrs = block[:instructions]
  while i < instrs.size()
    inst = apply_subst(instrs[i], subst, subst_count)

    if inst[:op] in (:store_i64 :store_i128 :store_float :store_double)
      if escaped[inst[:ptr]] != true
        known[inst[:ptr]] = inst[:value]
      else
        known[inst[:ptr]] = nil
      new_instrs.push(inst)
    elsif inst[:op] in (:load_i64 :load_i128 :load_float :load_double)
      kv = known[inst[:ptr]]
      if kv != nil
        # Value is known — record substitution, skip the load
        subst[inst[:temp]] = kv
        subst_count += 1
        # Also record function-wide so cross-block uses of this temp
        # (which cse_block's local subst never reaches) get rewritten in
        # optimize_function's reapply pass.
        if global_subst != nil
          global_subst[inst[:temp]] = kv
      else
        new_instrs.push(inst)
    elsif inst[:op] == :ptr_to_i64
      # Address-of escape: any pointer whose address is taken can be
      # mutated through aliasing (closures, callee, indirect store). Mark
      # the slot as escaped and drop all known values so subsequent loads
      # always re-fetch from memory.
      escaped[inst[:value]] = true
      known = {}
      new_instrs.push(inst)
    elsif inst[:op] in (:call_direct_i64 :call_direct_i128 :call_direct_void :call_direct_ptr :call_direct_i64_ptr1 :call_direct_void_ptr1 :call_method_i64 :call_indirect_i64 :memo_call0_i64 :memo_call1_i64 :memo_call2_i64 :call_reuse_or_new_array :call_reuse_or_new_hash :call_reuse_or_new_typed :call_reuse_or_new_strbuf :call_reuse_and_drain_or_new_hash :call_recycle_or_new_array :call_recycle_or_new_hash :call_recycle_or_new_typed :call_recycle_or_new_strbuf :call_recycle_array :call_recycle_hash :call_recycle_typed :call_recycle_strbuf)
      # Calls may mutate any escaped slot. Drop known values so subsequent
      # loads observe writes performed by the callee or its closures.
      known = {}
      new_instrs.push(inst)
    else
      new_instrs.push(inst)
    i += 1

  block[:instructions] = new_instrs

# Apply temp substitutions to an instruction's input operands.
# Clones lazily only if a substitution is actually needed.

-> clone_inst(inst)
  result = {}
  keys = inst.keys()
  k = 0
  while k < keys.size()
    result[keys[k]] = inst[keys[k]]
    k += 1
  result

-> apply_subst(inst, subst, subst_count = nil)
  if subst_count == nil
    subst_count = subst.keys().size()
  if subst_count == 0
    return inst
  result = inst
  cloned = false
  val = inst[:value]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:value] = rep
  val = inst[:lhs]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:lhs] = rep
  val = inst[:rhs]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:rhs] = rep
  val = inst[:ptr]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:ptr] = rep
  val = inst[:index]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:index] = rep
  val = inst[:raw]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:raw] = rep
  val = inst[:boxed]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:boxed] = rep
  val = inst[:lhs_boxed]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:lhs_boxed] = rep
  val = inst[:rhs_boxed]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:rhs_boxed] = rep
  val = inst[:cond]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:cond] = rep
  val = inst[:then_val]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:then_val] = rep
  val = inst[:else_val]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:else_val] = rep
  val = inst[:self_reg]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:self_reg] = rep
  val = inst[:receiver]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:receiver] = rep
  val = inst[:super_reg]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:super_reg] = rep
  val = inst[:a_value]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:a_value] = rep
  val = inst[:b_value]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:b_value] = rep
  val = inst[:captures_ptr]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:captures_ptr] = rep
  val = inst[:buf]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:buf] = rep
  val = inst[:class_temp]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:class_temp] = rep
  val = inst[:table]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:table] = rep
  # Inline GEP fields: arr, idx
  val = inst[:arr]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:arr] = rep
  val = inst[:idx]
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:idx] = rep
  # Substitute within s[] scratch array
  sarr = inst[:s]
  if sarr != nil
    new_sarr = nil
    si = 0
    while si < sarr.size()
      sv = sarr[si]
      rep = subst[sv]
      if rep != nil
        if cloned == false
          result = clone_inst(inst)
          cloned = true
        if new_sarr == nil
          new_sarr = []
          ci = 0
          while ci < si
            new_sarr.push(sarr[ci])
            ci += 1
        new_sarr.push(rep)
      elsif new_sarr != nil
        new_sarr.push(sv)
      si += 1
    if new_sarr != nil
      result[:s] = new_sarr
  # Substitute within args array only if needed
  args = inst[:args]
  if args != nil
    new_args = nil
    ai = 0
    while ai < args.size()
      arg = args[ai]
      rep = subst[arg]
      if rep != nil
        if cloned == false
          result = clone_inst(inst)
          cloned = true
        if new_args == nil
          new_args = []
          ci = 0
          while ci < ai
            new_args.push(args[ci])
            ci += 1
        new_args.push(rep)
      elsif new_args != nil
        new_args.push(arg)
      ai += 1
    if new_args != nil
      result[:args] = new_args
  result

# -- Pass 2: Dead store elimination --
# Forward pass: if two stores target the same slot with no intervening load,
# the first store is dead (overwritten before read).

-> dead_store_elim(block)
  prev_store = {}
  dead_set = {}

  i = 0
  instrs = block[:instructions]
  while i < instrs.size()
    inst = instrs[i]
    if inst[:op] in (:store_i64 :store_i128 :store_float :store_double)
      prev = prev_store[inst[:ptr]]
      if prev != nil
        dead_set[prev] = true
      prev_store[inst[:ptr]] = i
    elsif inst[:op] in (:load_i64 :load_i128 :load_float :load_double)
      # Load makes the previous store to this slot live
      prev_store[inst[:ptr]] = nil
    i += 1

  if dead_set.keys().size() == 0
    return

  new_instrs = []
  i = 0
  while i < instrs.size()
    if dead_set[i] != true
      new_instrs.push(instrs[i])
    i += 1
  block[:instructions] = new_instrs

# -- Pass 3: Dead alloca pruning --
# Find var slots that are never loaded (read) in any block. Remove those
# slots from var_slots and strip their orphaned stores.

-> prune_dead_allocas(f)
  # Collect all ptrs that appear in load instructions
  loaded = {}
  i = 0
  while i < f[:blocks].size()
    blk = f[:blocks][i]
    j = 0
    while j < blk[:instructions].size()
      inst = blk[:instructions][j]
      if inst[:op] in (:load_i64 :load_i128 :load_float :load_double)
        loaded[inst[:ptr]] = true
      elsif inst[:op] == :ptr_to_i64
        loaded[inst[:value]] = true
      j += 1
    i += 1

  # Identify dead slots (stored but never loaded)
  dead = {}
  slot_names = f[:var_slots].keys()
  i = 0
  while i < slot_names.size()
    ptr = f[:var_slots][slot_names[i]]
    if ptr.starts_with?("%v") && loaded[ptr] != true
      dead[ptr] = true
    i += 1

  if dead.keys().size() == 0
    return

  # Rebuild var_slots without dead entries
  new_slots = {}
  new_slot_types = {}
  i = 0
  while i < slot_names.size()
    ptr = f[:var_slots][slot_names[i]]
    if dead[ptr] != true
      new_slots[slot_names[i]] = ptr
      if f[:var_slot_types] != nil
        new_slot_types[slot_names[i]] = f[:var_slot_types][slot_names[i]]
    i += 1
  f[:var_slots] = new_slots
  f[:var_slot_types] = new_slot_types

  # Remove orphaned stores to dead slots
  i = 0
  while i < f[:blocks].size()
    blk = f[:blocks][i]
    new_instrs = []
    j = 0
    while j < blk[:instructions].size()
      inst = blk[:instructions][j]
      if ((inst[:op] != :store_i64 && inst[:op] != :store_i128 && inst[:op] != :store_float && inst[:op] != :store_double) || dead[inst[:ptr]] != true)
        new_instrs.push(inst)
      j += 1
    blk[:instructions] = new_instrs
    i += 1
