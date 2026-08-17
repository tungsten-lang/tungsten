# Lowering / library cache — persist raw WIRE for an unchanged imported
# library cohort. Core remains the stable base artifact; this layer begins at
# its exact counter/string boundary and stops before the entry file. Every
# restored function still traverses the ordinary CFG/SSA/ownership/hash/emitter
# pipeline, so this cache removes lowering work without creating a codegen or
# optimization boundary.

incremental_library_cache_state = {
  persistent_dir: nil,
  persistent_identity: nil,
  hits: 0,
  misses: 0,
  stores: 0,
  corruptions: 0
}

-> incremental_library_cache_configure_persistent(dir, identity)
  incremental_library_cache_state[:persistent_dir] = dir
  incremental_library_cache_state[:persistent_identity] = identity
  nil

-> incremental_library_cache_persistent_path(key)
  dir = incremental_library_cache_state[:persistent_dir]
  identity = incremental_library_cache_state[:persistent_identity]
  if dir == nil || identity == nil
    return nil
  dir + "/library-wire-v1-" + identity + "-" + key + ".twc"

-> incremental_library_cache_set_bypass(mod, reason)
  mod[:incremental_library_cache_status] = :bypass
  mod[:incremental_library_cache_reason] = reason
  nil

# Canonicalize only immutable scalar/container facts. AST and WIRE handles are
# deliberately unsupported here: if a new analysis map leaks either into the
# ABI context, reuse fails closed until that dependency gets an explicit row.
-> incremental_library_cache_canonical_value(value, state, depth = 0)
  if state[:ok] != true
    return ""
  if depth > 64
    state[:ok] = false
    return ""
  if value == nil
    return "n;"
  t = type(value)
  if t == "Boolean"
    return value == true ? "b1;" : "b0;"
  if t == "Int"
    return "i" + core_abi_field(value)
  if t == "BigInt"
    return "z" + core_abi_field(value)
  if t == "Float" || t == "Decimal"
    return "f" + core_abi_field(value)
  if t == "String"
    return "s" + core_abi_field(value)
  if t == "Symbol"
    return "y" + core_abi_field(value)
  if t == "Array"
    out = StringBuffer(32 + value.size() * 12)
    out << "a" + core_abi_field(value.size())
    i = 0
    while i < value.size()
      item = incremental_library_cache_canonical_value(value[i], state, depth + 1)
      if state[:ok] != true
        return ""
      out << core_abi_field(item)
      i += 1
    return out.to_s()
  if t == "Hash"
    pairs = []
    keys = value.keys()
    i = 0
    while i < keys.size()
      key_text = incremental_library_cache_canonical_value(keys[i], state, depth + 1)
      value_text = incremental_library_cache_canonical_value(value[keys[i]], state, depth + 1)
      if state[:ok] != true
        return ""
      pairs.push(core_abi_field(key_text) + core_abi_field(value_text))
      i += 1
    pairs = incremental_core_cache_sort_strings(pairs)
    return "h" + core_abi_field(pairs.size()) + pairs.join("")
  state[:ok] = false
  ""

-> incremental_library_cache_digest(value)
  state = {ok: true}
  canonical = incremental_library_cache_canonical_value(value, state)
  if state[:ok] != true
    return nil
  wyhash64_hex_string(canonical)

-> incremental_library_cache_context_fields
  [
    :known_calls,
    :known_fn_param_counts,
    :known_fn_splat_info,
    :known_static_methods,
    :known_fn_overloads,
    :known_typed_overload_counts,
    :known_unique_typed_overload_keys,
    :known_unique_typed_overload_param_types,
    :known_pure_calls,
    :raw_callable_fns,
    :raw_fn_param_kinds,
    :fn_return_types,
    :return_class_sets,
    :return_class_set_workers,
    :no_raise_workers,
    :class_super_names,
    :class_method_fn_names,
    :class_constructor_fn_names,
    :class_static_new,
    :ivar_types,
    :exact_source_ivar_types,
    :top_level_static_types,
    :top_level_var_types,
    :extern_var_refs,
    :observed_param_types,
    :param_infer_bailed,
    :constant_aliases,
    :block_method_names,
    :build_defines
  ]

-> incremental_library_cache_context_snapshot(mod)
  snapshot = {}
  fields = incremental_library_cache_context_fields()
  i = 0
  while i < fields.size()
    snapshot[fields[i]] = mod[fields[i]]
    i += 1
  snapshot[:protect_core] = mod[:protect_core]
  snapshot[:type_tables_locked] = mod[:type_tables_locked]
  snapshot[:method_tables_locked] = mod[:method_tables_locked]
  snapshot[:fast_mode] = mod[:fast_mode]
  snapshot[:math_mode] = mod[:math_mode]
  snapshot[:no_static_slab] = mod[:no_static_slab]
  snapshot[:uses_argv] = mod[:uses_argv]
  snapshot

-> incremental_library_cache_param_row(param)
  if param == nil
    return "-"
  row = StringBuffer(64)
  row << core_abi_field(ast_get(param, :name))
  row << core_abi_field(ast_get(param, :keyword) == true)
  row << core_abi_field(ast_get(param, :splat) == true)
  row << core_abi_field(ast_get(param, :block_param) == true)
  row << core_abi_field(ast_get(param, :ivar_assign) == true)
  row << core_abi_field(ast_get(param, :default) != nil)
  row.to_s()

-> incremental_library_cache_definition_row(node, owner)
  row = StringBuffer(192)
  row << "D;"
  row << core_abi_field(ast_kind(node))
  row << core_abi_field(owner)
  row << core_abi_field(ast_get(node, :name))
  row << core_abi_field(ast_get(node, :is_class_method) == true)
  row << core_abi_field(ast_get(node, :from_fn) == true)
  params = ast_get(node, :params)
  if params == nil
    row << core_abi_field(0)
  else
    row << core_abi_field(params.size())
    i = 0
    while i < params.size()
      row << core_abi_field(incremental_library_cache_param_row(params[i]))
      i += 1
  param_types = ast_get(node, :param_types)
  if param_types == nil
    row << core_abi_field(0)
  else
    row << core_abi_field(param_types.size())
    i = 0
    while i < param_types.size()
      row << core_abi_field(param_types[i])
      i += 1
  row << core_abi_field(ast_get(node, :return_type))
  row << core_abi_field(ast_get(node, :typed_overload) == true)
  row.to_s()

-> incremental_library_cache_definition_rows(expressions, mod)
  rows = []
  i = 0
  while i < expressions.size()
    expr = expressions[i]
    kind = ast_kind(expr)
    if kind in (:fn_def :method_def)
      rows.push(incremental_library_cache_definition_row(expr, nil))
    elsif kind in (:class_def :module_def :trait_def)
      rows.push("T;" + core_abi_field(kind) + core_abi_field(expr.name) + core_abi_field(ast_get(expr, :superclass)))
      body = nil
      if mod[:prepared_class_bodies] != nil
        body = mod[:prepared_class_bodies][expr]
      if body == nil
        body = ast_get(expr, :body)
      if body != nil
        bi = 0
        while bi < body.size()
          child = body[bi]
          if is_ast_node?(child) && ast_kind(child) in (:fn_def :method_def)
            rows.push(incremental_library_cache_definition_row(child, expr.name))
          bi += 1
    i += 1

  class_names = mod[:known_classes].keys().sort()
  i = 0
  while i < class_names.size()
    name = class_names[i]
    node = mod[:known_classes][name]
    if node != nil && is_ast_node?(node)
      rows.push(core_abi_class_row(name, node, mod))
    i += 1
  incremental_core_cache_sort_strings(rows)

-> incremental_library_cache_context_digest(mod, expressions)
  context = incremental_library_cache_context_snapshot(mod)
  context_hash = incremental_library_cache_digest(context)
  if context_hash == nil
    return nil
  rows = incremental_library_cache_definition_rows(expressions, mod)
  text = StringBuffer(64 + rows.size() * 96)
  text << context_hash
  text << "\n"
  i = 0
  while i < rows.size()
    text << rows[i]
    text << "\n"
    i += 1
  wyhash64_hex_string(text.to_s())

# Function-producing expressions outside a definition would be lowered again
# on a hit, duplicating cached workers. Definition bodies are opaque here: all
# functions they create carry the declaring path and are part of the snapshot.
-> incremental_library_cache_nondef_safe?(value)
  if value == nil
    return true
  if type(value) == "Array"
    i = 0
    while i < value.size()
      if !incremental_library_cache_nondef_safe?(value[i])
        return false
      i += 1
    return true
  if !is_ast_node?(value)
    return true
  kind = ast_kind(value)
  if kind in (:block :go)
    return false
  if kind in (:fn_def :method_def :gpu_kernel_def)
    return true
  if kind == :binary_op && ast_get(value, :op) in (:DOT_PLUS :DOT_MINUS :DOT_STAR :DOT_SLASH)
    return false
  children = ast_children(value)
  i = 0
  while i < children.size()
    if !incremental_library_cache_nondef_safe?(children[i])
      return false
    i += 1
  true

-> incremental_library_cache_expression_safe?(expr, mod)
  kind = ast_kind(expr)
  if kind in (:fn_def :method_def :gpu_kernel_def)
    return true
  if kind in (:class_def :module_def :trait_def)
    body = nil
    if mod[:prepared_class_bodies] != nil
      body = mod[:prepared_class_bodies][expr]
    if body == nil
      body = ast_get(expr, :body)
    if body == nil
      return true
    i = 0
    while i < body.size()
      child = body[i]
      if is_ast_node?(child) && ast_kind(child) in (:fn_def :method_def :gpu_kernel_def)
        nil
      elsif !incremental_library_cache_nondef_safe?(child)
        return false
      i += 1
    return true
  incremental_library_cache_nondef_safe?(expr)

-> incremental_library_cache_partition(expressions, source_manifest)
  if source_manifest == nil || source_manifest.size() == 0 || type(source_manifest[0]) != "Array"
    return {ok: false, reason: "source manifest is unavailable"}
  entry_path = source_manifest[0][0]
  if entry_path == nil
    return {ok: false, reason: "entry path is unavailable"}
  paths = {}
  prefix_count = 0
  entry_seen = false
  i = 0
  while i < expressions.size()
    expr = expressions[i]
    path = ast_get(expr, :source_path)
    if path == nil
      return {ok: false, reason: "a user expression has no declaring-file provenance"}
    if path == entry_path
      entry_seen = true
    else
      if entry_seen
        return {ok: false, reason: "library expressions are not a contiguous entry prefix"}
      paths[path] = true
      prefix_count += 1
    i += 1
  if prefix_count == 0 || paths.size() == 0
    return {ok: false, reason: "the entry has no imported library prefix"}
  {ok: true, entry_path: entry_path, paths: paths, prefix_count: prefix_count}

-> incremental_library_cache_manifest_rows(source_manifest, library_paths)
  rows = []
  found = {}
  i = 0
  while i < source_manifest.size()
    item = source_manifest[i]
    if type(item) != "Array" || item.size() != 2
      return nil
    path = item[0]
    if library_paths[path] == true
      mtime = item[1]
      stat = File.stat(path)
      if stat == nil || stat.mtime_ns() == nil || stat.ctime_ns() == nil || stat.size() == nil || mtime != stat.mtime_ns()
        return nil
      digest = incremental_core_cache_file_digest(path, mtime, stat.ctime_ns(), stat.size())
      if digest == nil
        return nil
      rows.push(core_abi_field(path) + core_abi_field(mtime) + core_abi_field(stat.ctime_ns()) + core_abi_field(stat.size()) + core_abi_field(digest))
      found[path] = true
    i += 1
  if found.size() != library_paths.size()
    return nil
  incremental_core_cache_sort_strings(rows)

-> incremental_library_cache_prepare(mod, expressions, source_manifest)
  if env("TUNGSTEN_LIBRARY_WIRE_CACHE") == "0" || env("TUNGSTEN_LIBRARY_WIRE_DISK_CACHE") == "0"
    return incremental_library_cache_set_bypass(mod, "disabled")
  if incremental_library_cache_state[:persistent_dir] == nil || incremental_library_cache_state[:persistent_identity] == nil
    return incremental_library_cache_set_bypass(mod, "persistent cache is unavailable")
  if mod[:protect_core] != true || mod[:method_tables_locked] != true || mod[:core_reuse_contract] != :stable
    return incremental_library_cache_set_bypass(mod, "protected Core and locked method tables are required")
  # A cold Core build has a different pre-canonical string/counter history.
  # Prime that exact artifact first, then bind libraries to its stable boundary.
  if mod[:incremental_core_cache_hit] != true
    return incremental_library_cache_set_bypass(mod, "waiting for a warm Core artifact")

  partition = incremental_library_cache_partition(expressions, source_manifest)
  if partition[:ok] != true
    return incremental_library_cache_set_bypass(mod, partition[:reason])
  paths = partition[:paths]
  prefix_count = partition[:prefix_count]
  if prefix_count < expressions.size() && ast_kind(expressions[prefix_count - 1]) == :compound_assign && ast_kind(expressions[prefix_count]) == :compound_assign
    return incremental_library_cache_set_bypass(mod, "a lowering fusion can cross the library boundary")
  i = 0
  while i < prefix_count
    if !incremental_library_cache_expression_safe?(expressions[i], mod)
      return incremental_library_cache_set_bypass(mod, "library startup can create uncached functions")
    i += 1

  specs = mod[:generic_specialization_order]
  if specs != nil
    i = 0
    while i < specs.size()
      spec_path = ast_get(specs[i], :source_path)
      if paths[spec_path] == true
        return incremental_library_cache_set_bypass(mod, "a cached library generic was specialized by this program")
      i += 1

  rows = incremental_library_cache_manifest_rows(source_manifest, paths)
  if rows == nil
    return incremental_library_cache_set_bypass(mod, "library manifest changed during compilation")
  context_hash = incremental_library_cache_context_digest(mod, expressions)
  if context_hash == nil
    return incremental_library_cache_set_bypass(mod, "ABI context contains an unsupported value")
  key_text = StringBuffer(128 + rows.size() * 96)
  key_text << "library-wire-v1\n"
  key_text << core_abi_field(mod[:incremental_core_cache_key])
  key_text << core_abi_field(mod[:incremental_core_cache_entry][:core_abi_hash])
  key_text << core_abi_field(context_hash)
  key_text << core_abi_field(w_ast_schema_hash_tungsten())
  i = 0
  while i < rows.size()
    key_text << rows[i]
    key_text << "\n"
    i += 1
  key = wyhash64_hex_string(key_text.to_s())
  report = env("TUNGSTEN_LIBRARY_CACHE_KEY_REPORT")
  if report != nil && report != ""
    write_file(report + "." + key, key_text.to_s())
  mod[:incremental_library_cache_key] = key
  mod[:incremental_library_cache_path] = incremental_library_cache_persistent_path(key)
  mod[:incremental_library_cache_paths] = paths
  mod[:incremental_library_cache_prefix_count] = prefix_count
  mod[:incremental_library_cache_file_count] = paths.size()
  mod[:incremental_library_cache_context_hash] = context_hash
  mod[:incremental_library_cache_status] = :prepared
  nil

-> incremental_library_cache_counter_fields
  [:next_bigint_literal, :next_block, :next_ic, :next_call_site, :next_reuse_site, :next_fuse_site, :next_inline_block_id, :next_custom_unit_id]

-> incremental_library_cache_capture_boundary(mod)
  counters = {}
  fields = incremental_library_cache_counter_fields()
  i = 0
  while i < fields.size()
    value = mod[fields[i]]
    if value == nil
      value = 0
    counters[fields[i]] = value
    i += 1
  reuse_sites = []
  i = 0
  while i < mod[:reuse_sites].size()
    reuse_sites.push(mod[:reuse_sites][i])
    i += 1
  used = {}
  if mod[:used_memo_tables] != nil
    keys = mod[:used_memo_tables].keys()
    i = 0
    while i < keys.size()
      used[keys[i]] = mod[:used_memo_tables][keys[i]]
      i += 1
  string_texts = []
  i = 0
  while i < mod[:strings].size()
    string_texts.push(mod[:strings][i][:text])
    i += 1
  {counters: counters, reuse_sites: reuse_sites, used_memo_tables: used, string_texts: string_texts}

-> incremental_library_cache_state_fields
  [
    :known_calls,
    :known_fn_param_counts,
    :known_fn_splat_info,
    :known_static_methods,
    :known_fn_overloads,
    :known_typed_overload_counts,
    :known_unique_typed_overload_keys,
    :known_unique_typed_overload_param_types,
    :known_pure_calls,
    :raw_callable_fns,
    :raw_fn_param_kinds,
    :fn_return_types,
    :return_class_sets,
    :return_class_set_workers,
    :no_raise_workers,
    :class_super_names,
    :class_method_fn_names,
    :class_constructor_fn_names,
    :class_static_new,
    :fn_memo_tables,
    :used_memo_tables,
    :cvar_globals,
    :top_level_vars,
    :top_level_var_types,
    :top_level_const_values,
    :top_level_static_types,
    :ccall_fns,
    :math_alias_fns,
    :small_array_consts,
    :custom_units,
    :view_layouts,
    :tag_report_gates,
    :tag_report_infix,
    :reuse_sites,
    :specialized_methods,
    :used_builtin_classes
  ]

-> incremental_library_cache_capture_state(mod)
  snapshot = {}
  fields = incremental_library_cache_state_fields()
  i = 0
  while i < fields.size()
    snapshot[fields[i]] = mod[fields[i]]
    i += 1
  snapshot

-> incremental_library_cache_entry_valid?(entry, mod)
  if type(entry) != "Hash" || entry[:version] != "library-wire-v1" || entry[:key] != mod[:incremental_library_cache_key] || entry[:core_key] != mod[:incremental_core_cache_key] || entry[:core_abi_hash] != mod[:incremental_core_cache_entry][:core_abi_hash] || entry[:context_hash] != mod[:incremental_library_cache_context_hash]
    return false
  if type(entry[:functions]) != "Array" || type(entry[:finish]) != "Hash" || type(entry[:state]) != "Hash" || type(entry[:start_hash]) != "String" || type(entry[:start_function_count]) != "Int"
    return false
  finish = entry[:finish]
  if type(finish[:counters]) != "Hash" || type(finish[:string_texts]) != "Array"
    return false
  counter_fields = incremental_library_cache_counter_fields()
  i = 0
  while i < counter_fields.size()
    if type(finish[:counters][counter_fields[i]]) != "Int"
      return false
    i += 1
  state_fields = incremental_library_cache_state_fields()
  i = 0
  while i < state_fields.size()
    if !entry[:state].has_key?(state_fields[i])
      return false
    i += 1
  i = 0
  while i < entry[:functions].size()
    func = entry[:functions][i]
    if ccall_nobox("w_is_wire_extern", func) != 1 || type(func[:name]) != "String" || type(func[:blocks]) != "Array" || type(func[:source_path]) != "String"
      return false
    bi = 0
    while bi < func[:blocks].size()
      block = func[:blocks][bi]
      if ccall_nobox("w_is_wire_extern", block) != 1 || type(block[:instructions]) != "Array"
        return false
      ii = 0
      while ii < block[:instructions].size()
        if ccall_nobox("w_is_wire_extern", block[:instructions][ii]) != 1
          return false
        ii += 1
      bi += 1
    i += 1
  true

-> incremental_library_cache_seed_finish_strings(mod, finish)
  target = finish[:string_texts]
  if type(target) != "Array" || target.size() < mod[:strings].size()
    return false
  i = 0
  while i < mod[:strings].size()
    if mod[:strings][i][:text] != target[i]
      return false
    i += 1
  while i < target.size()
    id = module_string_constant(mod, target[i])
    if id != i
      return false
    i += 1
  true

-> incremental_library_cache_begin(mod)
  if mod[:incremental_library_cache_status] != :prepared
    return nil
  start = incremental_library_cache_capture_boundary(mod)
  start_hash = incremental_library_cache_digest(start)
  if start_hash == nil
    return incremental_library_cache_set_bypass(mod, "the Core boundary cannot be fingerprinted")
  mod[:incremental_library_cache_start_hash] = start_hash
  mod[:incremental_library_cache_start_function_count] = mod[:functions].size()

  path = mod[:incremental_library_cache_path]
  entry = ccall("w_core_cache_read", path)
  if !incremental_library_cache_entry_valid?(entry, mod)
    mod[:incremental_library_cache_status] = :miss
    incremental_library_cache_state[:misses] = incremental_library_cache_state[:misses] + 1
    return nil
  if entry[:start_hash] != start_hash || entry[:start_function_count] != mod[:functions].size()
    mod[:incremental_library_cache_status] = :miss
    mod[:incremental_library_cache_reason] = "the warm Core boundary changed"
    incremental_library_cache_state[:misses] = incremental_library_cache_state[:misses] + 1
    return nil
  if !incremental_library_cache_seed_finish_strings(mod, entry[:finish])
    mod[:incremental_library_cache_status] = :miss
    mod[:incremental_library_cache_reason] = "the cached string boundary changed"
    incremental_library_cache_state[:misses] = incremental_library_cache_state[:misses] + 1
    return nil

  functions = entry[:functions]
  i = 0
  while i < functions.size()
    mod[:functions].push(functions[i])
    i += 1
  mod[:incremental_library_cache_entry] = entry
  mod[:incremental_library_cache_hit] = true
  mod[:incremental_library_cache_function_count] = functions.size()
  mod[:incremental_library_cache_status] = :hit
  incremental_library_cache_state[:hits] = incremental_library_cache_state[:hits] + 1
  nil

-> incremental_library_cache_skip_definition?(mod, definition_path)
  mod[:incremental_library_cache_hit] == true && mod[:incremental_library_cache_paths] != nil && mod[:incremental_library_cache_paths][definition_path] == true

-> incremental_library_cache_apply_finish(mod, entry)
  finish = entry[:finish]
  fields = incremental_library_cache_counter_fields()
  i = 0
  while i < fields.size()
    field = fields[i]
    current = mod[field]
    if current == nil
      current = 0
    target = finish[:counters][field]
    if target == nil || current > target
      raise "incremental library counter mismatch for " + field.to_s()
    mod[field] = target
    i += 1
  state = entry[:state]
  fields = incremental_library_cache_state_fields()
  i = 0
  while i < fields.size()
    field = fields[i]
    mod[field] = state[field]
    i += 1
  nil

-> incremental_library_cache_collect_functions(mod)
  functions = []
  paths = mod[:incremental_library_cache_paths]
  start = mod[:incremental_library_cache_start_function_count]
  if start == nil
    return nil
  i = start
  while i < mod[:functions].size()
    func = mod[:functions][i]
    if func[:is_toplevel] == true || paths[func[:source_path]] != true
      return nil
    functions.push(func)
    i += 1
  functions

-> incremental_library_cache_finish(mod)
  if mod[:incremental_library_cache_finished] == true
    return nil
  status = mod[:incremental_library_cache_status]
  if !(status in (:hit :miss))
    return nil
  mod[:incremental_library_cache_finished] = true
  if status == :hit
    incremental_library_cache_apply_finish(mod, mod[:incremental_library_cache_entry])
    return nil

  functions = incremental_library_cache_collect_functions(mod)
  if functions == nil
    mod[:incremental_library_cache_reason] = "a library definition produced a function with external provenance"
    return nil
  if functions.size() == 0
    mod[:incremental_library_cache_reason] = "the library cohort produced no WIRE functions"
    return nil
  finish = incremental_library_cache_capture_boundary(mod)
  entry = {
    version: "library-wire-v1",
    key: mod[:incremental_library_cache_key],
    core_key: mod[:incremental_core_cache_key],
    core_abi_hash: mod[:incremental_core_cache_entry][:core_abi_hash],
    context_hash: mod[:incremental_library_cache_context_hash],
    start_hash: mod[:incremental_library_cache_start_hash],
    start_function_count: mod[:incremental_library_cache_start_function_count],
    finish: finish,
    state: incremental_library_cache_capture_state(mod),
    functions: functions,
    function_count: functions.size(),
    file_count: mod[:incremental_library_cache_file_count]
  }
  if ccall("w_core_cache_write", mod[:incremental_library_cache_path], entry) == true
    mod[:incremental_library_cache_stored] = true
    mod[:incremental_library_cache_function_count] = functions.size()
    incremental_library_cache_state[:stores] = incremental_library_cache_state[:stores] + 1
  nil

-> incremental_library_cache_maybe_finish(ctx, statements, completed)
  target = ctx[:incremental_library_cache_statements]
  if target == nil || wvalue_bits(target) != wvalue_bits(statements)
    return nil
  prefix_count = ctx[:incremental_library_cache_prefix_count]
  if prefix_count != nil && completed >= prefix_count
    incremental_library_cache_finish(ctx[:mod])
  nil

-> incremental_library_cache_verbose_text(mod)
  status = mod[:incremental_library_cache_status]
  if status == :hit
    return "  library WIRE cache: hit " + mod[:incremental_library_cache_key] + " (" + mod[:incremental_library_cache_function_count].to_s() + " functions, " + mod[:incremental_library_cache_file_count].to_s() + " files)"
  if status == :miss
    suffix = mod[:incremental_library_cache_stored] == true ? ", disk stored" : ""
    count = mod[:incremental_library_cache_function_count]
    if count == nil
      count = 0
    return "  library WIRE cache: miss " + mod[:incremental_library_cache_key] + " (" + count.to_s() + " functions" + suffix + ")"
  reason = mod[:incremental_library_cache_reason]
  if reason == nil
    reason = "not eligible"
  "  library WIRE cache: bypass (" + reason + ")"
