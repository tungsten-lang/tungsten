# Lowering / stable Core ABI — ownership partition, conservative warm-Core
# eligibility, and a deterministic fingerprint of the Core-facing WIRE ABI.
#
# PROTECT_THE_CORE is deliberately an executable-owner choice. It does not
# prevent subclassing Core classes or selecting different lowering modes.
# Structural coupling falls back to monolithic compilation; deterministic
# modes become distinct compatibility-key variants. The status recorded here
# tells a future incremental compiler when a lowered Core partition is safe to
# reuse and why it fell back when it is not.

-> core_source_path?(path)
  if path == nil
    return false
  text = "" + path
  root = env("TUNGSTEN_ROOT")
  if root != nil
    prefix = root + "/core/"
    if text.size() >= prefix.size() && text.slice(0, prefix.size()) == prefix
      return true
  text.size() >= 5 && text.slice(0, 5) == "core/"

-> stable_core_partition_expressions(expressions)
  core = []
  user = []
  missing = 0
  i = 0
  while i < expressions.size()
    expr = expressions[i]
    path = ast_get(expr, :source_path)
    if path == nil
      missing += 1
      user.push(expr)
    elsif core_source_path?(path)
      core.push(expr)
    else
      user.push(expr)
    i += 1
  {core: core, user: user, missing: missing}

-> copy_core_abi_map(source)
  copied = {}
  if source == nil
    return copied
  keys = source.keys()
  i = 0
  while i < keys.size()
    copied[keys[i]] = source[keys[i]]
    i += 1
  copied

-> core_abi_top_assignment_names(expressions)
  names = {}
  i = 0
  while i < expressions.size()
    expr = expressions[i]
    kind = ast_kind(expr)
    if kind in (:assign :compound_assign)
      target = expr.target
      if target != nil && is_ast_node?(target) && ast_kind(target) == :var
        names[target.name] = true
    elsif kind == :multi_assign
      targets = expr.targets
      if targets != nil
        ti = 0
        while ti < targets.size()
          target = targets[ti]
          if target != nil && is_ast_node?(target) && ast_kind(target) == :var
            names[target.name] = true
          ti += 1
    i += 1
  names

-> core_abi_constant_alias?(expr)
  if expr == nil || !is_ast_node?(expr) || ast_kind(expr) != :call
    return false
  expr.receiver == nil && expr.name == "constant_alias"

-> stable_core_contract_fallback_reason(mod, core_exprs, user_exprs, missing)
  if missing > 0
    return missing.to_s() + " top-level expressions have no declaring-file provenance"

  # Generic specializations are minted from whole-program use. A specialized
  # Core template belongs in the program delta until incremental lowering can
  # materialize such variants beside (rather than inside) the warmed prelude.
  specs = mod[:generic_specialization_order]
  if specs != nil
    si = 0
    while si < specs.size()
      if definition_from_core?(specs[si])
        return "a Core generic template was specialized by this program"
      si += 1

  core_classes = {}
  supers = {}
  core_globals = core_abi_top_assignment_names(core_exprs)
  ci = 0
  while ci < core_exprs.size()
    expr = core_exprs[ci]
    if ast_kind(expr) in (:class_def :module_def)
      core_classes[expr.name] = true
      supers[expr.name] = expr.superclass
    ci += 1

  # Build the complete source superclass map so an indirect user chain such
  # as UserLeaf < UserMid < CoreBase is caught as well as a direct subclass.
  ui = 0
  while ui < user_exprs.size()
    expr = user_exprs[ui]
    if ast_kind(expr) in (:class_def :module_def)
      supers[expr.name] = expr.superclass
    ui += 1

  user_globals = core_abi_top_assignment_names(user_exprs)
  global_names = user_globals.keys()
  gi = 0
  while gi < global_names.size()
    if core_globals[global_names[gi]] == true
      return "program global '" + global_names[gi] + "' shadows a Core global"
    gi += 1

  ui = 0
  while ui < user_exprs.size()
    expr = user_exprs[ui]
    if core_abi_constant_alias?(expr)
      return "program constant_alias declarations require per-program Core analysis"
    if ast_kind(expr) == :class_def
      cur = expr.superclass
      visited = {}
      while cur != nil && visited[cur] != true
        if core_classes[cur] == true
          return "program class " + expr.name + " subclasses Core class " + cur
        visited[cur] = true
        cur = supers[cur]
    ui += 1
  nil

-> prepare_stable_core_contract(mod, core_exprs, user_exprs, missing)
  mod[:core_expression_count] = core_exprs.size()
  mod[:user_expression_count] = user_exprs.size()
  reason = stable_core_contract_fallback_reason(mod, core_exprs, user_exprs, missing)
  if reason == nil
    mod[:core_reuse_contract] = :stable
  else
    mod[:core_reuse_contract] = :monolithic_fallback
    mod[:core_reuse_fallback_reason] = reason
  nil

# A warmed Core must publish every Core top-level binding that user functions
# might reference. Making those mirrors unconditional removes the old
# whole-program coupling where the presence of one user read changed Core's
# store_global stream and ownership result.
-> mark_stable_core_global_exports(mod, core_exprs)
  exports = core_abi_top_assignment_names(core_exprs)
  mod[:core_exported_globals] = exports
  if mod[:extern_var_refs] != nil
    names = exports.keys()
    i = 0
    while i < names.size()
      mod[:extern_var_refs][names[i]] = true
      i += 1
  nil

-> core_abi_field(value)
  if value == nil
    return "-;"
  text = value.to_s()
  text.size().to_s() + ":" + text + ";"

-> core_abi_bool(value)
  if value == true
    return "1"
  "0"

-> core_abi_function_row(wfn)
  row = StringBuffer(192)
  row << "F;"
  row << core_abi_field(wfn[:name])
  row << core_abi_field(wfn[:source_kind])
  row << core_abi_field(wfn[:source_class])
  row << core_abi_field(wfn[:source_method])
  row << core_abi_field(wfn[:params].size())
  row << core_abi_field(wfn[:return_type])
  row << core_abi_field(core_abi_bool(wfn[:raw_i64_signature]))
  row << core_abi_field(wfn[:raw_return_type])
  extras = wfn[:extra_params]
  if extras == nil
    row << core_abi_field(0)
  else
    row << core_abi_field(extras.size())
    i = 0
    while i < extras.size()
      row << core_abi_field(extras[i][:type])
      i += 1
  row.to_s()

-> core_abi_class_row(name, node, mod)
  row = StringBuffer(192)
  row << "C;"
  row << core_abi_field(name)
  super_name = mod[:class_super_names][name]
  if super_name == nil
    super_name = node.superclass
  row << core_abi_field(super_name)
  offsets = ast_ivar_offsets_get(node)
  if offsets == nil
    row << core_abi_field(0)
    return row.to_s()
  keys = offsets.keys().sort()
  row << core_abi_field(keys.size())
  i = 0
  while i < keys.size()
    row << core_abi_field(keys[i])
    row << core_abi_field(offsets[keys[i]])
    i += 1
  row.to_s()

# Lowering modes change Core code but do not make it user-dependent. Encode
# them as cache variants instead of forcing monolithic fallback: a fast-math
# program can reuse a fast-math Core, never a precise one. Build defines are
# similarly exact-keyed; their values are length-prefixed to avoid ambiguous
# concatenation.
-> core_abi_variant_row(mod)
  row = StringBuffer(192)
  row << "X;"
  row << core_abi_field("types")
  row << core_abi_field(core_abi_bool(mod[:type_tables_locked]))
  row << core_abi_field("doors")
  row << core_abi_field(core_abi_bool(mod[:method_tables_locked]))
  row << core_abi_field("fast")
  row << core_abi_field(core_abi_bool(mod[:fast_mode]))
  row << core_abi_field("math")
  row << core_abi_field(mod[:math_mode])
  row << core_abi_field("static_slab")
  row << core_abi_field(core_abi_bool(mod[:no_static_slab] != true))
  defines = mod[:build_defines]
  if defines == nil
    row << core_abi_field(0)
  else
    keys = defines.keys().sort()
    row << core_abi_field(keys.size())
    i = 0
    while i < keys.size()
      row << core_abi_field(keys[i])
      row << core_abi_field(defines[keys[i]])
      i += 1
  row.to_s()

# Fingerprint the link-visible shape a cached Core partition would expose.
# Source contents and compiler/runtime identity remain separate cache-manifest
# inputs; this digest specifically catches callable signature, class-layout,
# global-export, and executable-contract drift.
-> finalize_stable_core_abi(mod, core_exprs)
  rows = []
  function_count = 0
  i = 0
  while i < mod[:functions].size()
    wfn = mod[:functions][i]
    if wfn[:is_toplevel] != true && core_source_path?(wfn[:source_path])
      rows.push(core_abi_function_row(wfn))
      function_count += 1
    i += 1

  class_count = 0
  class_names = mod[:known_classes].keys().sort()
  i = 0
  while i < class_names.size()
    name = class_names[i]
    node = mod[:known_classes][name]
    if node != nil && is_ast_node?(node) && definition_from_core?(node)
      rows.push(core_abi_class_row(name, node, mod))
      class_count += 1
    i += 1

  global_count = 0
  exports = mod[:core_exported_globals]
  if exports != nil
    names = exports.keys().sort()
    global_count = names.size()
    i = 0
    while i < names.size()
      rows.push("G;" + core_abi_field(names[i]))
      i += 1

  rows.push(core_abi_variant_row(mod))
  rows = rows.sort()
  canonical = rows.join("\n") + "\n"
  mod[:core_abi_hash] = wyhash64_hex_string(canonical)
  mod[:core_abi_function_count] = function_count
  mod[:core_abi_class_count] = class_count
  mod[:core_abi_global_count] = global_count
  mod[:core_abi_canonical] = canonical
  report_path = env("TUNGSTEN_CORE_ABI_REPORT")
  if report_path != nil && report_path != ""
    write_file(report_path, canonical)
  nil
