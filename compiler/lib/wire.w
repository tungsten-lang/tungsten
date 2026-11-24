# WIRE — Tungsten IR data model and function builder
# WIRE is a non-SSA IR using named variable slots with load/store,
# plus SSA-like temps for intermediates. Functions have basic blocks;
# blocks have instruction lists. Instructions are one-word packed handles:
# the kind is embedded in the handle and fields live as symbol/value pairs in
# a resettable bump arena. `[]`/`[]=` remain source-compatible during the
# migration, so CFG/ownership/emission can move independently of lowerers.

use wire_schema
use wire_constructors

-> wire_kind_id(op)
  wire_schema_kind_id(op)

-> wire_kind(instruction)
  sym = ccall_rawargs("w_wire_kind_sym", instruction, wire_kind_symbols)
  if sym != nil
    return sym
  instruction[:op]

-> wire_get(instruction, field)
  ccall_rawargs("w_wire_field_load_nil", instruction, field)

-> wire_set(instruction, field, value)
  ccall_rawargs("w_wire_field_store", instruction, field, value)

-> wire_field_count(instruction)
  ccall_nobox("w_wire_field_count", instruction)

-> wire_field_symbol_at(instruction, index)
  raw_index = ccall_nobox("w_numeric_to_i64", index)
  ccall_rawargs("w_wire_field_symbol_at", instruction, raw_index)

-> wire_field_value_at(instruction, index)
  raw_index = ccall_nobox("w_numeric_to_i64", index)
  ccall_rawargs("w_wire_field_value_at", instruction, raw_index)

# Dense, variable-width instruction operands share the WIRE generation with
# their parent records. nil remains nil; an already-packed sequence passes
# through in the runtime helper. Ordinary Arrays are copied once into the
# bump arena and can then be reclaimed by the compiler's ownership pass.
-> wire_sequence(value)
  if value == nil
    return nil
  ccall_rawargs("w_wire_sequence_from_array", value)

-> wire_sequence_size(value)
  if value == nil
    return 0
  ccall_nobox("w_wire_sequence_size", value)

-> wire_sequence_get(value, index)
  raw_index = ccall_nobox("w_numeric_to_i64", index)
  ccall_rawargs("w_wire_sequence_get", value, raw_index)

-> wire_sequence_set(value, index, item)
  raw_index = ccall_nobox("w_numeric_to_i64", index)
  ccall_rawargs("w_wire_sequence_set", value, raw_index, item)

-> wire_sequence_field?(field)
  field in (:arg_types :args :cases :fields :incoming :s)

-> wire_instruction(instruction)
  if instruction == nil
    return nil
  if ccall_nobox("w_is_wire_extern", instruction) == 1
    return instruction
  if type(instruction) != "Hash"
    return instruction
  op = instruction[:op]
  if op == nil
    return instruction
  # Compatibility callers still receive the same canonical ordinal contract
  # as generated constructors, independent of Hash insertion order.
  keys = instruction.keys().sort()
  kind_id = ccall_nobox("w_numeric_to_i64", wire_kind_id(op))
  field_count = ccall_nobox("w_numeric_to_i64", keys.size())
  handle = ccall_rawargs("w_wire_alloc", kind_id, field_count)
  i = 0
  while i < keys.size()
    key = keys[i]
    value = instruction[key]
    if wire_sequence_field?(key)
      value = wire_sequence(value)
    ccall_nobox("w_wire_field_store_at", handle, i, key, value)
    i += 1
  handle

-> wire_clone_instruction(instruction)
  if ccall_nobox("w_is_wire_extern", instruction) == 1
    return ccall_rawargs("w_wire_clone", instruction)
  instruction

-> wire_record(kind, fields, spare_fields = 2)
  keys = fields.keys()
  kind_id = ccall_nobox("w_numeric_to_i64", wire_kind_id(kind))
  field_count = ccall_nobox("w_numeric_to_i64", keys.size())
  spare_count = ccall_nobox("w_numeric_to_i64", spare_fields)
  handle = ccall_rawargs("w_wire_alloc_reserve", kind_id, field_count, spare_count)
  i = 0
  while i < keys.size()
    key = keys[i]
    ccall_nobox("w_wire_field_store_at", handle, i, key, fields[key])
    i += 1
  handle

# -- Module --

-> wire_module(source_path, retained_wire_mark = 0)
  # One WIRE generation lives through lower -> destructive mid-end -> emit.
  # compile-batch starts the next module only after emission has finished.
  retained_wire_mark_raw = ccall_nobox("w_numeric_to_i64", retained_wire_mark)
  ccall_nobox("w_wire_store_reset", retained_wire_mark_raw)
  wire_record(:wire_module, {
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
    # Inline typed-array accesses carry bounds checks (lower_ast).
    bounds_checks:    false,
    # Module-level names assigned exactly once (collect_top_level_static_types).
    top_level_assign_once: {},
    # Ivars with a write of unknown type (collect_ivar_types).
    ivar_untyped_writes: {},
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
    # Direct-call ABI metadata for top-level definitions with `*rest`.
    # The physical callee slot receives one Array even though the source call
    # may supply any number of arguments at that position.
    known_fn_splat_info: {},
    known_fn_defs: {},
    known_fn_overloads: {},
    known_typed_overload_counts: {},
    known_unique_typed_overload_keys: {},
    known_unique_typed_overload_param_types: {},
    raw_fn_param_kinds: {},
    known_pure_calls: {},
    fn_return_types:  {},
    # Whole-program, bounded source-class return summaries. Filled for locked
    # programs after class registration, before any body is lowered.
    return_class_sets: {},
    return_class_set_workers: {},
    no_raise_workers: {},
    class_methods:    {},
    # Entry-program closed-world contracts. PROTECT_THE_CORE is a validated
    # provenance assertion. STOP_THE_PRESS closes runtime type registration;
    # LOCK_THE_DOORS implies it and also closes method registration.
    protect_core:     false,
    type_tables_locked: false,
    method_tables_locked: false,
    # Filled only for PROTECT_THE_CORE programs. The fingerprint describes
    # the Core-facing WIRE ABI; the reuse contract says whether this program
    # is safe to pair with a warmed Core partition.
    core_reuse_contract: nil,
    core_reuse_fallback_reason: nil,
    core_abi_hash: nil,
    # Process-local immutable Core WIRE reuse. These fields are declared on
    # the module record up front so cache state never depends on late spare
    # field insertion or field-cache collisions.
    incremental_core_cache_probe: nil,
    incremental_core_cache_key: nil,
    incremental_core_cache_entry: nil,
    incremental_core_cache_status: nil,
    incremental_core_cache_persistent_status: nil,
    incremental_core_cache_persistent_stored: nil,
    incremental_core_cache_hit: false,
    incremental_core_cache_closure_files: nil,
    incremental_core_cache_stored: false,
    incremental_core_cache_retain_mark: nil,
    incremental_core_cache_name_map: nil,
    incremental_core_fn_hashes: nil,
    incremental_core_cache_counter_prefix: nil,
    incremental_core_function_count: 0,
    incremental_core_string_count: 0,
    # Raw, pre-mid-end WIRE reuse for a contiguous non-Core library cohort.
    incremental_library_cache_key: nil,
    incremental_library_cache_path: nil,
    incremental_library_cache_paths: nil,
    library_reachability_paths: nil,
    incremental_library_cache_prefix_count: 0,
    incremental_library_cache_string_count: 0,
    incremental_library_cache_compact_string_count: 0,
    incremental_library_cache_file_count: 0,
    incremental_library_cache_context_hash: nil,
    incremental_library_cache_start_hash: nil,
    incremental_library_cache_start_function_count: 0,
    incremental_library_cache_entry: nil,
    incremental_library_cache_status: nil,
    incremental_library_cache_reason: nil,
    incremental_library_cache_hit: false,
    incremental_library_cache_stored: false,
    incremental_library_cache_finished: false,
    incremental_library_cache_function_count: 0,
    # Experimental closed-world emission slice. The complete function graph
    # remains attached for Core-cache finalization; compiler.w swaps this
    # filtered view in only while rendering LLVM.
    core_reachability_status: nil,
    core_reachability_reason: nil,
    core_reachability_emit_functions: nil,
    core_reachability_registration_restore: [],
    core_reachability_early: false,
    content_hash_info_functions: nil,
    core_reachability_total: 0,
    core_reachability_kept: 0,
    core_reachability_pruned: 0,
    library_reachability_total: 0,
    library_reachability_kept: 0,
    library_reachability_pruned: 0,
    content_hash_function_count: 0,
    content_hash_skipped_count: 0,
    cvar_globals:     {},
    fn_memo_tables:   {},
    used_memo_tables: {},
    top_level_vars:   {},
    top_level_var_types: {},
    top_level_static_types: {},
    next_string:      0,
    # One process-lifetime cache slot per source BigInt literal.  The emitted
    # module owns the slots; the runtime publishes an immutable template on
    # first use so loop-local literals replace decimal parsing with a copy.
    next_bigint_literal: 0,
    next_block:       0,
    next_core_block:  0,
    next_ic:          0,
    next_call_site:   0,
    next_fuse_site:   0,
    next_inline_block_id: 0,
    reuse_sites:     [],
    next_reuse_site: 0,
    custom_units:    {},
    # IDs 256..4095 are generated from the Ruby reference unit registry.
    # User-defined/unknown units live above that range and are heap-boxed.
    next_custom_unit_id: 4096,
    # Literal-constant maps (collect_top_level_static_types) and the
    # ownership pass's fresh-result summaries (ownership.w), declared here so
    # they do not draw on the spare slots below.
    top_level_int_literals: nil,
    top_level_wide_int_literals: nil,
    top_level_float_literals: nil,
    fresh_heap_fns: nil,
    fresh_heap_kinds: nil,
    fresh_heap_classes: nil
    # Spare slots for fields first set later in the pipeline. Over 130 such
    # fields exist (many only on some paths), and a program that reaches more
    # of them than there are spares dies in w_wire_field_store ("instruction
    # exhausted spare field slots"); the crypto and wassat bits did at 128.
  }, 256)

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

# Kinds 264..266 are the append-only module/function/block records immediately
# before wire_sequence in wire_schema.w. Their field ordinals are canonical;
# construct them directly so the packed representation never begins as a
# temporary Hash.
wire_function_record_fields = [
  :name, :original_name, :params, :extra_params, :return_type, :is_toplevel,
  :blocks, :var_slots, :var_slot_types, :next_temp, :next_label, :next_var,
  :next_scope, :loop_stack, :eh_depth, :ensure_stack, :case_stack,
  :scope_recycle_stack, :recycle_vars, :dynamic_method_calls,
  :dynamic_method_call_keys, :reflective_method_access, :is_memoized,
  :exit_label, :result_slot
]
wire_block_record_fields = [:label, :instructions]

-> wire_make_function_record(name, params, return_type, is_toplevel, extra_params)
  # The runtime fills the canonical pairs in one C loop and allocates the
  # standard empty child containers. This keeps 25 individual C crossings
  # out of every function definition while field symbols remain generated by
  # this source-level schema.
  ccall_rawargs("w_wire_function_record_new", wire_function_record_fields, name, params, return_type, is_toplevel, extra_params)

-> build_function(name, params, return_type, is_toplevel, extra_params)
  result = wire_make_function_record(name, params, return_type, is_toplevel, extra_params)

  start_block(result, "__entry")
  result

-> wire_record_dynamic_method_call(f, method_name, source_argc)
  runtime_arity = source_argc + 1
  key = method_name + "/" + runtime_arity.to_s()
  if f[:dynamic_method_call_keys][key] != true
    f[:dynamic_method_call_keys][key] = true
    f[:dynamic_method_calls].push({name: method_name, arity: runtime_arity})
  # These methods either invoke an arbitrary name or make the method-table
  # contents observable. A reachability slice must retain the full table when
  # any live body uses one of them.
  if method_name in ("respond_to?" "__send__" "method" "methods" "instance_method" "instance_methods" "public_instance_method" "public_instance_methods" "private_instance_methods" "protected_instance_methods" "method_defined?" "private_method?" "protected_method?" "public_method?" "singleton_methods")
    f[:reflective_method_access] = true
  nil

-> build_wire_temp_names
  a = []
  i = 0
  while i < 4096
    a.push("%t" + i.to_s())
    i += 1
  a

wire_temp_names = build_wire_temp_names()

-> build_wire_var_slot_names
  a = []
  i = 0
  while i < 512
    a.push("%vs." + i.to_s())
    i += 1
  a

wire_var_slot_names = build_wire_var_slot_names()

-> next_temp(f)
  n = f[:next_temp]
  f[:next_temp] = n + 1
  if n >= 0 && n < 4096
    return wire_temp_names[n]
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
  ptr = nil
  if n >= 0 && n < 512
    ptr = wire_var_slot_names[n]
  else
    ptr = "%vs." + n.to_s()
  f[:var_slots][name] = ptr
  f[:var_slot_types][name] = slot_type
  ptr

# -- Basic blocks --

-> start_block(f, label)
  f[:blocks].push(ccall_rawargs("w_wire_block_record_new", wire_block_record_fields, label))

-> current_block(f)
  f[:blocks][f[:blocks].size() - 1]

-> emit_instruction(f, instruction)
  current_block(f)[:instructions].push(wire_instruction(instruction))

# The most recently emitted instruction of the current block, or nil for an
# empty block. Lets a lowerer inspect what an operand's lowering actually
# produced (e.g. the fresh-string proof for w_str_concat_free_rhs).
-> last_emitted_instruction(f)
  instrs = current_block(f)[:instructions]
  if instrs.size() == 0
    return nil
  instrs[instrs.size() - 1]

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
  if ccall_nobox("w_is_wire_extern", instruction) == 1
    wire_set(instruction, :function_recycle_count, count)
  else
    instruction[:function_recycle_count] = count
  emit_instruction(f, instruction)

# -- Scope-aware push/pop with ## recycle tracking --
# Each scope's recycle-tracked vars are emitted as w_*_recycle calls before
# scope_pop. The top of scope_recycle_stack is the current scope's list.

-> emit_scope_push(f, id)
  emit_wire_scope_push(f, id)
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
        emit_wire_cleanup_pop(f)
        emit_recycle_for_kind(f, entry[:kind], entry[:temp])
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
  emit_wire_scope_pop(f, id)

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
  if kind == :hash
    emit_wire_cleanup_push_hash(f, temp)
  elsif kind == :typed
    emit_wire_cleanup_push_typed(f, temp)
  elsif kind == :strbuf
    emit_wire_cleanup_push_strbuf(f, temp)
  else
    emit_wire_cleanup_push_array(f, temp)
  top.push({temp: temp, kind: kind})

-> block_terminated(f)
  blk = current_block(f)
  instrs = blk[:instructions]
  if instrs.size() == 0
    return false
  last = instrs[instrs.size() - 1]
  op = wire_kind(last)
  op in (:ret_i64 :ret_i32 :ret_void :br :cond_br :switch_i64 :unreachable)

# Remove empty blocks (SSA may leave blocks with no instructions).
# Redirects branches that target empty blocks to the next non-empty block.
-> prune_empty_blocks(f)
  blocks = f[:blocks]
  # Build redirect map: empty block label → next non-empty block label
  redirect = {}
  has_redirect = false
  bi = 0
  while bi < blocks.size()
    if blocks[bi][:instructions].size() == 0
      # Find next non-empty block
      ni = bi + 1
      while ni < blocks.size() && blocks[ni][:instructions].size() == 0
        ni += 1
      if ni < blocks.size()
        redirect[blocks[bi][:label]] = blocks[ni][:label]
        has_redirect = true
    bi += 1
  if !has_redirect
    return nil
  # Rewrite branch targets
  bi = 0
  while bi < blocks.size()
    instrs = blocks[bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      op = wire_kind(inst)
      if op == :br
        lbl = wire_get(inst, :label)
        if lbl != nil && redirect[lbl] != nil
          wire_set(inst, :label, redirect[lbl])
      elsif op == :cond_br
        tlbl = wire_get(inst, :then_label)
        if tlbl != nil && redirect[tlbl] != nil
          wire_set(inst, :then_label, redirect[tlbl])
        elbl = wire_get(inst, :else_label)
        if elbl != nil && redirect[elbl] != nil
          wire_set(inst, :else_label, redirect[elbl])
      elsif op == :switch_i64
        dlbl = wire_get(inst, :default_label)
        if dlbl != nil && redirect[dlbl] != nil
          wire_set(inst, :default_label, redirect[dlbl])
        cases = wire_get(inst, :cases)
        if cases != nil
          ci = 0
          while ci < wire_sequence_size(cases)
            c = wire_sequence_get(cases, ci)
            clbl = c[:label]
            if clbl != nil && redirect[clbl] != nil
              c[:label] = redirect[clbl]
            ci += 1
      elsif op == :phi_ssa
        # Phi incoming labels
        incoming = wire_get(inst, :incoming)
        if incoming != nil
          pi = 0
          while pi < wire_sequence_size(incoming)
            lbl = wire_sequence_get(incoming, pi + 1)
            if redirect[lbl] != nil
              wire_sequence_set(incoming, pi + 1, redirect[lbl])
            pi += 2
      ii += 1
    bi += 1
  # Remove empty blocks
  new_blocks = []
  bi = 0
  while bi < blocks.size()
    if blocks[bi][:instructions].size() > 0 || redirect[blocks[bi][:label]] == nil
      new_blocks.push(blocks[bi])
    bi += 1
  f[:blocks] = new_blocks

# -- Loop context --

# Both loop pushes record the exception-frame depth and ensure-region depth
# at loop entry so break/next can pop the frames of any begin/rescue regions
# they abandon and run the ensure bodies of those regions (regions opened
# inside the loop body enclosing the break/next).
-> push_loop(f, break_label, next_label, redo_label)
  f[:loop_stack].push({break_label: break_label, next_label: next_label, redo_label: redo_label, eh_depth: f[:eh_depth], ensure_base: f[:ensure_stack].size()})

# Structured while/with loops introduce a lexical body scope. Record the
# outer depth so break/next can clean every abandoned body/branch value.
-> push_loop_with_recycle_depth(f, break_label, next_label, redo_label, recycle_depth)
  f[:loop_stack].push({break_label: break_label, next_label: next_label, redo_label: redo_label, recycle_depth: recycle_depth, eh_depth: f[:eh_depth], ensure_base: f[:ensure_stack].size()})

-> pop_loop(f)
  f[:loop_stack].pop()

-> current_loop(f)
  stack = f[:loop_stack]
  if stack.size() == 0
    return nil
  stack[stack.size() - 1]

# -- Case context (for `recase`) --

-> push_case(f, info)
  # Record the exception-frame and ensure-region depths so `recase` (a branch
  # back to the case header) can pop frames of begin regions it abandons
  # within the case arms and run their ensure bodies.
  info[:eh_depth] = f[:eh_depth]
  info[:ensure_base] = f[:ensure_stack].size()
  f[:case_stack].push(info)

-> pop_case(f)
  f[:case_stack].pop()

-> current_case(f)
  stack = f[:case_stack]
  if stack.size() == 0
    return nil
  stack[stack.size() - 1]

# -- Typed values --
# A typed value has fixed :type/:value slots in the WIRE arena. Lowering
# creates many thousands of these short-lived pairs during a
# self-compile; a Hash allocated a table and canonicalized the same two keys
# for every expression. Kind 268 is append-only in wire_schema.w, immediately
# after the stable wire_sequence kind (267).

-> typed_value(type, value)
  ccall_rawargs("w_wire_packed_2", 268, type, value)

-> is_i48_decimal_literal?(s, signed = true)
  if s == nil
    return false
  n = s.size()
  if n == 0 || n > 16
    return false
  i = 0
  neg = false
  b0 = s.byte_at(0)
  if b0 == 45
    if !signed || n == 1
      return false
    neg = true
    i = 1
  elsif b0 < 48 || b0 > 57
    return false
  while i < n
    b = s.byte_at(i)
    if b < 48 || b > 57
      return false
    i += 1
  digits = neg ? n - 1 : n
  if digits <= 14
    return true
  if digits > 15
    return false
  iv = s.to_i()
  if signed
    return iv >= -140737488355328 && iv <= 140737488355327
  iv >= 0 && iv <= 140737488355327

-> ensure_i64_value(f, tv)
  if tv[:type] == :i64
    return tv[:value]
  # raw_int -> i64: nanbox int
  if tv[:type] == :raw_int
    temp_masked = next_temp(f)
    temp = next_temp(f)
    emit_wire_nanbox_int(f, tv[:value], temp, temp_masked)
    return temp
  # :char -> i64: nanbox as int (char codepoint fits in i48 trivially).
  # The typed_value's :value is the literal codepoint string, not a temp.
  if tv[:type] == :char
    temp_masked = next_temp(f)
    temp = next_temp(f)
    emit_wire_nanbox_int(f, tv[:value], temp, temp_masked)
    return temp
  # raw_i64 -> i64: fold decimal literals that fit in signed i48 straight to
  # nanbox_int (constant-folded at emit time); runtime values box via the
  # inline-fast wrapper (fitting values box inline; >i48 promotes to BigInt).
  if tv[:type] == :raw_i64
    if is_i48_decimal_literal?(tv[:value], true)
      temp_masked = next_temp(f)
      temp = next_temp(f)
      emit_wire_nanbox_int(f, tv[:value], temp, temp_masked)
      return temp
    temp = next_temp(f)
    emit_wire_call_direct_i64(f, nil, [tv[:value]], nil, nil, "__w_int_fast", nil, nil, temp)
    return temp
  # raw_u64 -> i64: fold non-negative i48-fitting literals; otherwise unsigned bridge
  if tv[:type] == :raw_u64
    if is_i48_decimal_literal?(tv[:value], false)
      temp_masked = next_temp(f)
      temp = next_temp(f)
      emit_wire_nanbox_int(f, tv[:value], temp, temp_masked)
      return temp
    temp = next_temp(f)
    emit_wire_call_direct_i64(f, nil, [tv[:value]], nil, nil, "w_u64", nil, nil, temp)
    return temp
  # raw_i128/raw_u128 -> i64: box via bigint-capable runtime bridges
  if tv[:type] == :raw_i128
    temp = next_temp(f)
    emit_wire_call_direct_i64(f, ["i128"], [tv[:value]], nil, nil, "w_i128", nil, nil, temp)
    return temp
  if tv[:type] == :raw_u128
    temp = next_temp(f)
    emit_wire_call_direct_i64(f, ["i128"], [tv[:value]], nil, nil, "w_u128", nil, nil, temp)
    return temp
  # raw_f32/raw_f64 -> i64: box at the Tungsten value boundary.
  if tv[:type] == :raw_f32
    raw64 = next_temp(f)
    emit_wire_fpext_f32_f64(f, raw64, tv[:value])
    temp_bits = next_temp(f)
    temp = next_temp(f)
    emit_wire_nanbox_float(f, raw64, temp, temp_bits)
    return temp
  if tv[:type] == :raw_f64
    temp_bits = next_temp(f)
    temp = next_temp(f)
    emit_wire_nanbox_float(f, tv[:value], temp, temp_bits)
    return temp
  # Aggregate/static receiver types (typed arrays, specialized classes, and
  # similar inference-only symbols) still carry an ordinary boxed i64 WValue.
  # Only :i1 needs conversion here; treating every unrecognized static type as
  # a predicate emitted `select i1` over array/object registers.
  if tv[:type] != :i1
    return tv[:value]
  # i1 -> i64: nanbox bool (select i1 → W_TRUE/W_FALSE)
  temp = next_temp(f)
  emit_wire_nanbox_bool(f, temp, tv[:value])
  temp

-> ensure_i1_value(f, tv)
  if tv[:type] == :i1
    return tv[:value]
  # i64 -> i1: icmp ne 0
  temp = next_temp(f)
  emit_wire_icmp_ne_zero(f, temp, tv[:value])
  temp

# -- Finalize --

# Map a recycle-kind symbol to its runtime recycle op. Shared by the
# scope-exit emitter and the per-ret function-scope flush below.
-> wire_make_recycle_for_kind(kind, value)
  if kind == :hash
    return wire_make_call_recycle_hash(value)
  if kind == :typed
    return wire_make_call_recycle_typed(value)
  if kind == :strbuf
    return wire_make_call_recycle_strbuf(value)
  wire_make_call_recycle_array(value)

-> emit_recycle_for_kind(f, kind, value)
  ccall_rawargs("w_wire_func_push_inst", f, wire_make_recycle_for_kind(kind, value))

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
      op = wire_kind(inst)
      if op == :ret_i64 || op == :ret_i32 || op == :ret_void
        fnbody = stack[0]
        recycle_count = wire_get(inst, :function_recycle_count)
        if recycle_count == nil
          recycle_count = fnbody.size()
        # LIFO order, matching emit_recycles_for_current_scope.
        if fnbody != nil && recycle_count > 0
          ri = recycle_count - 1
          while ri >= 0
            entry = fnbody[ri]
            new_instrs.push(wire_make_cleanup_pop())
            new_instrs.push(wire_make_recycle_for_kind(entry[:kind], entry[:temp]))
            ri -= 1
      new_instrs.push(inst)
      ii += 1
    f[:blocks][bi][:instructions] = new_instrs
    bi += 1

-> finalize_function(f)
  if !block_terminated(f)
    if f[:return_type] == "i64"
      emit_wire_ret_i64(f, nil, w_nil.to_s)
    elsif f[:return_type] == "i32"
      emit_wire_ret_i32(f, "0")
    else
      emit_wire_ret_void(f)
  # Per-ret flush of function-body ## recycle vars (fall-through AND explicit
  # returns). Runs before optimize_function, exactly like the old inline
  # fall-through emit did.
  insert_function_scope_recycles(f)
  optimize_function(f)

# -- Optimization passes --
# Run CSE (store-load forwarding), dead store elimination, and dead alloca
# pruning on each function after lowering. These are block-local passes that
# clean up the store/load/alloca patterns inherent in non-SSA variable slots.

-> wire_slot_store_type(op)
  if op == :store_i64
    return :i64
  if op == :store_double
    return :f64
  if op == :store_float
    return :f32
  if op == :store_i128
    return :i128
  nil

-> wire_slot_load_type(op)
  if op == :load_i64
    return :i64
  if op == :load_double
    return :f64
  if op == :load_float
    return :f32
  if op == :load_i128
    return :i128
  nil

-> wire_is_call_op?(op)
  op in (:call_direct_i64 :call_direct_i128 :call_direct_void :call_direct_ptr :call_direct_i64_ptr1 :call_direct_void_ptr1 :call_method_i64 :call_indirect_i64 :memo_call0_i64 :memo_call1_i64 :memo_call2_i64 :call_reuse_or_new_array :call_reuse_or_new_hash :call_reuse_or_new_typed :call_reuse_or_new_strbuf :call_reuse_and_drain_or_new_hash :call_recycle_or_new_array :call_recycle_or_new_hash :call_recycle_or_new_typed :call_recycle_or_new_strbuf :call_recycle_array :call_recycle_hash :call_recycle_typed :call_recycle_strbuf)

-> init_wire_call_kind_table()
  tbl = Array.new(WIRE_KIND_MAX + 1)
  call_ids = [
    WIRE_KIND_CALL_DIRECT_I64, WIRE_KIND_CALL_DIRECT_I128, WIRE_KIND_CALL_DIRECT_VOID,
    WIRE_KIND_CALL_DIRECT_PTR, WIRE_KIND_CALL_DIRECT_I64_PTR1, WIRE_KIND_CALL_DIRECT_VOID_PTR1,
    WIRE_KIND_CALL_METHOD_I64,
    WIRE_KIND_MEMO_CALL0_I64, WIRE_KIND_MEMO_CALL1_I64, WIRE_KIND_MEMO_CALL2_I64,
    WIRE_KIND_CALL_REUSE_OR_NEW_ARRAY, WIRE_KIND_CALL_REUSE_OR_NEW_HASH,
    WIRE_KIND_CALL_REUSE_OR_NEW_TYPED, WIRE_KIND_CALL_REUSE_OR_NEW_STRBUF,
    WIRE_KIND_CALL_REUSE_AND_DRAIN_OR_NEW_HASH,
    WIRE_KIND_CALL_RECYCLE_OR_NEW_ARRAY, WIRE_KIND_CALL_RECYCLE_OR_NEW_HASH,
    WIRE_KIND_CALL_RECYCLE_OR_NEW_TYPED, WIRE_KIND_CALL_RECYCLE_OR_NEW_STRBUF,
    WIRE_KIND_CALL_RECYCLE_ARRAY, WIRE_KIND_CALL_RECYCLE_HASH,
    WIRE_KIND_CALL_RECYCLE_TYPED, WIRE_KIND_CALL_RECYCLE_STRBUF
  ]
  i = 0
  while i < call_ids.size()
    tbl[call_ids[i]] = true
    i += 1
  tbl

wire_call_kind_table = init_wire_call_kind_table()

-> wire_collect_fn_escape_and_setjmp(f)
  fn_escaped = {}
  fn_has_setjmp = false
  heap_slots = f[:heap_slot_names]
  if heap_slots != nil && f[:var_slots] != nil
    hnames = heap_slots.keys()
    hi = 0
    while hi < hnames.size()
      if heap_slots[hnames[hi]] == true
        hp = f[:var_slots][hnames[hi]]
        if hp != nil
          fn_escaped[hp] = true
      hi += 1
  bi = 0
  blocks = f[:blocks]
  while bi < blocks.size()
    instrs = blocks[bi][:instructions]
    ii = 0
    n_instrs = instrs.size()
    while ii < n_instrs
      inst = instrs[ii]
      kid = ccall_nobox("w_wire_kind_extern", inst) ## i64
      case kid
      when WIRE_KIND_PTR_TO_I64
        v = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PTR_TO_I64_VALUE)
        if v != nil
          fn_escaped[v] = true
      when WIRE_KIND_SETJMP
        fn_has_setjmp = true
        b = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_SETJMP_BUF)
        if b != nil
          fn_escaped[b] = true
      when WIRE_KIND_CALL_DIRECT_I64_PTR1, WIRE_KIND_CALL_DIRECT_VOID_PTR1
        a = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_PTR1_ARG)
        if a != nil
          fn_escaped[a] = true
      when WIRE_KIND_STORE_PTR
        d = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_PTR_DEST)
        if d != nil
          fn_escaped[d] = true
      when WIRE_KIND_GEP_ARRAY
        gb = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_GEP_ARRAY_BASE)
        if gb != nil
          fn_escaped[gb] = true
      when WIRE_KIND_CALL_DIRECT_I64
        args = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_ARGS)
        if args != nil
          ai = 0
          nargs = wire_sequence_size(args)
          while ai < nargs
            arg = wire_sequence_get(args, ai)
            if arg != nil && arg.starts_with?("%v")
              fn_escaped[arg] = true
            ai += 1
      when WIRE_KIND_CALL_DIRECT_VOID, WIRE_KIND_CALL_DIRECT_PTR
        args = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_VOID_ARGS)
        if args != nil
          ai = 0
          nargs = wire_sequence_size(args)
          while ai < nargs
            arg = wire_sequence_get(args, ai)
            if arg != nil && arg.starts_with?("%v")
              fn_escaped[arg] = true
            ai += 1
      when WIRE_KIND_CALL_DIRECT_I128
        args = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I128_ARGS)
        if args != nil
          ai = 0
          nargs = wire_sequence_size(args)
          while ai < nargs
            arg = wire_sequence_get(args, ai)
            if arg != nil && arg.starts_with?("%v")
              fn_escaped[arg] = true
            ai += 1
      ii += 1
    bi += 1
  {escaped: fn_escaped, has_setjmp: fn_has_setjmp}

-> wire_try_fold_box_call(f, inst)
  kid = ccall_nobox("w_wire_kind_extern", inst) ## i64
  if kid != WIRE_KIND_CALL_DIRECT_I64
    return inst
  nm = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_NAME)
  if nm != "__w_int_fast" && nm != "w_u64"
    return inst
  if ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_ARG_TYPES) != nil || ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_SRC_LINE) != nil
    return inst
  args = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_ARGS)
  if args == nil || wire_sequence_size(args) != 1
    return inst
  a0 = wire_sequence_get(args, 0)
  if !is_i48_decimal_literal?(a0, nm == "__w_int_fast")
    return inst
  temp = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_TEMP)
  tm = f != nil ? next_temp(f) : (temp + ".m")
  wire_make_nanbox_int(a0, temp, tm)

-> optimize_function(f)
  # Precompute function-wide address-escaped slots and setjmp presence so
  # block-local CSE can safely retain unescaped local `%v*` slots across
  # calls (and DSE can stay conservative around raising calls under setjmp).
  fn_info = wire_collect_fn_escape_and_setjmp(f)
  fn_escaped = fn_info[:escaped]
  fn_has_setjmp = fn_info[:has_setjmp]

  # Pass 1: Store-load and load-load forwarding within each basic block. A
  # forwarded load's temp can be USED in a later block (e.g. the fused-pipeline
  # loop body reads a receiver hoisted from the entry block via a raw-text
  # array_get_inline). cse_block only rewrites uses within its own block, so
  # those cross-block uses would dangle once the load is eliminated. Accumulate
  # every forwarding substitution into a function-wide map and reapply it to
  # all blocks below. Sound: the forwarded value dominates the eliminated load,
  # hence dominates any block the load's temp reaches in valid SSA.
  global_subst = {}
  i = 0
  while i < f[:blocks].size()
    cse_block(f[:blocks][i], global_subst, fn_escaped, fn_has_setjmp, f)
    i += 1

  # Reapply the accumulated substitutions function-wide so cross-block uses
  # of eliminated-load temps get rewritten too. Chains (a → b where b was
  # itself forwarded) are resolved by following the map to a fixpoint.
  if global_subst.size() > 0
    resolved = resolve_subst_chains(global_subst)
    rcount = resolved.size()
    bi = 0
    while bi < f[:blocks].size()
      instrs = f[:blocks][bi][:instructions]
      ii = 0
      while ii < instrs.size()
        instrs[ii] = wire_try_fold_box_call(f, apply_subst(instrs[ii], resolved, rcount))
        ii += 1
      bi += 1

  # Pass 2: Dead store elimination within each basic block
  i = 0
  while i < f[:blocks].size()
    dead_store_elim(f[:blocks][i], fn_escaped, fn_has_setjmp)
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

# -- Pass 1: Store-load and load-load forwarding (CSE) --
# Within a single basic block, track known values and their slot types after
# store_* and load_* instructions. When a load_* reads from a slot with a
# matching-type known value, eliminate the load and substitute the known value
# into all subsequent uses of the load's temp. Unescaped local stack slots
# (`%v*` not in fn_escaped) survive calls when the function has no setjmp.

-> wire_array_alloc_ebits_spec(cname, cargs)
  if cname == "w_bytes_new"
    return ":8:0"
  if cname in ("w_array_zeros" "w_array_new_uninit" "w_array_new_uninit_sized") && cargs != nil && wire_sequence_size(cargs) >= 1
    eb = wire_sequence_get(cargs, 0)
    if eb in ("64" "66" "-64")
      return ":64:0"
    if eb in ("32" "33" "-32")
      return ":32:0"
    if eb in ("16" "116" "-16" "-116")
      return ":16:0"
    if eb in ("8" "108" "-108" "-109")
      return ":8:0"
    if eb in ("4" "-4" "-104")
      return ":4:0"
    if eb == "65"
      return ":64:1"
  nil

-> cse_block(block, global_subst = nil, fn_escaped = nil, fn_has_setjmp = false, f = nil)
  known = {}
  known_type = {}
  has_known = false
  has_non_slot_known = false
  escaped = {}
  checked_ebits = nil
  subst = {}
  subst_count = 0
  new_instrs = []

  i = 0
  instrs = block[:instructions]
  n_instrs = instrs.size()
  while i < n_instrs
    inst = instrs[i]
    if subst_count > 0
      inst = wire_try_fold_box_call(f, apply_subst(inst, subst, subst_count))
    kid = ccall_nobox("w_wire_kind_extern", inst) ## i64

    st_type = nil
    if kid == WIRE_KIND_STORE_I64
      st_type = :i64
    elsif kid == WIRE_KIND_STORE_DOUBLE
      st_type = :f64
    elsif kid == WIRE_KIND_STORE_FLOAT
      st_type = :f32
    elsif kid == WIRE_KIND_STORE_I128
      st_type = :i128
    if st_type != nil
      ptr = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_I64_PTR)
      is_esc = escaped[ptr] == true || (fn_escaped != nil && fn_escaped[ptr] == true)
      if !is_esc
        known[ptr] = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_I64_VALUE)
        known_type[ptr] = st_type
        has_known = true
        if !ptr.starts_with?("%v")
          has_non_slot_known = true
      elsif has_known
        known[ptr] = nil
        known_type[ptr] = nil
      new_instrs.push(inst)
    else
      ld_type = nil
      if kid == WIRE_KIND_LOAD_I64
        ld_type = :i64
      elsif kid == WIRE_KIND_LOAD_DOUBLE
        ld_type = :f64
      elsif kid == WIRE_KIND_LOAD_FLOAT
        ld_type = :f32
      elsif kid == WIRE_KIND_LOAD_I128
        ld_type = :i128
      if ld_type != nil
        ptr = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_I64_PTR)
        kv = nil
        if has_known && known_type[ptr] == ld_type
          kv = known[ptr]
        if kv != nil
          # Value is known with matching slot type — record substitution, skip the load
          temp = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_I64_TEMP)
          subst[temp] = kv
          subst_count += 1
          # Also record function-wide so cross-block uses of this temp
          # (which cse_block's local subst never reaches) get rewritten in
          # optimize_function's reapply pass.
          if global_subst != nil
            global_subst[temp] = kv
        else
          new_instrs.push(inst)
          # Load-load CSE: remember this loaded value for later same-BB loads
          # from the same unescaped slot.
          is_esc = escaped[ptr] == true || (fn_escaped != nil && fn_escaped[ptr] == true)
          if !is_esc
            known[ptr] = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_I64_TEMP)
            known_type[ptr] = ld_type
            has_known = true
            if !ptr.starts_with?("%v")
              has_non_slot_known = true
      elsif kid == WIRE_KIND_PTR_TO_I64
        # Address-of escape: any pointer whose address is taken can be
        # mutated through aliasing (closures, callee, indirect store). Mark
        # the slot as escaped and drop all known values so subsequent loads
        # always re-fetch from memory.
        escaped[ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PTR_TO_I64_VALUE)] = true
        if has_known
          known = {}
          known_type = {}
          has_known = false
          has_non_slot_known = false
        new_instrs.push(inst)
      else
        if kid == WIRE_KIND_CALL_DIRECT_I64
          cname = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_NAME)
          if cname == "w_check_array_ebits"
            cargs = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_ARGS)
            if cargs != nil && wire_sequence_size(cargs) >= 3
              arr_reg = wire_sequence_get(cargs, 0)
              eb_suffix = ":" + wire_sequence_get(cargs, 1) + ":" + wire_sequence_get(cargs, 2)
              eb_key = arr_reg + eb_suffix
              if checked_ebits != nil && checked_ebits[eb_key] == true
                temp = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_TEMP)
                subst[temp] = arr_reg
                subst_count += 1
                if global_subst != nil
                  global_subst[temp] = arr_reg
                i += 1
                next
              if checked_ebits == nil
                checked_ebits = {}
              checked_ebits[eb_key] = true
              checked_ebits[ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_TEMP) + eb_suffix] = true
          elsif cname == "w_array_zeros" || cname == "w_array_new_uninit" || cname == "w_array_new_uninit_sized" || cname == "w_bytes_new"
            spec = wire_array_alloc_ebits_spec(cname, ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_ARGS))
            if spec != nil
              if checked_ebits == nil
                checked_ebits = {}
              checked_ebits[ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_CALL_DIRECT_I64_TEMP) + spec] = true
        if has_known && (kid == WIRE_KIND_STORE_PTR || (kid > 0 && kid <= WIRE_KIND_MAX && wire_call_kind_table[kid] == true))
          if fn_has_setjmp || fn_escaped == nil
            # Conservative under setjmp (or standalone cse_block without fn_escaped):
            # drop all known values across calls.
            known = {}
            known_type = {}
            has_known = false
            has_non_slot_known = false
          elsif has_non_slot_known
            # Unescaped local `%v*` slots cannot be aliased by callees or indirect
            # stores; drop only non-slot pointers.
            kkeys = known.keys()
            ki = 0
            kept = false
            while ki < kkeys.size()
              kp = kkeys[ki]
              if known[kp] != nil
                if !kp.starts_with?("%v")
                  known[kp] = nil
                  known_type[kp] = nil
                else
                  kept = true
              ki += 1
            has_known = kept
            has_non_slot_known = false
        new_instrs.push(inst)
    i += 1

  block[:instructions] = new_instrs

# Apply temp substitutions to an instruction's input operands.
# Clones lazily only if a substitution is actually needed.

-> wire_mark_used_temps(inst, targets, live)
  fc = wire_field_count(inst)
  fi = 0
  while fi < fc
    sym = wire_field_symbol_at(inst, fi)
    if !(sym in (:temp :temp_masked :temp_shl :temp_bits :temp_ptr :temp_args_val :arg_types :cases))
      val = wire_field_value_at(inst, fi)
      if val != nil
        if wire_sequence_field?(sym)
          sn = wire_sequence_size(val)
          si = 0
          while si < sn
            elt = wire_sequence_get(val, si)
            if elt != nil && targets[elt] == true
              live[elt] = true
            si += 1
        elsif targets[val] == true
          live[val] = true
    fi += 1
  nil

-> clone_inst(inst)
  if ccall_nobox("w_is_wire_extern", inst) == 1
    return ccall_rawargs("w_wire_clone", inst)
  result = {}
  keys = inst.keys()
  k = 0
  while k < keys.size()
    result[keys[k]] = inst[keys[k]]
    k += 1
  result

-> apply_subst(inst, subst, subst_count = nil)
  if subst_count == nil
    subst_count = subst.size()
  if subst_count == 0
    return inst
  if runtime_identity() == "compiled-runtime" && ccall_nobox("w_is_wire_extern", inst) == 1
    return ccall_rawargs("w_wire_apply_subst", inst, subst)
  op = wire_kind(inst)
  # Fast-path the hottest opcodes in frequency order.
  if op == :call_direct_i64 || op == :call_direct_void || op == :call_direct_ptr || op == :call_direct_i128
    args = wire_get(inst, :args)
    if args != nil
      result = inst
      cloned = false
      new_args = nil
      ai = 0
      while ai < wire_sequence_size(args)
        arg = wire_sequence_get(args, ai)
        rep = subst[arg]
        if rep != nil
          if cloned == false
            result = clone_inst(inst)
            cloned = true
          if new_args == nil
            new_args = []
            ci = 0
            while ci < ai
              new_args.push(wire_sequence_get(args, ci))
              ci += 1
          new_args.push(rep)
        elsif new_args != nil
          new_args.push(arg)
        ai += 1
      if new_args != nil
        wire_set(result, :args, wire_sequence(new_args))
      return result
    return inst
  if op == :load_i64 || op == :load_double || op == :load_float || op == :load_i128
    val = wire_get(inst, :ptr)
    if val != nil
      rep = subst[val]
      if rep != nil
        result = clone_inst(inst)
        wire_set(result, :ptr, rep)
        return result
    return inst
  if op == :store_i64 || op == :store_double || op == :store_float || op == :store_i128
    result = inst
    cloned = false
    val = wire_get(inst, :value)
    if val != nil
      rep = subst[val]
      if rep != nil
        result = clone_inst(inst)
        cloned = true
        wire_set(result, :value, rep)
    val = wire_get(inst, :ptr)
    if val != nil
      rep = subst[val]
      if rep != nil
        if cloned == false
          result = clone_inst(inst)
        wire_set(result, :ptr, rep)
    return result
  if op == :br || op == :ret_void || op == :string_i64 || op == :symbol_i64 || op == :call_loc_set_col || op == :load_class || op == :load_global || op == :const_float
    return inst
  if op == :cond_br
    val = wire_get(inst, :cond)
    if val != nil
      rep = subst[val]
      if rep != nil
        result = clone_inst(inst)
        wire_set(result, :cond, rep)
        return result
    return inst
  if op == :ret_i64 || op == :switch_i64 || op == :icmp_ne_zero || op == :not_i1 || op == :nanbox_bool || op == :truthy_inline || op == :free_value || op == :ptr_to_i64 || op == :i64_to_ptr
    val = wire_get(inst, :value)
    if val != nil
      rep = subst[val]
      if rep != nil
        result = clone_inst(inst)
        wire_set(result, :value, rep)
        return result
    return inst
  if op == :phi_ssa
    inc = wire_get(inst, :incoming)
    if inc != nil
      result = inst
      cloned = false
      new_inc = nil
      n_inc = wire_sequence_size(inc)
      ii = 0
      while ii < n_inc
        val = wire_sequence_get(inc, ii)
        rep = subst[val]
        if rep != nil
          if cloned == false
            result = clone_inst(inst)
            cloned = true
          if new_inc == nil
            new_inc = []
            ci = 0
            while ci < ii
              new_inc.push(wire_sequence_get(inc, ci))
              ci += 1
          new_inc.push(rep)
          new_inc.push(wire_sequence_get(inc, ii + 1))
        elsif new_inc != nil
          new_inc.push(val)
          new_inc.push(wire_sequence_get(inc, ii + 1))
        ii += 2
      if new_inc != nil
        wire_set(result, :incoming, wire_sequence(new_inc))
      return result
    return inst
  if op == :call_method_i64
    result = inst
    cloned = false
    val = wire_get(inst, :receiver)
    if val != nil
      rep = subst[val]
      if rep != nil
        result = clone_inst(inst)
        cloned = true
        wire_set(result, :receiver, rep)
    val = wire_get(inst, :method_name_val)
    if val != nil
      rep = subst[val]
      if rep != nil
        if cloned == false
          result = clone_inst(inst)
          cloned = true
        wire_set(result, :method_name_val, rep)
    args = wire_get(inst, :args)
    if args != nil
      new_args = nil
      ai = 0
      while ai < wire_sequence_size(args)
        arg = wire_sequence_get(args, ai)
        rep = subst[arg]
        if rep != nil
          if cloned == false
            result = clone_inst(inst)
            cloned = true
          if new_args == nil
            new_args = []
            ci = 0
            while ci < ai
              new_args.push(wire_sequence_get(args, ci))
              ci += 1
          new_args.push(rep)
        elsif new_args != nil
          new_args.push(arg)
        ai += 1
      if new_args != nil
        wire_set(result, :args, wire_sequence(new_args))
    return result
  if op == :add_i64 || op == :sub_i64 || op == :mul_i64 || op == :icmp_i64 || op == :icmp_ne_i64 || op == :and_i1 || op == :or_i1 || op == :fadd_f64 || op == :fsub_f64 || op == :fmul_f64 || op == :fdiv_f64 || op == :fcmp_f64
    result = inst
    cloned = false
    val = wire_get(inst, :lhs)
    if val != nil
      rep = subst[val]
      if rep != nil
        result = clone_inst(inst)
        cloned = true
        wire_set(result, :lhs, rep)
    val = wire_get(inst, :rhs)
    if val != nil
      rep = subst[val]
      if rep != nil
        if cloned == false
          result = clone_inst(inst)
        wire_set(result, :rhs, rep)
    return result
  if op == :nanbox_int || op == :nanbox_float
    val = wire_get(inst, :raw)
    if val != nil
      rep = subst[val]
      if rep != nil
        result = clone_inst(inst)
        wire_set(result, :raw, rep)
        return result
    return inst
  if op == :nanunbox_int || op == :nanunbox_float
    val = wire_get(inst, :boxed)
    if val != nil
      rep = subst[val]
      if rep != nil
        result = clone_inst(inst)
        wire_set(result, :boxed, rep)
        return result
    return inst
  if op == :ivar_get || op == :ivar_get_idx
    val = wire_get(inst, :self_reg)
    if val != nil
      rep = subst[val]
      if rep != nil
        result = clone_inst(inst)
        wire_set(result, :self_reg, rep)
        return result
    return inst
  if op == :ivar_set || op == :ivar_set_idx
    result = inst
    cloned = false
    val = wire_get(inst, :value)
    if val != nil
      rep = subst[val]
      if rep != nil
        result = clone_inst(inst)
        cloned = true
        wire_set(result, :value, rep)
    val = wire_get(inst, :self_reg)
    if val != nil
      rep = subst[val]
      if rep != nil
        if cloned == false
          result = clone_inst(inst)
        wire_set(result, :self_reg, rep)
    return result
  if op == :select_i64
    result = inst
    cloned = false
    val = wire_get(inst, :cond)
    if val != nil
      rep = subst[val]
      if rep != nil
        result = clone_inst(inst)
        cloned = true
        wire_set(result, :cond, rep)
    val = wire_get(inst, :then_val)
    if val != nil
      rep = subst[val]
      if rep != nil
        if cloned == false
          result = clone_inst(inst)
          cloned = true
        wire_set(result, :then_val, rep)
    val = wire_get(inst, :else_val)
    if val != nil
      rep = subst[val]
      if rep != nil
        if cloned == false
          result = clone_inst(inst)
        wire_set(result, :else_val, rep)
    return result
  result = inst
  cloned = false
  val = wire_get(inst, :value)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:value] = rep
  val = wire_get(inst, :lhs)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:lhs] = rep
  val = wire_get(inst, :rhs)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:rhs] = rep
  val = wire_get(inst, :ptr)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:ptr] = rep
  val = wire_get(inst, :index)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:index] = rep
  val = wire_get(inst, :raw)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:raw] = rep
  val = wire_get(inst, :boxed)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:boxed] = rep
  val = wire_get(inst, :lhs_boxed)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:lhs_boxed] = rep
  val = wire_get(inst, :rhs_boxed)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:rhs_boxed] = rep
  val = wire_get(inst, :cond)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:cond] = rep
  val = wire_get(inst, :then_val)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:then_val] = rep
  val = wire_get(inst, :else_val)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:else_val] = rep
  val = wire_get(inst, :self_reg)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:self_reg] = rep
  val = wire_get(inst, :receiver)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:receiver] = rep
  val = wire_get(inst, :super_reg)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:super_reg] = rep
  val = wire_get(inst, :a_value)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:a_value] = rep
  val = wire_get(inst, :b_value)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:b_value] = rep
  val = wire_get(inst, :captures_ptr)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:captures_ptr] = rep
  val = wire_get(inst, :buf)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:buf] = rep
  val = wire_get(inst, :class_temp)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:class_temp] = rep
  val = wire_get(inst, :table)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:table] = rep
  # Inline GEP fields: arr, idx
  val = wire_get(inst, :arr)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:arr] = rep
  val = wire_get(inst, :idx)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      result[:idx] = rep
  val = wire_get(inst, :arg)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      wire_set(result, :arg, rep)
  val = wire_get(inst, :dest)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      wire_set(result, :dest, rep)
  val = wire_get(inst, :base)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      wire_set(result, :base, rep)
  val = wire_get(inst, :cap)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      wire_set(result, :cap, rep)
  val = wire_get(inst, :node)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      wire_set(result, :node, rep)
  val = wire_get(inst, :method_name_val)
  if val != nil
    rep = subst[val]
    if rep != nil
      if cloned == false
        result = clone_inst(inst)
        cloned = true
      wire_set(result, :method_name_val, rep)
  if op == :slab_alloc_init
    farr = wire_get(inst, :fields)
    if farr != nil
      new_farr = nil
      fi = 0
      while fi < wire_sequence_size(farr)
        fv = wire_sequence_get(farr, fi)
        rep = subst[fv]
        if rep != nil
          if cloned == false
            result = clone_inst(inst)
            cloned = true
          if new_farr == nil
            new_farr = []
            ci = 0
            while ci < fi
              new_farr.push(wire_sequence_get(farr, ci))
              ci += 1
          new_farr.push(rep)
        elsif new_farr != nil
          new_farr.push(fv)
        fi += 1
      if new_farr != nil
        wire_set(result, :fields, wire_sequence(new_farr))
  if op == :bool_array_set_inline || op == :bool_array_set_byte_inline
    val = wire_get(inst, :val)
    if val != nil
      rep = subst[val]
      if rep != nil
        if cloned == false
          result = clone_inst(inst)
          cloned = true
        wire_set(result, :val, rep)
  # Substitute within s[] scratch array
  sarr = wire_get(inst, :s)
  if sarr != nil
    new_sarr = nil
    si = 0
    while si < wire_sequence_size(sarr)
      sv = wire_sequence_get(sarr, si)
      rep = subst[sv]
      if rep != nil
        if cloned == false
          result = clone_inst(inst)
          cloned = true
        if new_sarr == nil
          new_sarr = []
          ci = 0
          while ci < si
            new_sarr.push(wire_sequence_get(sarr, ci))
            ci += 1
        new_sarr.push(rep)
      elsif new_sarr != nil
        new_sarr.push(sv)
      si += 1
    if new_sarr != nil
      wire_set(result, :s, wire_sequence(new_sarr))
  # Inline-asm builtin operands live in op-specific fields (outp/ap/bp/n/
  # ooff/aoff/boff/bsc/na/nb/vp/twp/ivp/hq — see calls.w's asm_* lowerings).
  # Gate the sweep on the op so the common path stays flat. Without this, a
  # CSE-forwarded machine-int local passed as an asm-builtin operand (e.g.
  # asm_add_no's n) kept referencing the eliminated load's temp — clang
  # rejected the IR with `use of undefined value %tN`.
  if op in (:asm_add_n :asm_add_no :asm_sub_no :asm_addmul1 :asm_mulbase :asm_neon_umull :asm_neon_redc :asm_neon_redc4 :asm_neon_madd4 :asm_neon_msub4 :asm_neon_gadd2 :asm_neon_ntt_stage :asm_gold_stage :asm_gold_stage_inv :asm_add_uneq :asm_sub_uneq)
    asm_fields = [:outp, :ap, :bp, :vp, :twp, :ivp, :n, :ooff, :aoff, :boff, :bsc, :na, :nb, :hq]
    fi = 0
    while fi < asm_fields.size()
      fk = asm_fields[fi]
      fv = inst[fk]
      if fv != nil
        rep = subst[fv]
        if rep != nil
          if cloned == false
            result = clone_inst(inst)
            cloned = true
          result[fk] = rep
      fi += 1
  # Substitute within args array only if needed
  args = wire_get(inst, :args)
  if args != nil
    new_args = nil
    ai = 0
    while ai < wire_sequence_size(args)
      arg = wire_sequence_get(args, ai)
      rep = subst[arg]
      if rep != nil
        if cloned == false
          result = clone_inst(inst)
          cloned = true
        if new_args == nil
          new_args = []
          ci = 0
          while ci < ai
            new_args.push(wire_sequence_get(args, ci))
            ci += 1
        new_args.push(rep)
      elsif new_args != nil
        new_args.push(arg)
      ai += 1
    if new_args != nil
      wire_set(result, :args, wire_sequence(new_args))
  result

# -- Pass 2: Dead store elimination --
# Forward pass: if two stores target the same slot with no intervening load,
# the first store is dead (overwritten before read).

-> dead_store_elim(block, fn_escaped = nil, fn_has_setjmp = false)
  prev_store = {}
  dead_set = {}
  has_dead = false
  # Slots whose address has been taken (ptr_to_i64) may be loaded later
  # through a captured inttoptr — e.g. `i = 0; each { use i }; i = 1`.
  # DSE must not kill stores to escaped slots: the intervening use is
  # invisible as a load_i64 of the slot itself. Under setjmp, a raising
  # call can jump to rescue and read a slot stored before the call.
  escaped = {}

  i = 0
  instrs = block[:instructions]
  n_instrs = instrs.size()
  while i < n_instrs
    inst = instrs[i]
    kid = ccall_nobox("w_wire_kind_extern", inst) ## i64
    if kid == WIRE_KIND_STORE_I64 || kid == WIRE_KIND_STORE_I128 || kid == WIRE_KIND_STORE_FLOAT || kid == WIRE_KIND_STORE_DOUBLE
      ptr = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_I64_PTR)
      prev = prev_store[ptr]
      is_esc = escaped[ptr] == true || (fn_escaped != nil && fn_escaped[ptr] == true)
      if prev != nil && !is_esc
        dead_set[prev] = true
        has_dead = true
      prev_store[ptr] = i
    elsif kid == WIRE_KIND_LOAD_I64 || kid == WIRE_KIND_LOAD_I128 || kid == WIRE_KIND_LOAD_FLOAT || kid == WIRE_KIND_LOAD_DOUBLE
      # Load makes the previous store to this slot live
      prev_store[ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_I64_PTR)] = nil
    elsif kid == WIRE_KIND_PTR_TO_I64
      val = ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PTR_TO_I64_VALUE)
      escaped[val] = true
      prev_store[val] = nil
    elsif fn_has_setjmp && kid > 0 && kid <= WIRE_KIND_MAX && wire_call_kind_table[kid] == true
      prev_store = {}
    i += 1

  if !has_dead
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
  if f[:var_slots].size() == 0
    return

  # Collect all ptrs that appear in load instructions
  loaded = {}
  i = 0
  while i < f[:blocks].size()
    blk = f[:blocks][i]
    instrs = blk[:instructions]
    j = 0
    n_instrs = instrs.size()
    while j < n_instrs
      inst = instrs[j]
      kid = ccall_nobox("w_wire_kind_extern", inst) ## i64
      if kid == WIRE_KIND_LOAD_I64 || kid == WIRE_KIND_LOAD_I128 || kid == WIRE_KIND_LOAD_FLOAT || kid == WIRE_KIND_LOAD_DOUBLE
        loaded[ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_LOAD_I64_PTR)] = true
      elsif kid == WIRE_KIND_PTR_TO_I64
        loaded[ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_PTR_TO_I64_VALUE)] = true
      j += 1
    i += 1

  # Identify dead slots (stored but never loaded)
  dead = {}
  has_dead = false
  slot_names = f[:var_slots].keys()
  i = 0
  while i < slot_names.size()
    ptr = f[:var_slots][slot_names[i]]
    if ptr.starts_with?("%v") && loaded[ptr] != true
      dead[ptr] = true
      has_dead = true
    i += 1

  if !has_dead
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
    instrs = blk[:instructions]
    new_instrs = []
    j = 0
    n_instrs = instrs.size()
    while j < n_instrs
      inst = instrs[j]
      kid = ccall_nobox("w_wire_kind_extern", inst) ## i64
      if ((kid != WIRE_KIND_STORE_I64 && kid != WIRE_KIND_STORE_I128 && kid != WIRE_KIND_STORE_FLOAT && kid != WIRE_KIND_STORE_DOUBLE) || dead[ccall_rawargs("w_wire_slot_load", inst, WIRE_SLOT_STORE_I64_PTR)] != true)
        new_instrs.push(inst)
      j += 1
    blk[:instructions] = new_instrs
    i += 1
