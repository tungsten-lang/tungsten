# Closed-world Core function reachability.
#
# PROTECT_THE_CORE gives the compiler a stable Core cohort and
# LOCK_THE_DOORS closes the complete method universe. For that combination we
# can emit only the Core functions reachable from the program delta, direct
# function references, and the literal dynamic sends in live bodies. The full
# Core graph remains on the module so a cold incremental-cache compile still
# stores the reusable 929-function cohort after emission.

-> core_reachability_enabled?
  env("TUNGSTEN_CORE_REACHABILITY") != "0"

-> core_reachability_add_function(name, functions_by_name, live, queue)
  if name == nil || live[name] == true
    return nil
  func = functions_by_name[name]
  if func != nil
    live[name] = true
    queue.push(func)
  nil

-> core_reachability_root_method(registrations_by_name, name, call_arity, functions_by_name, live, queue)
  registrations = registrations_by_name[name]
  if registrations == nil
    return nil
  i = 0
  while i < registrations.size()
    registration = registrations[i]
    # Runtime dispatch first asks for a compatible arity, then deliberately
    # falls back to the name-only entry for nil padding and its historical
    # arity diagnostics. Without receiver-class facts every same-name Core
    # registration is therefore a possible target, even when its declared
    # arity differs from this call site.
    core_reachability_add_function(registration[:fn_name], functions_by_name, live, queue)
    i += 1
  nil

-> core_reachability_string_text_by_id(mod)
  by_id = {}
  i = 0
  while i < mod[:strings].size()
    entry = mod[:strings][i]
    by_id[entry[:id]] = entry[:text]
    i += 1
  by_id

-> core_reachability_collect_registrations(mod, core_names)
  text_by_id = core_reachability_string_text_by_id(mod)
  by_name = {}
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    bi = 0
    while bi < func[:blocks].size()
      instructions = func[:blocks][bi][:instructions]
      ii = 0
      while ii < instructions.size()
        inst = instructions[ii]
        op = wire_kind(inst)
        if op in (:class_add_method :class_add_static_method)
          fn_name = wire_get(inst, :fn_name)
          if core_names[fn_name] == true
            name = text_by_id[wire_get(inst, :method_str_id)]
            if name == nil
              return {ok: false, reason: "method registration has no string text"}
            registrations = by_name[name]
            if registrations == nil
              registrations = []
              by_name[name] = registrations
            registrations.push({
              fn_name: fn_name,
              arity: wire_get(inst, :arity),
              min_arity: wire_get(inst, :min_arity),
              splat_index: wire_get(inst, :splat_index)
            })
        ii += 1
      bi += 1
    fi += 1
  {ok: true, by_name: by_name}

-> core_reachability_unsafe_runtime_call?(name)
  name != nil && name.index("w_method_call") == 0

-> core_reachability_direct_target(inst)
  op = wire_kind(inst)
  if op in (:call_direct_i64 :call_direct_i128 :call_direct_void :call_direct_ptr :call_direct_i64_ptr1 :call_direct_void_ptr1 :fn_addr_i64)
    return wire_get(inst, :name)
  if op in (:closure_new :memo_call0_i64 :memo_call1_i64 :memo_call2_i64)
    return wire_get(inst, :fn_name)
  nil

# emit_artifact synthesizes stable BigInt source seams after ordinary function
# rendering. Those wrapper references are not represented by WIRE edges, so
# their source targets are explicit roots of the emission slice.
-> core_reachability_emitter_root?(func)
  method = func[:source_method]
  if func[:source_class] == nil && method in ("__bigint_and_raw" "__bigint_or_raw" "__bigint_xor_raw" "__bigint_and_mut_raw" "__bigint_or_mut_raw" "__bigint_xor_mut_raw" "__bigint_compare_raw")
    return true
  if func[:source_class] == "BigInt" && method in ("+" "-" "*" "&" "|" "^" "/" "%" "<<" ">>" "+__ovl_BigInt" "-__ovl_BigInt" "*__ovl_BigInt" "&__ovl_BigInt" "|__ovl_BigInt" "^__ovl_BigInt" "/__ovl_BigInt" "%__ovl_BigInt" "<<__ovl_Int" ">>__ovl_Int")
    return true
  false

-> core_reachability_filter_registrations(mod, core_names, live, functions = nil)
  if functions == nil
    functions = mod[:functions]
  removed = 0
  restore = []
  fi = 0
  while fi < functions.size()
    func = functions[fi]
    bi = 0
    while bi < func[:blocks].size()
      block = func[:blocks][bi]
      old_instructions = block[:instructions]
      new_instructions = []
      block_changed = false
      ii = 0
      while ii < old_instructions.size()
        inst = old_instructions[ii]
        op = wire_kind(inst)
        target = nil
        if op in (:class_add_method :class_add_static_method)
          target = wire_get(inst, :fn_name)
        if target != nil && core_names[target] == true && live[target] != true
          removed += 1
          block_changed = true
        else
          new_instructions.push(inst)
        ii += 1
      if block_changed
        restore.push({block: block, instructions: old_instructions})
        block[:instructions] = new_instructions
      bi += 1
    fi += 1
  mod[:core_reachability_registration_restore] = restore
  removed

# Rebuild the name sets after content hashing has compacted the live slice.
# Function handles are shared with `all_functions`, so their current names are
# visible there too; unreachable frozen Core functions retain their cached
# names. This keeps registration filtering at its historical post-hash point
# while allowing earlier passes to operate on the smaller live closure.
-> core_reachability_filter_current_registrations(mod, all_functions, live_functions)
  core_names = {}
  live = {}
  i = 0
  while i < all_functions.size()
    func = all_functions[i]
    if incremental_core_cache_function?(func)
      core_names[func[:name]] = true
    i += 1
  i = 0
  while i < live_functions.size()
    live[live_functions[i][:name]] = true
    i += 1
  core_reachability_filter_registrations(mod, core_names, live, all_functions)

-> core_reachability_restore_full_graph(mod)
  restore = mod[:core_reachability_registration_restore]
  if restore == nil
    return nil
  i = 0
  while i < restore.size()
    item = restore[i]
    item[:block][:instructions] = item[:instructions]
    i += 1
  mod[:core_reachability_registration_restore] = []
  nil

-> core_reachability_fallback(mod, reason)
  mod[:core_reachability_status] = :fallback
  mod[:core_reachability_reason] = reason
  mod[:core_reachability_emit_functions] = nil
  nil

-> core_reachability_prepare(mod, filter_registrations = true)
  mod[:core_reachability_registration_restore] = []
  if !core_reachability_enabled?
    mod[:core_reachability_status] = :disabled
    return nil
  if mod[:incremental_core_cache_key] == nil || mod[:protect_core] != true
    return core_reachability_fallback(mod, "PROTECT_THE_CORE! is absent")
  if mod[:method_tables_locked] != true
    return core_reachability_fallback(mod, "LOCK_THE_DOORS! is absent")

  functions_by_name = {}
  core_names = {}
  core_total = 0
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    functions_by_name[func[:name]] = func
    if incremental_core_cache_function?(func)
      core_names[func[:name]] = true
      core_total += 1
    fi += 1
  mod[:core_reachability_total] = core_total
  if core_total == 0
    return core_reachability_fallback(mod, "stable Core cohort is empty")

  registration_result = core_reachability_collect_registrations(mod, core_names)
  if registration_result[:ok] != true
    return core_reachability_fallback(mod, registration_result[:reason])
  registrations_by_name = registration_result[:by_name]

  live = {}
  queue = []
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    if core_names[func[:name]] != true || core_reachability_emitter_root?(func)
      core_reachability_add_function(func[:name], functions_by_name, live, queue)
    fi += 1

  # Runtime helpers can re-enter source method tables even when a WIRE body
  # contains no explicit send. Keep those language hooks. `new` is unbounded
  # because erased-receiver construction can select any observed call arity.
  implicit_methods = [
    {name: "+", arity: 2}, {name: "-", arity: 2},
    {name: "*", arity: 2}, {name: "/", arity: 2},
    {name: "%", arity: 2}, {name: "**", arity: 2},
    {name: "-@", arity: 1}, {name: "==", arity: 2},
    {name: "<=>", arity: 2}, {name: "to_s", arity: 1},
    {name: "[]", arity: 2}, {name: "[]=", arity: 3},
    {name: "method_missing", arity: nil},
    {name: "method_missing_set", arity: nil},
    {name: "new", arity: nil}
  ]
  i = 0
  while i < implicit_methods.size()
    item = implicit_methods[i]
    core_reachability_root_method(registrations_by_name, item[:name], item[:arity], functions_by_name, live, queue)
    i += 1

  # Extra C translation units can call the public runtime dispatch API with a
  # computed method name, an edge that WIRE cannot see. They cannot name
  # content-addressed internal helpers, so retaining every registered Core
  # method (and then its ordinary direct-call closure) is the conservative FFI
  # boundary while still allowing unregistered helper pruning.
  c_includes = env("TUNGSTEN_C_INCLUDES")
  if c_includes != nil && c_includes != ""
    method_names = registrations_by_name.keys()
    i = 0
    while i < method_names.size()
      core_reachability_root_method(registrations_by_name, method_names[i], nil, functions_by_name, live, queue)
      i += 1

  qi = 0
  while qi < queue.size()
    func = queue[qi]
    qi += 1
    if func[:reflective_method_access] == true
      return core_reachability_fallback(mod, "live reflective method access in " + func[:name])
    calls = func[:dynamic_method_calls]
    if calls == nil || type(calls) != "Array"
      return core_reachability_fallback(mod, "live function has no dynamic-send summary: " + func[:name])
    i = 0
    while i < calls.size()
      call = calls[i]
      core_reachability_root_method(registrations_by_name, call[:name], call[:arity], functions_by_name, live, queue)
      # Any failed type-class send can invoke one of these hooks.
      core_reachability_root_method(registrations_by_name, "method_missing", nil, functions_by_name, live, queue)
      core_reachability_root_method(registrations_by_name, "method_missing_set", nil, functions_by_name, live, queue)
      i += 1

    bi = 0
    while bi < func[:blocks].size()
      instructions = func[:blocks][bi][:instructions]
      ii = 0
      while ii < instructions.size()
        inst = instructions[ii]
        target = core_reachability_direct_target(inst)
        if core_reachability_unsafe_runtime_call?(target)
          return core_reachability_fallback(mod, "live dynamic runtime dispatch in " + func[:name])
        core_reachability_add_function(target, functions_by_name, live, queue)
        if wire_kind(inst) == :call_method_i64
          core_reachability_add_function(wire_get(inst, :devirt_fn), functions_by_name, live, queue)
          core_reachability_add_function(wire_get(inst, :construct_fn), functions_by_name, live, queue)
        ii += 1
      bi += 1

  emit_functions = []
  core_kept = 0
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    if live[func[:name]] == true
      emit_functions.push(func)
      if core_names[func[:name]] == true
        core_kept += 1
    fi += 1

  if filter_registrations
    core_reachability_filter_registrations(mod, core_names, live)
  mod[:core_reachability_emit_functions] = emit_functions
  mod[:core_reachability_kept] = core_kept
  mod[:core_reachability_pruned] = core_total - core_kept
  mod[:core_reachability_status] = :active
  nil

-> core_reachability_emission_functions(mod)
  if mod[:core_reachability_status] == :active
    return mod[:core_reachability_emit_functions]
  nil

-> core_reachability_verbose_text(mod)
  status = mod[:core_reachability_status]
  if status == :active
    return "  core reachability: " + mod[:core_reachability_kept].to_s() + "/" + mod[:core_reachability_total].to_s() + " kept (" + mod[:core_reachability_pruned].to_s() + " pruned)"
  if status == :fallback
    return "  core reachability: fallback (" + mod[:core_reachability_reason] + ")"
  "  core reachability: disabled"
