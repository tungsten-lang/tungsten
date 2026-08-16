# Lowered Core cache — retain post-mid-end Core WIRE across compile-batch
# members and reconstruct the same immutable graph in later compiler
# processes, while every entry program gets a fresh main/user overlay.
# Programs that do not satisfy the checked stable-Core contract keep the
# ordinary monolithic path.

incremental_core_cache_state = {
  entries: {},
  digest_memo: {},
  retain_mark: 0,
  persistent_dir: nil,
  persistent_identity: nil,
  hits: 0,
  misses: 0,
  stores: 0,
  disk_hits: 0,
  disk_misses: 0,
  disk_stores: 0
}

-> incremental_core_cache_configure_persistent(dir, identity)
  incremental_core_cache_state[:persistent_dir] = dir
  incremental_core_cache_state[:persistent_identity] = identity
  nil

-> incremental_core_cache_persistent_path(key)
  dir = incremental_core_cache_state[:persistent_dir]
  identity = incremental_core_cache_state[:persistent_identity]
  if dir == nil || identity == nil
    return nil
  dir + "/core-wire-" + identity + "-" + key + ".twc"

-> incremental_core_cache_entry_valid?(entry, key)
  if type(entry) != "Hash" || entry[:key] != key || type(entry[:core_abi_hash]) != "String"
    return false
  if type(entry[:functions]) != "Array" || type(entry[:strings]) != "Array" || type(entry[:name_map]) != "Hash" || type(entry[:fn_hashes]) != "Hash" || type(entry[:counter_prefix]) != "Hash"
    return false
  i = 0
  while i < entry[:strings].size()
    item = entry[:strings][i]
    if type(item) != "Hash" || item[:id] != i || type(item[:text]) != "String"
      return false
    i += 1
  i = 0
  while i < entry[:functions].size()
    func = entry[:functions][i]
    if ccall_nobox("w_is_wire_extern", func) != 1 || type(func[:name]) != "String" || type(func[:original_name]) != "String" || type(func[:params]) != "Array" || type(func[:extra_params]) != "Array" || type(func[:return_type]) != "String" || type(func[:blocks]) != "Array" || type(func[:dynamic_method_calls]) != "Array" || type(func[:dynamic_method_call_keys]) != "Hash"
      return false
    bi = 0
    while bi < func[:blocks].size()
      block = func[:blocks][bi]
      if ccall_nobox("w_is_wire_extern", block) != 1 || type(block[:label]) != "String" || type(block[:instructions]) != "Array"
        return false
      ii = 0
      while ii < block[:instructions].size()
        if ccall_nobox("w_is_wire_extern", block[:instructions][ii]) != 1
          return false
        ii += 1
      bi += 1
    i += 1
  true

# Keep the cache key independent of loader/autoload traversal order. Use an
# explicit lexical insertion sort here: the generic Core Array#sort may select
# different native algorithms across compiler modes, while this closure is
# small (tens of files) and key construction is not a hot O(n log n) problem.
-> incremental_core_cache_sort_strings(values)
  i = 1
  while i < values.size()
    current = values[i]
    j = i
    while j > 0 && current < values[j - 1]
      values[j] = values[j - 1]
      j -= 1
    values[j] = current
    i += 1
  values

-> incremental_core_cache_contracts(expressions)
  found = {protect: false, types: false, methods: false}
  i = 0
  while i < expressions.size()
    name = lowering_contract_name(expressions[i])
    if name == "PROTECT_THE_CORE!"
      found[:protect] = true
    elsif name == "STOP_THE_PRESS!"
      found[:types] = true
    elsif name == "LOCK_THE_DOORS!"
      found[:types] = true
      found[:methods] = true
    i += 1
  found

-> incremental_core_cache_file_digest(path, mtime, ctime, size)
  memo = incremental_core_cache_state[:digest_memo][path]
  if memo != nil && memo[:mtime] == mtime && memo[:ctime] == ctime && memo[:size] == size
    return memo[:digest]
  digest = digest_file64(path)
  if digest == nil
    return nil
  text = u64_hex(digest)
  incremental_core_cache_state[:digest_memo][path] = {
    mtime: mtime,
    ctime: ctime,
    size: size,
    digest: text
  }
  text

-> incremental_core_cache_manifest_rows(source_manifest)
  if source_manifest == nil || type(source_manifest) != "Array"
    return nil
  rows = []
  i = 0
  while i < source_manifest.size()
    entry = source_manifest[i]
    if type(entry) != "Array" || entry.size() != 2
      return nil
    path = entry[0]
    if core_source_path?(path)
      mtime = entry[1]
      stat = File.stat(path)
      if stat == nil
        return nil
      current_mtime = stat.mtime_ns()
      size = stat.size()
      ctime = stat.ctime_ns()
      # The manifest describes the source that was parsed. If the file moved
      # while that parse was in flight, bypass reuse rather than key old AST
      # data with the new on-disk digest.
      if mtime == nil || current_mtime == nil || current_mtime != mtime || size == nil || ctime == nil
        return nil
      digest = incremental_core_cache_file_digest(path, mtime, ctime, size)
      if digest == nil
        return nil
      rows.push(core_abi_field(path) + core_abi_field(mtime) + core_abi_field(ctime) + core_abi_field(size) + core_abi_field(digest))
    i += 1
  if rows.size() == 0
    return nil
  incremental_core_cache_sort_strings(rows)

-> incremental_core_cache_defines_row(build_defines)
  defs = build_defines
  if defs == nil || defs.size() == 0
    defs = parse_build_defines_env()
  keys = defs.keys().sort()
  row = StringBuffer(64 + keys.size() * 24)
  row << core_abi_field(keys.size())
  i = 0
  while i < keys.size()
    row << core_abi_field(keys[i])
    row << core_abi_field(defs[keys[i]])
    i += 1
  row.to_s()

-> incremental_core_cache_env_row(name)
  value = env(name)
  if value == nil
    value = ""
  core_abi_field(name) + core_abi_field(value)

-> incremental_core_cache_prepare(ast, source_manifest, fast_mode, build_defines, math_mode, no_static_slab, release_mode)
  retain_mark = incremental_core_cache_state[:retain_mark]
  disabled = env("TUNGSTEN_CORE_LOWER_CACHE") == "0"
  if disabled || ast == nil || ast.expressions == nil
    return {enabled: false, retain_mark: retain_mark, reason: "disabled or missing AST"}

  contracts = incremental_core_cache_contracts(ast.expressions)
  if contracts[:protect] != true
    return {enabled: false, retain_mark: retain_mark, reason: "PROTECT_THE_CORE! is absent"}

  rows = incremental_core_cache_manifest_rows(source_manifest)
  if rows == nil
    return {enabled: false, retain_mark: retain_mark, reason: "Core closure manifest is unavailable"}

  key_text = StringBuffer(rows.size() * 96 + 256)
  # v2 adds literal dynamic-send summaries to each persisted function. Older
  # snapshots cannot safely participate in closed-world Core reachability.
  key_text << "lowered-core-v2\n"
  i = 0
  while i < rows.size()
    key_text << rows[i]
    key_text << "\n"
    i += 1
  key_text << core_abi_field(fast_mode)
  key_text << core_abi_field(math_mode)
  key_text << core_abi_field(no_static_slab)
  key_text << core_abi_field(release_mode)
  key_text << core_abi_field(contracts[:types])
  key_text << core_abi_field(contracts[:methods])
  key_text << incremental_core_cache_defines_row(build_defines)
  # Embedders may perform several compiles in one process while changing
  # tuning variables between calls. Include every switch that can affect
  # lowered Core WIRE, its post-pass shape, or its stable symbol names.
  lowering_env = [
    "TUNGSTEN_PARAM_INFER",
    "TUNGSTEN_FREE",
    "TUNGSTEN_DEMOTE_TOP_LEVEL",
    "TUNGSTEN_CARRY_UNROLL",
    "TUNGSTEN_BIGINT_LITERAL_CACHE",
    "TUNGSTEN_BIGINT_DEST_OPS",
    "TUNGSTEN_BIGINT_MUTATE_UNIQUE",
    "TUNGSTEN_BIGINT_SUB_DEST",
    "TUNGSTEN_BIGINT_ADDMUL_FUSION",
    "TUNGSTEN_BIGINT_MOD_RING_FUSION",
    "TUNGSTEN_BIGINT_SMALL_MUT",
    "TUNGSTEN_BIGINT_MOD_POW2",
    "TUNGSTEN_BIGINT_DIV_POW2",
    "TUNGSTEN_BIGINT_SQR_MUT",
    "TUNGSTEN_BIGINT_MOD_MUT",
    "TUNGSTEN_BIGINT_BITWISE_MUT",
    "TUNGSTEN_BIGINT_SHIFT_MUT",
    "TUNGSTEN_BIGINT_CMP0",
    "TUNGSTEN_SYMBOL_PREFIX_HEX",
    "TUNGSTEN_SERVICE_BINDINGS",
    "TUNGSTEN_TARGET",
    "TUNGSTEN_CPU",
    "TUNGSTEN_CROSS_TARGET",
    "TUNGSTEN_MARCH_ARGS"
  ]
  i = 0
  while i < lowering_env.size()
    key_text << incremental_core_cache_env_row(lowering_env[i])
    i += 1
  key_text << core_abi_field(w_ast_schema_hash_tungsten())

  key = wyhash64_hex_string(key_text.to_s())
  report = env("TUNGSTEN_CORE_CACHE_KEY_REPORT")
  if report != nil && report != ""
    write_file(report + "." + key, key_text.to_s())
  entry = incremental_core_cache_state[:entries][key]
  persistent_status = :memory
  if entry == nil
    persistent_path = incremental_core_cache_persistent_path(key)
    if persistent_path != nil
      loaded = ccall("w_core_cache_read", persistent_path)
      if incremental_core_cache_entry_valid?(loaded, key)
        entry = loaded
        incremental_core_cache_state[:entries][key] = entry
        retain_mark = ccall("w_int", ccall_nobox("w_wire_store_mark"))
        incremental_core_cache_state[:retain_mark] = retain_mark
        incremental_core_cache_state[:disk_hits] = incremental_core_cache_state[:disk_hits] + 1
        persistent_status = :hit
      else
        incremental_core_cache_state[:disk_misses] = incremental_core_cache_state[:disk_misses] + 1
        persistent_status = :miss
  {
    enabled: true,
    retain_mark: retain_mark,
    key: key,
    entry: entry,
    closure_files: rows.size(),
    persistent_status: persistent_status
  }

-> incremental_core_cache_seed_strings(mod, entry)
  strings = []
  by_text = {}
  cached = entry[:strings]
  i = 0
  while i < cached.size()
    text = cached[i][:text]
    strings.push({id: i, text: text})
    by_text[text] = i
    i += 1
  mod[:strings] = strings
  mod[:string_ids_by_text] = by_text
  mod[:next_string] = strings.size()
  mod[:incremental_core_string_count] = strings.size()
  nil

-> incremental_core_cache_activate(mod, probe)
  if probe == nil || probe[:enabled] != true || mod[:core_reuse_contract] != :stable
    if mod[:protect_core] == true && mod[:core_reuse_contract] != :stable
      mod[:incremental_core_cache_status] = :fallback
    else
      mod[:incremental_core_cache_status] = :bypass
    return nil

  mod[:incremental_core_cache_key] = probe[:key]
  mod[:incremental_core_cache_closure_files] = probe[:closure_files]
  mod[:incremental_core_cache_persistent_status] = probe[:persistent_status]
  entry = probe[:entry]
  if entry == nil
    mod[:incremental_core_cache_status] = :miss
    incremental_core_cache_state[:misses] = incremental_core_cache_state[:misses] + 1
    return nil

  incremental_core_cache_seed_strings(mod, entry)
  mod[:incremental_core_cache_entry] = entry
  mod[:incremental_core_fn_hashes] = entry[:fn_hashes]
  mod[:incremental_core_cache_status] = :hit
  mod[:incremental_core_cache_hit] = true
  incremental_core_cache_state[:hits] = incremental_core_cache_state[:hits] + 1
  nil

-> incremental_core_cache_skip_definition?(mod, definition_path)
  mod[:incremental_core_cache_hit] == true && core_source_path?(definition_path)

-> incremental_core_cache_attach_functions(mod)
  entry = mod[:incremental_core_cache_entry]
  if entry == nil
    return nil
  functions = entry[:functions]
  i = 0
  while i < functions.size()
    mod[:functions].push(functions[i])
    i += 1
  nil

-> incremental_core_cache_counter_fields
  [:next_bigint_literal, :next_block, :next_ic, :next_call_site, :next_reuse_site, :next_fuse_site, :next_inline_block_id]

-> incremental_core_cache_capture_boundary(mod)
  counters = {}
  fields = incremental_core_cache_counter_fields()
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
  memo = {}
  used = mod[:used_memo_tables]
  if used != nil
    keys = used.keys()
    i = 0
    while i < keys.size()
      memo[keys[i]] = used[keys[i]]
      i += 1
  string_texts = []
  i = 0
  while i < mod[:strings].size()
    string_texts.push(mod[:strings][i][:text])
    i += 1
  {
    counters: counters,
    reuse_sites: reuse_sites,
    used_memo_tables: memo,
    string_texts: string_texts
  }

# Core top-level startup is deliberately relowered into each fresh main.
# Apply the cached boundary only after that startup has consumed its ordinary
# ids; user lowering then begins after every id embedded in cached functions.
-> incremental_core_cache_finish_core_partition(mod)
  if mod[:incremental_core_cache_key] == nil
    return nil
  entry = mod[:incremental_core_cache_entry]
  if entry == nil
    mod[:incremental_core_cache_counter_prefix] = incremental_core_cache_capture_boundary(mod)
    return nil
  prefix = entry[:counter_prefix]
  if prefix == nil
    raise "incremental Core cache entry has no counter prefix"
  fields = incremental_core_cache_counter_fields()
  i = 0
  while i < fields.size()
    field = fields[i]
    current = mod[field]
    if current == nil
      current = 0
    target = prefix[:counters][field]
    if target < current
      raise "incremental Core counter mismatch for " + field.to_s()
    mod[field] = target
    i += 1
  reused = []
  i = 0
  while i < prefix[:reuse_sites].size()
    reused.push(prefix[:reuse_sites][i])
    i += 1
  mod[:reuse_sites] = reused
  used = mod[:used_memo_tables]
  if used == nil
    used = {}
    mod[:used_memo_tables] = used
  keys = prefix[:used_memo_tables].keys()
  i = 0
  while i < keys.size()
    used[keys[i]] = prefix[:used_memo_tables][keys[i]]
    i += 1
  mod[:incremental_core_cache_counter_prefix] = prefix
  nil

-> incremental_core_cache_function?(func)
  func[:is_toplevel] != true && core_source_path?(func[:source_path])

-> incremental_core_cache_order_and_mark_functions(mod)
  if mod[:incremental_core_cache_key] == nil
    return nil
  roots = []
  core = []
  user = []
  i = 0
  while i < mod[:functions].size()
    func = mod[:functions][i]
    if func[:is_toplevel] == true
      roots.push(func)
    elsif incremental_core_cache_function?(func)
      core.push(func)
      func[:llvm_internal] = true
      if mod[:incremental_core_cache_hit] != true
        func[:incremental_core_candidate] = true
    else
      user.push(func)
    i += 1
  ordered = []
  i = 0
  while i < roots.size()
    ordered.push(roots[i])
    i += 1
  i = 0
  while i < core.size()
    ordered.push(core[i])
    i += 1
  i = 0
  while i < user.size()
    ordered.push(user[i])
    i += 1
  mod[:functions] = ordered
  mod[:incremental_core_function_count] = core.size()
  nil

-> incremental_core_cache_string_text_by_id(mod)
  index = {}
  i = 0
  while i < mod[:strings].size()
    index[mod[:strings][i][:id]] = mod[:strings][i][:text]
    i += 1
  index

-> incremental_core_cache_collect_inst_strings(inst, text_by_id, texts)
  fields = [:string_id, :str_id, :name_str_id, :method_str_id, :file_str_id, :ivar_str_id]
  i = 0
  while i < fields.size()
    id = wire_get(inst, fields[i])
    if id != nil && text_by_id[id] != nil
      texts[text_by_id[id]] = true
    i += 1
  cases = wire_get(inst, :cases)
  if cases != nil
    i = 0
    while i < wire_sequence_size(cases)
      item = wire_sequence_get(cases, i)
      id = item[:string_id]
      if id != nil && text_by_id[id] != nil
        texts[text_by_id[id]] = true
      i += 1
  nil

-> incremental_core_cache_rewrite_inst_strings(inst, remap)
  fields = [:string_id, :str_id, :name_str_id, :method_str_id, :file_str_id, :ivar_str_id]
  i = 0
  while i < fields.size()
    old_id = wire_get(inst, fields[i])
    if old_id != nil
      new_id = remap[old_id]
      if new_id != nil && new_id != old_id
        wire_set(inst, fields[i], new_id)
    i += 1
  cases = wire_get(inst, :cases)
  if cases != nil
    i = 0
    while i < wire_sequence_size(cases)
      item = wire_sequence_get(cases, i)
      old_id = item[:string_id]
      if old_id != nil && remap[old_id] != nil
        item[:string_id] = remap[old_id]
      i += 1
  nil

# Cached instructions embed module string ids. Put every Core-referenced text
# in a lexical prefix so those ids are independent of entry-program lowering.
-> incremental_core_cache_canonicalize_strings(mod)
  if mod[:incremental_core_cache_key] == nil
    return nil
  text_by_id = incremental_core_cache_string_text_by_id(mod)
  core_texts = {}
  boundary = mod[:incremental_core_cache_counter_prefix]
  if boundary != nil && boundary[:string_texts] != nil
    i = 0
    while i < boundary[:string_texts].size()
      core_texts[boundary[:string_texts][i]] = true
      i += 1
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    if incremental_core_cache_function?(func)
      bi = 0
      while bi < func[:blocks].size()
        instrs = func[:blocks][bi][:instructions]
        ii = 0
        while ii < instrs.size()
          incremental_core_cache_collect_inst_strings(instrs[ii], text_by_id, core_texts)
          ii += 1
        bi += 1
    fi += 1

  prefix_texts = core_texts.keys().sort()
  new_strings = []
  by_text = {}
  i = 0
  while i < prefix_texts.size()
    by_text[prefix_texts[i]] = new_strings.size()
    new_strings.push({id: new_strings.size(), text: prefix_texts[i]})
    i += 1
  i = 0
  while i < mod[:strings].size()
    text = mod[:strings][i][:text]
    if by_text[text] == nil
      by_text[text] = new_strings.size()
      new_strings.push({id: new_strings.size(), text: text})
    i += 1

  remap = {}
  i = 0
  while i < mod[:strings].size()
    old = mod[:strings][i]
    remap[old[:id]] = by_text[old[:text]]
    i += 1
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    bi = 0
    while bi < func[:blocks].size()
      instrs = func[:blocks][bi][:instructions]
      ii = 0
      while ii < instrs.size()
        incremental_core_cache_rewrite_inst_strings(instrs[ii], remap)
        ii += 1
      bi += 1
    fi += 1

  mod[:strings] = new_strings
  mod[:string_ids_by_text] = by_text
  mod[:next_string] = new_strings.size()
  mod[:incremental_core_string_count] = prefix_texts.size()
  nil

-> incremental_core_cache_validate_hit(mod)
  entry = mod[:incremental_core_cache_entry]
  if entry != nil && entry[:core_abi_hash] != mod[:core_abi_hash]
    raise "incremental Core ABI mismatch for cache key " + mod[:incremental_core_cache_key] + ": cached=" + entry[:core_abi_hash] + " current=" + mod[:core_abi_hash]
  nil

# Called only after all destructive mid-end passes and emission have finished.
# The retained watermark includes some first-program overlay records; cache
# entries reference only the selected Core functions and canonical strings.
-> incremental_core_cache_finalize(mod)
  if mod[:incremental_core_cache_status] != :miss
    return nil
  functions = []
  final_name_map = {}
  core_fn_hashes = {}
  i = 0
  while i < mod[:functions].size()
    func = mod[:functions][i]
    if func[:incremental_core_candidate] == true
      original_name = func[:original_name]
      if original_name == nil
        original_name = func[:incremental_core_hash_source_name]
      if original_name != func[:name]
        rename_map_put(final_name_map, original_name, func[:name])
      hash_source = func[:incremental_core_hash_source_name]
      if hash_source != nil && hash_source != func[:name] && hash_source != original_name
        rename_map_put(final_name_map, hash_source, func[:name])
      hash_value = fn_hash_get(mod[:fn_hashes], hash_source)
      if hash_value != nil
        fn_hash_put(core_fn_hashes, func[:name], hash_value)
      func[:incremental_core_candidate] = nil
      func[:incremental_core_frozen] = true
      functions.push(func)
    i += 1

  string_count = mod[:incremental_core_string_count]
  strings = []
  i = 0
  while i < string_count
    strings.push({id: i, text: mod[:strings][i][:text]})
    i += 1
  entry = {
    key: mod[:incremental_core_cache_key],
    core_abi_hash: mod[:core_abi_hash],
    functions: functions,
    strings: strings,
    name_map: final_name_map,
    fn_hashes: core_fn_hashes,
    counter_prefix: mod[:incremental_core_cache_counter_prefix]
  }
  incremental_core_cache_state[:entries][mod[:incremental_core_cache_key]] = entry
  mark = ccall("w_int", ccall_nobox("w_wire_store_mark"))
  incremental_core_cache_state[:retain_mark] = mark
  incremental_core_cache_state[:stores] = incremental_core_cache_state[:stores] + 1
  persistent_path = incremental_core_cache_persistent_path(mod[:incremental_core_cache_key])
  if persistent_path != nil
    if ccall("w_core_cache_write", persistent_path, entry) == true
      incremental_core_cache_state[:disk_stores] = incremental_core_cache_state[:disk_stores] + 1
      mod[:incremental_core_cache_persistent_stored] = true
    else
      mod[:incremental_core_cache_persistent_stored] = false
  mod[:incremental_core_cache_stored] = true
  mod[:incremental_core_cache_retain_mark] = mark
  nil

-> incremental_core_cache_verbose_text(mod)
  status = mod[:incremental_core_cache_status]
  function_count = mod[:incremental_core_function_count]
  if function_count == nil || function_count == 0
    function_count = mod[:core_abi_function_count]
  if status == :hit
    source = mod[:incremental_core_cache_persistent_status] == :hit ? "disk" : "memory"
    return "  core cache: hit " + mod[:incremental_core_cache_key] + " (" + function_count.to_s() + " functions, " + source + ")"
  if status == :miss
    stored = mod[:incremental_core_cache_persistent_stored]
    suffix = stored == true ? ", disk stored" : ""
    return "  core cache: miss " + mod[:incremental_core_cache_key] + " (" + function_count.to_s() + " functions" + suffix + ")"
  if status == :fallback
    return "  core cache: fallback (" + mod[:core_reuse_fallback_reason] + ")"
  "  core cache: bypass"
