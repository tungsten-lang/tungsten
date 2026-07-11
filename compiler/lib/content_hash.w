# Content-addressable functions — hash function bodies for deduplication.
# Two functions with identical bodies compile to one LLVM function.
# Uses wyhash64 for consistent hashing.

use runtime_types
use hashing

# Normalize a temp name to a sequential index.
# First occurrence of a temp gets the next index.
# Returns nil for literal values (not temp references).
-> norm_temp(name, temp_map)
  if name == nil
    return -1

  existing = temp_map[name]

  if existing != nil
    return existing

  idx = temp_map[:next_idx]

  if idx == nil
    idx = 0

  temp_map[name] = idx
  temp_map[:next_idx] = idx + 1
  idx

-> canonical_op_code(op, op_codes)
  existing = op_codes[op]
  if existing != nil
    return existing
  next_code = op_codes[:next_code]
  if next_code == nil
    next_code = 0
  op_codes[op] = next_code
  op_codes[:next_code] = next_code + 1
  next_code


# Hash one instruction canonically.
# Encode a value (temp or literal) into the canonical string.
-> encode_val(buf, val, temp_map)
  if val == nil
    buf << "_"
    return nil
  text = val.to_s()
  if text.size() > 0 && text.slice(0, 1) == "%"
    buf << "t"
    buf << norm_temp(text, temp_map).to_s()
  else
    buf << "l"
    buf << text
  buf << ","

# Encode one instruction into the canonical string buffer.
-> encode_inst(inst, buf, temp_map, label_map, fn_hashes, mod, self_name, op_codes)
  op = inst[:op]
  buf << "o"
  buf << canonical_op_code(op, op_codes).to_s()

  # Register temp output
  if inst[:temp] != nil
    norm_temp(inst[:temp], temp_map)

  if op in (:call_direct_i64 :call_direct_void :call_direct_ptr)
    callee = inst[:name]

    if callee == self_name
      buf << "@R"
    elsif fn_hashes[callee] != nil
      buf << "@"
      buf << fn_hashes[callee]
    else
      buf << "@"
      buf << callee

    args = inst[:args]

    if args != nil
      ai = 0
      while ai < args.size()
        encode_val(buf, args[ai], temp_map)
        ai += 1

    buf << ";"
    return nil

  if op == :call_method_i64
    encode_val(buf, inst[:receiver], temp_map)
    encode_val(buf, inst[:method_name_val], temp_map)
    args = inst[:args]

    if args != nil
      ai = 0
      while ai < args.size()
        encode_val(buf, args[ai], temp_map)
        ai += 1

    buf << ";"
    return nil

  if op == :closure_new
    callee = inst[:fn_name]
    if fn_hashes[callee] != nil
      buf << "@"
      buf << fn_hashes[callee]
    else
      buf << "@"
      buf << callee
    buf << "c"
    buf << inst[:capture_count].to_s()
    buf << ";"
    return nil

  if op in (:string_i64 :symbol_i64)
    str_idx = mod[:string_index]
    if str_idx != nil
      text = str_idx[inst[:string_id]]
      if text != nil
        buf << "\""
        buf << text
        buf << "\""
    buf << ";"
    return nil

  if op == :br
    idx = label_map[inst[:label]]
    if idx != nil
      buf << ">"
      buf << idx.to_s()
    buf << ";"
    return nil

  if op == :cond_br
    encode_val(buf, inst[:cond], temp_map)
    idx1 = label_map[inst[:then_label]]
    idx2 = label_map[inst[:else_label]]
    if idx1 != nil
      buf << ">"
      buf << idx1.to_s()
    buf << "/"
    if idx2 != nil
      buf << idx2.to_s()
    buf << ";"
    return nil

  if op in (:ret_i64 :ret_i32)
    encode_val(buf, inst[:value], temp_map)
    buf << ";"
    return nil

  if op == :phi_ssa
    incoming = inst[:incoming]
    if incoming != nil
      i = 0
      while i < incoming.size()
        encode_val(buf, incoming[i], temp_map)
        idx = label_map[incoming[i + 1]]

        if idx != nil
          buf << ">"
          buf << idx.to_s()
        i += 2

    buf << ";"
    return nil

  # Generic: encode known operand fields
  if inst[:value] != nil
    encode_val(buf, inst[:value], temp_map)
  if inst[:lhs] != nil
    encode_val(buf, inst[:lhs], temp_map)
  if inst[:rhs] != nil
    encode_val(buf, inst[:rhs], temp_map)
  if inst[:ptr] != nil
    buf << "p"
    buf << inst[:ptr]
  if inst[:index] != nil
    buf << "I"
    encode_val(buf, inst[:index].to_s(), temp_map)
  if inst[:raw] != nil
    buf << "r"
    buf << inst[:raw].to_s()
  if inst[:pred] != nil
    buf << "P"
    buf << inst[:pred]
  if inst[:self_reg] != nil
    encode_val(buf, inst[:self_reg], temp_map)
  if inst[:cond] != nil
    encode_val(buf, inst[:cond], temp_map)
  if inst[:then_val] != nil
    encode_val(buf, inst[:then_val], temp_map)
  if inst[:else_val] != nil
    encode_val(buf, inst[:else_val], temp_map)
  if inst[:offset] != nil
    buf << "O"
    buf << inst[:offset].to_s()
  if inst[:str_id] != nil
    buf << "S"
    buf << inst[:str_id].to_s()
  if inst[:byte_len] != nil
    buf << "B"
    buf << inst[:byte_len].to_s()
  if inst[:arity] != nil
    buf << "A"
    buf << inst[:arity].to_s()
  if inst[:class_name] != nil
    buf << "C"
    buf << inst[:class_name]
  if inst[:name] != nil && op != :call_direct_i64 && op != :call_direct_void && op != :call_direct_ptr
    buf << "N"
    buf << inst[:name]
  if inst[:cvar_key] != nil
    buf << "V"
    buf << inst[:cvar_key]
  if inst[:offset] != nil
    buf << "O"
    buf << inst[:offset].to_s()
  if inst[:bits] != nil
    buf << "W"
    buf << inst[:bits].to_s()
  if inst[:signed] != nil
    if inst[:signed] == true
      buf << "Gs"
    else
      buf << "Gu"
  # Inline typed-array load/store operands (big_array_get_inline / set): the
  # array and index temps distinguish reads of DIFFERENT arrays/positions.
  # Without these, two such functions hash identically and get wrongly merged
  # by function dedup, so one reads the wrong array at runtime.
  if inst[:arr] != nil
    buf << "ar"
    encode_val(buf, inst[:arr], temp_map)
  if inst[:idx] != nil
    buf << "ix"
    encode_val(buf, inst[:idx], temp_map)
  if inst[:idx_raw] != nil
    if inst[:idx_raw] == true
      buf << "ir1"
    else
      buf << "ir0"
  buf << ";"

# Hash an entire function canonically.
-> canonical_hash(func, mod, fn_hashes, op_codes)
  # Build a canonical string representation, then hash it with wyhash64.
  instr_count = 0
  bi = 0
  while bi < func[:blocks].size()
    instr_count = instr_count + func[:blocks][bi][:instructions].size()
    bi += 1
  buf = StringBuffer(64 + instr_count * 24)
  buf << func[:params].size().to_s()
  buf << "|"
  extra = func[:extra_params]
  if extra != nil
    i = 0
    while i < extra.size()
      buf << extra[i][:type]
      buf << ","
      i += 1
  buf << "|"
  buf << func[:return_type]
  buf << "|"

  # Build label map: label → sequential index
  label_map = {}
  bi = 0
  while bi < func[:blocks].size()
    label_map[func[:blocks][bi][:label]] = bi
    bi += 1

  # Build temp map
  temp_map = {next_idx: func[:params].size()}
  pi = 0
  while pi < func[:params].size()
    temp_map["%" + func[:params][pi]] = pi
    pi += 1

  # Encode all blocks
  bi = 0
  while bi < func[:blocks].size()
    buf << "B"
    instrs = func[:blocks][bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      if inst[:op] != :scope_push && inst[:op] != :scope_pop
        encode_inst(inst, buf, temp_map, label_map, fn_hashes, mod, func[:name], op_codes)
      ii += 1
    bi += 1
  encoded = buf.to_s()
  wyhash64_hex_string(encoded)

# Rewrite all function name references in a module.
-> rewrite_references(mod, rename_map)
  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    bi = 0
    while bi < func[:blocks].size()
      instrs = func[:blocks][bi][:instructions]
      ii = 0
      while ii < instrs.size()
        inst = instrs[ii]
        op = inst[:op]
        # Rewrite callee names
        if op in (:call_direct_i64 :call_direct_void :call_direct_ptr)
          replacement = rename_map[inst[:name]]
          if replacement != nil
            inst[:name] = replacement
        if op == :closure_new
          replacement = rename_map[inst[:fn_name]]
          if replacement != nil
            inst[:fn_name] = replacement
        # Fused-loop worker address (ptrtoint ptr @name) — the referenced
        # worker gets compact-symbol renamed like any function.
        if op == :fn_addr_i64
          replacement = rename_map[inst[:name]]
          if replacement != nil
            inst[:name] = replacement
        if op in (:memo_call0_i64 :memo_call1_i64 :memo_call2_i64)
          replacement = rename_map[inst[:fn_name]]
          if replacement != nil
            inst[:fn_name] = replacement
        if op in (:class_add_method :class_add_static_method)
          replacement = rename_map[inst[:fn_name]]
          if replacement != nil
            inst[:fn_name] = replacement
        ii += 1
      bi += 1
    fi += 1

-> rewrite_memo_globals(mod, rename_map)
  memo = mod[:fn_memo_tables]
  global_rename = {}

  if memo != nil
    mk = memo.keys()
    mi = 0
    while mi < mk.size()
      old_global = memo[mk[mi]]
      if old_global != nil
        dot = old_global.index(".memo")
        if dot != nil
          old_fn = old_global.slice(0, dot)
          replacement = rename_map[old_fn]
          if replacement != nil
            new_global = replacement + ".memo"
            global_rename[old_global] = new_global
            memo[mk[mi]] = new_global
      mi += 1

  if global_rename.keys().size() == 0
    return nil

  fi = 0
  while fi < mod[:functions].size()
    func = mod[:functions][fi]
    bi = 0
    while bi < func[:blocks].size()
      instrs = func[:blocks][bi][:instructions]
      ii = 0
      while ii < instrs.size()
        inst = instrs[ii]
        if inst[:global] != nil
          replacement = global_rename[inst[:global]]
          if replacement != nil
            inst[:global] = replacement
        ii += 1
      bi += 1
    fi += 1

-> rewrite_known_name_maps(mod, rename_map)
  kcalls = mod[:known_calls]
  if kcalls != nil
    kk = kcalls.keys()
    ki = 0
    while ki < kk.size()
      replacement = rename_map[kcalls[kk[ki]]]
      if replacement != nil
        kcalls[kk[ki]] = replacement
      ki += 1

  kpure = mod[:known_pure_calls]
  if kpure != nil
    kk = kpure.keys()
    ki = 0
    while ki < kk.size()
      replacement = rename_map[kpure[kk[ki]]]
      if replacement != nil
        kpure[kk[ki]] = replacement
      ki += 1

  statics = mod[:known_static_methods]
  if statics != nil
    sk = statics.keys()
    si = 0
    while si < sk.size()
      info = statics[sk[si]]
      replacement = rename_map[info[:fn_name]]
      if replacement != nil
        info[:fn_name] = replacement
      replacement = rename_map[info[:method_fn_name]]
      if replacement != nil
        info[:method_fn_name] = replacement
      si += 1

-> json_quote(value)
  if value == nil
    return "null"
  text = value.to_s()
  out = StringBuffer(text.size() + 8)
  out << "\""
  chars = text.chars()
  i = 0
  while i < chars.size()
    ch = chars[i]
    case ch
    when "\\"
      out << "\\\\"
    when "\""
      out << "\\\""
    when "\n"
      out << "\\n"
    when "\r"
      out << "\\r"
    when "\t"
      out << "\\t"
    else
      out << ch
    i += 1
  out << "\""
  out.to_s()

-> compact_symbol_for_hash(full_hash, used_symbols, min_prefix)
  prefix_len = min_prefix
  while prefix_len <= full_hash.size()
    candidate = "__wy_" + full_hash.slice(0, prefix_len)
    existing = used_symbols[candidate]
    if existing == nil
      used_symbols[candidate] = full_hash
      return candidate
    if existing == full_hash
      return candidate
    prefix_len += 2

  suffix = 1
  while true
    candidate = "__wy_" + full_hash + "_" + suffix.to_s()
    if used_symbols[candidate] == nil
      used_symbols[candidate] = full_hash
      return candidate
    suffix += 1

-> build_hash_symbols(hash_groups, min_prefix)
  used = {}
  hash_symbols = {}
  hkeys = hash_groups.keys().sort()
  hi = 0
  while hi < hkeys.size()
    h = hkeys[hi]
    hash_symbols[h] = compact_symbol_for_hash(h, used, min_prefix)
    hi += 1
  hash_symbols

-> symbol_prefix_hex
  raw = env("TUNGSTEN_SYMBOL_PREFIX_HEX")
  if raw != nil
    n = raw.strip().to_i()
    if n > 0 && n <= 16
      return n
  8

-> build_function_info_by_name(functions)
  info = {}
  fi = 0
  while fi < functions.size()
    func = functions[fi]
    original = func[:original_name]
    if original == nil
      original = func[:name]
    kind = func[:source_kind]
    if kind != nil
      kind = kind.to_s()
    info[original] = {
      symbol: original,
      class: func[:source_class],
      method: func[:source_method],
      kind: kind,
      file: func[:source_path],
      line: func[:source_line],
      arity: func[:params].size()
    }
    fi += 1
  info

-> append_original_json(out, info)
  out << "{\"symbol\":"
  out << json_quote(info[:symbol])
  out << ",\"class\":"
  out << json_quote(info[:class])
  out << ",\"method\":"
  out << json_quote(info[:method])
  out << ",\"kind\":"
  out << json_quote(info[:kind])
  out << ",\"file\":"
  out << json_quote(info[:file])
  out << ",\"line\":"
  if info[:line] == nil
    out << "null"
  else
    out << info[:line].to_s()
  out << ",\"arity\":"
  out << info[:arity].to_s()
  out << "}"

-> build_symbol_sidemap_text(mod, hash_groups, hash_symbols, fn_info_by_name, prefix_hex)
  out = StringBuffer(hash_groups.keys().size() * 160 + 256)
  out << "{\n"
  out << "  \"version\": 1,\n"
  out << "  \"hash_algorithm\": \"wyhash64\",\n"
  out << "  \"prefix_hex\": "
  out << prefix_hex.to_s()
  out << ",\n"
  out << "  \"source\": "
  out << json_quote(mod[:source_path])
  out << ",\n"
  out << "  \"hashes\": {\n"

  hkeys = hash_groups.keys().sort()
  hi = 0
  while hi < hkeys.size()
    h = hkeys[hi]
    out << "    "
    out << json_quote(h)
    out << ": {\"symbol\": "
    out << json_quote(hash_symbols[h])
    out << ", \"originals\": \["

    group = hash_groups[h].sort()
    gi = 0
    emitted = 0
    while gi < group.size()
      info = fn_info_by_name[group[gi]]
      if info != nil
        if emitted > 0
          out << ", "
        append_original_json(out, info)
        emitted += 1
      gi += 1

    out << "]}"
    if hi + 1 < hkeys.size()
      out << ","
    out << "\n"
    hi += 1

  out << "  }\n"
  out << "}\n"
  out.to_s()

-> apply_compact_symbols(mod, fn_hashes, hash_groups, fn_info_by_name)
  prefix_hex = symbol_prefix_hex()
  hash_symbols = build_hash_symbols(hash_groups, prefix_hex)
  rename_map = {}
  functions = mod[:functions]
  fi = 0
  while fi < functions.size()
    func = functions[fi]
    h = fn_hashes[func[:name]]
    if h != nil
      compact = hash_symbols[h]
      if compact != nil && compact != func[:name]
        if func[:original_name] == nil
          func[:original_name] = func[:name]
        rename_map[func[:name]] = compact
    fi += 1

  if rename_map.keys().size() > 0
    rewrite_references(mod, rename_map)
    rewrite_known_name_maps(mod, rename_map)
    rewrite_memo_globals(mod, rename_map)

    fi = 0
    while fi < functions.size()
      replacement = rename_map[functions[fi][:name]]
      if replacement != nil
        functions[fi][:name] = replacement
        functions[fi][:llvm_internal] = true
      fi += 1

  mod[:fn_symbol_prefix_hex] = prefix_hex
  mod[:fn_symbol_count] = rename_map.keys().size()
  mod[:fn_hash_symbols] = hash_symbols
  mod[:symbol_sidemap_text] = build_symbol_sidemap_text(mod, hash_groups, hash_symbols, fn_info_by_name, prefix_hex)

# Print a readable summary of a function's WIRE instructions.
-> dump_wire_func(func, mod)
  << "  fn " + func[:name] + "(" + func[:params].size().to_s() + " params)"
  bi = 0
  while bi < func[:blocks].size()
    << "    " + func[:blocks][bi][:label] + ":"
    instrs = func[:blocks][bi][:instructions]
    ii = 0
    while ii < instrs.size()
      inst = instrs[ii]
      op = inst[:op]
      if op != :scope_push && op != :scope_pop
        line = "      " + op.to_s()
        if inst[:temp] != nil
          line = line + " " + inst[:temp]
        if op in (:call_direct_i64 :call_direct_void)
          line = line + " @" + inst[:name]
          if inst[:args] != nil
            line = line + "(" + inst[:args].size().to_s() + " args)"
        elsif op == :call_method_i64
          line = line + " method"
        elsif op == :ret_i64
          line = line + " " + inst[:value].to_s()
        elsif op == :br
          line = line + " -> " + inst[:label]
        elsif op == :cond_br
          line = line + " -> " + inst[:then_label] + " / " + inst[:else_label]
        elsif op == :string_i64
          str_idx = mod[:string_index]
          if str_idx != nil
            text = str_idx[inst[:string_id]]
            if text != nil
              if text.size() > 30
                line = line + " \"" + text.slice(0, 30) + "...\""
              else
                line = line + " \"" + text + "\""
        << line
      ii += 1
    bi += 1

# Main pass: hash all functions, dedup, rewrite references.
-> content_hash_pass(mod, verbose = false)
  functions = mod[:functions]
  fn_hashes = {}
  op_codes = {next_code: 0}

  # Pre-build string ID → text index for fast lookup
  strings = mod[:strings]
  str_idx = {}
  si = 0
  while si < strings.size()
    str_idx[strings[si][:id]] = strings[si][:text]
    si += 1
  mod[:string_index] = str_idx

  # Build call graph for topo sort
  fn_set = {}
  fi = 0
  while fi < functions.size()
    fn_set[functions[fi][:name]] = true
    fi += 1

  calls_to = {}
  fi = 0
  while fi < functions.size()
    func = functions[fi]
    edges = []
    bi = 0
    while bi < func[:blocks].size()
      instrs = func[:blocks][bi][:instructions]
      ii = 0
      while ii < instrs.size()
        inst = instrs[ii]
        callee = nil
        if inst[:op] in (:call_direct_i64 :call_direct_void)
          callee = inst[:name]
        elsif inst[:op] == :closure_new
          callee = inst[:fn_name]
        if callee != nil && fn_set[callee] == true && callee != func[:name]
          edges.push(callee)
        ii += 1
      bi += 1
    calls_to[func[:name]] = edges
    fi += 1

  # Topo sort (leaf functions first)
  processed = {}
  order = []
  remaining = functions.size()
  while remaining > 0
    progress = false
    fi = 0
    while fi < functions.size()
      fname = functions[fi][:name]
      if processed[fname] != true
        edges = calls_to[fname]
        all_done = true
        if edges != nil
          ei = 0
          while ei < edges.size()
            if processed[edges[ei]] != true
              all_done = false
            ei += 1
        if all_done
          order.push(fi)
          processed[fname] = true
          remaining = remaining - 1
          progress = true
      fi += 1
    if !progress
      # Cycle: process remaining with __CYCLE__ sentinel
      fi = 0
      while fi < functions.size()
        if processed[functions[fi][:name]] != true
          order.push(fi)
          processed[functions[fi][:name]] = true
          remaining = remaining - 1
        fi += 1

  # Hash each function in topo order
  oi = 0
  while oi < order.size()
    func = functions[order[oi]]
    # Skip main and empty functions
    if func[:is_toplevel] != true && func[:blocks].size() > 0
      h = canonical_hash(func, mod, fn_hashes, op_codes)
      fn_hashes[func[:name]] = h
    oi += 1

  # Group by hash
  hash_groups = {}  # hash → [fn_name, ...]
  hkeys = fn_hashes.keys()
  hi = 0
  while hi < hkeys.size()
    fname = hkeys[hi]
    h = fn_hashes[fname]
    if hash_groups[h] == nil
      hash_groups[h] = []
    hash_groups[h].push(fname)
    hi += 1
  fn_info_by_name = build_function_info_by_name(functions)

  # SHOW_ME_THE_DUPES: print dedup pairs with their WIRE instructions
  show_dupes = env("SHOW_ME_THE_DUPES") != nil

  # Build rename map for duplicates
  rename_map = {}
  dedup_count = 0
  gkeys = hash_groups.keys()
  gi = 0
  while gi < gkeys.size()
    group = hash_groups[gkeys[gi]]
    if group.size() > 1
      # Pick canonical name (first alphabetically)
      canonical = group[0]
      ci = 1
      while ci < group.size()
        if group[ci] < canonical
          canonical = group[ci]
        ci += 1
      # Show dedup pairs if requested
      if show_dupes
        << ""
        << "=== DEDUP GROUP (hash " + gkeys[gi].to_s() + ", " + group.size().to_s() + " functions) ==="
        ci = 0
        while ci < group.size()
          # Find the function object
          ffi = 0
          while ffi < functions.size()
            if functions[ffi][:name] == group[ci]
              dump_wire_func(functions[ffi], mod)
              break
            ffi += 1
          ci += 1
      # Map all others to canonical
      ci = 0
      while ci < group.size()
        if group[ci] != canonical
          rename_map[group[ci]] = canonical
          dedup_count = dedup_count + 1
        ci += 1
    gi += 1
  if dedup_count > 0
    # Rewrite all references
    rewrite_references(mod, rename_map)

    # Remove duplicate functions
    new_functions = []
    fi = 0
    while fi < functions.size()
      if rename_map[functions[fi][:name]] == nil
        new_functions.push(functions[fi])
      fi += 1
    mod[:functions] = new_functions

    # Update known_calls, known_pure_calls, fn_memo_tables
    kcalls = mod[:known_calls]
    if kcalls != nil
      kk = kcalls.keys()
      ki = 0
      while ki < kk.size()
        replacement = rename_map[kcalls[kk[ki]]]
        if replacement != nil
          kcalls[kk[ki]] = replacement
        ki += 1

    kpure = mod[:known_pure_calls]
    if kpure != nil
      kk = kpure.keys()
      ki = 0
      while ki < kk.size()
        replacement = rename_map[kpure[kk[ki]]]
        if replacement != nil
          kpure[kk[ki]] = replacement
        ki += 1

    # Merge memo tables for deduped functions, and rewrite the
    # store_memo_ptr `:global` references that used the old name.
    # Without the instruction rewrite, the emitter declares the
    # canonical-fn memo global but main still tries to store into
    # `@__w_<old_name>.memo` — undefined symbol at link time.
    memo = mod[:fn_memo_tables]
    global_rename = {}
    if memo != nil
      mk = memo.keys()
      mi = 0
      while mi < mk.size()
        old_global = memo[mk[mi]]
        if old_global != nil
          dot = old_global.index(".memo")
          if dot != nil
            old_fn = old_global.slice(0, dot)
            replacement = rename_map[old_fn]
            if replacement != nil
              new_global = replacement + ".memo"
              global_rename[old_global] = new_global
              memo[mk[mi]] = new_global
        mi += 1

    if global_rename.keys().size() > 0
      fi = 0
      while fi < mod[:functions].size()
        func = mod[:functions][fi]
        bi = 0
        while bi < func[:blocks].size()
          instrs = func[:blocks][bi][:instructions]
          ii = 0
          while ii < instrs.size()
            inst = instrs[ii]
            if inst[:global] != nil
              replacement = global_rename[inst[:global]]
              if replacement != nil
                inst[:global] = replacement
            ii += 1
          bi += 1
        fi += 1

  apply_compact_symbols(mod, fn_hashes, hash_groups, fn_info_by_name)

  mod[:fn_hashes] = fn_hashes
  mod[:fn_dedup_count] = dedup_count
