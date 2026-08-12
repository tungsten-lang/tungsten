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

-> exact_string_key?(left, right)
  left != nil && right != nil && left.size() == right.size() && left == right

-> fn_hash_put(fn_hashes, source, hash)
  fn_hashes[source] = {source: source, hash: hash}

-> fn_hash_get(fn_hashes, source)
  entry = fn_hashes[source]
  if entry == nil || !exact_string_key?(entry[:source], source)
    return nil
  entry[:hash]

-> fn_content_put(fn_contents, source, content)
  fn_contents[source] = {source: source, content: content}

-> fn_content_get(fn_contents, source)
  entry = fn_contents[source]
  if entry == nil || !exact_string_key?(entry[:source], source)
    return nil
  entry[:content]


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

# Canonicalize instruction fields that change emitted code but are not part of
# the common value/lhs/rhs/ptr shape below. Keeping this list explicit makes a
# missing WIRE operand fail closed (fewer deduplications) instead of silently
# merging functions whose LLVM differs — boxed/headerless typed-array paths
# were especially vulnerable to that class of bug.
-> encode_codegen_meta_value(buf, value, temp_map)
  if value == nil
    buf << "_"
    return nil
  value_type = type(value)
  if value_type == "Array" || value_type == "SmallArray"
    buf << "\["
    i = 0
    while i < value.size()
      encode_codegen_meta_value(buf, value[i], temp_map)
      buf << ","
      i += 1
    buf << "\]"
    return nil
  if value_type == "Hash"
    buf << "{"
    keys = value.keys().sort()
    i = 0
    while i < keys.size()
      encode_codegen_meta_value(buf, keys[i], temp_map)
      buf << ":"
      encode_codegen_meta_value(buf, value[keys[i]], temp_map)
      buf << ","
      i += 1
    buf << "}"
    return nil
  scalar = value_type == "String" || value_type == "Symbol" || value_type == "Integer" || value_type == "Int" || value_type == "BigInt" || value_type == "Float" || value_type == "Decimal" || value_type == "Rational" || value_type == "Boolean" || value_type == "Bool"
  if !scalar
    # Source-only objects do not participate in LLVM emission. Encode one
    # opaque marker: calling #to_s would serialize host-specific node or block
    # internals, and some stage-0 values intentionally have no conversion.
    buf << "x"
    return nil
  text = value.to_s()
  if text.size() > 0 && text.slice(0, 1) == "%"
    buf << "t"
    buf << norm_temp(text, temp_map).to_s()
  else
    buf << text.size().to_s()
    buf << ":"
    buf << text

-> encode_codegen_meta_field(inst, field, buf, temp_map)
  value = inst[field]
  if value == nil
    return nil
  # switch_i64 cases retain their source AST arm for the later block-lowering
  # walk, but LLVM emission consumes only these three fields. Packed-node and
  # hash AST hosts deliberately represent :arm differently, so never let that
  # source-only payload enter a content address.
  if field == :cases
    buf << "kcases=("
    i = 0
    while i < value.size()
      c = value[i]
      encode_codegen_meta_value(buf, c[:value], temp_map)
      buf << "/"
      encode_codegen_meta_value(buf, c[:string_id], temp_map)
      buf << "/"
      encode_codegen_meta_value(buf, c[:label], temp_map)
      buf << ";"
      i += 1
    buf << ")"
    return nil
  # The node_field_* WIRE ops store an SSA temp in :node. Other lowering
  # records may retain an AST node under the same key; that object is not read
  # by the LLVM emitter and differs by bootstrap host representation.
  if field == :node && type(value) != "String"
    return nil
  buf << "k"
  buf << field.to_s()
  buf << "="
  encode_codegen_meta_value(buf, value, temp_map)
  buf << ";"

content_hash_codegen_fields = [
  :a_label, :a_value, :arg, :arg_types, :as_i1,
  :b_label, :b_value, :base, :block_arity, :boxed, :buf,
  :call_conv, :cap, :captures_ptr, :cases, :class_temp, :codepoint,
  :col, :compound_op, :const_name, :count, :default_label, :dest,
  :dispatch_key, :elem, :entry_label, :fields, :file_byte_len,
  :file_str_id, :fp_flags, :headerless, :is_symbol, :ivar_byte_len,
  :ivar_str_id, :kind, :kind_id, :lhs_boxed, :line, :method_byte_len,
  :method_str_id, :min_arity, :n, :name_byte_len, :name_str_id,
  :node, :novec, :range_high, :range_low, :rhs_boxed, :rt_fallback,
  :scalar_source_argc1, :shift, :slot, :slot_id, :slot_type, :splat_index,
  :super_reg, :table, :total_bytes, :trap, :type, :unroll_count, :val
]
-> encode_codegen_metadata(inst, buf, temp_map)
  i = 0
  while i < content_hash_codegen_fields.size()
    encode_codegen_meta_field(inst, content_hash_codegen_fields[i], buf, temp_map)
    i += 1

# Encode one instruction into the canonical string buffer.
-> encode_inst(inst, buf, temp_map, label_map, fn_hashes, mod, self_name, op_codes)
  op = inst[:op]
  buf << "o"
  buf << canonical_op_code(op, op_codes).to_s()

  # Register temp output
  if inst[:temp] != nil
    norm_temp(inst[:temp], temp_map)

  encode_codegen_metadata(inst, buf, temp_map)

  if op in (:call_direct_i64 :call_direct_void :call_direct_ptr)
    callee = inst[:name]

    if callee == self_name
      buf << "@R"
    elsif fn_hash_get(fn_hashes, callee) != nil
      buf << "@"
      buf << fn_hash_get(fn_hashes, callee)
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

    # Devirtualized target: two otherwise-identical bodies whose call sites
    # devirtualize to DIFFERENT methods must not content-collapse.
    if inst[:devirt_fn] != nil
      buf << "dv:"
      buf << inst[:devirt_fn]
      buf << ":"
      buf << inst[:devirt_class]

    buf << ";"
    return nil

  if op == :closure_new
    callee = inst[:fn_name]
    if fn_hash_get(fn_hashes, callee) != nil
      buf << "@"
      buf << fn_hash_get(fn_hashes, callee)
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
  # Native view-field width and signedness determine the emitted load/store
  # instruction. `u8 field@0` and `u32 field@0` have the same op, pointer and
  # offset but are not interchangeable; omitting these fields previously
  # merged Packet#tag into Hash#size and made the former read four bytes.
  if inst[:size] != nil
    buf << "Z"
    buf << inst[:size].to_s()
  if inst[:field_type] != nil
    buf << "F"
    buf << inst[:field_type].to_s()
  if inst[:signed] != nil
    if inst[:signed] == true
      buf << "Gs"
    else
      buf << "Gu"
  # Literal-constant payloads (const_decimal / const_currency /
  # const_quantity / const_duration_* / const_date / const_ipv4 /
  # const_rational / const_color): without these fields two functions
  # differing only in such a constant hash identically and get wrongly
  # merged — e.g. every class method returning a quantity literal
  # collapsed to the first one (`100 m/s` == `5 Pa` == `3 kg`).
  if inst[:sig] != nil
    buf << "q"
    buf << inst[:sig].to_s()
  if inst[:scale] != nil
    buf << "e"
    buf << inst[:scale].to_s()
  if inst[:unit_id] != nil
    buf << "u"
    buf << inst[:unit_id].to_s()
  if inst[:symbol_id] != nil
    buf << "cy"
    buf << inst[:symbol_id].to_s()
  if inst[:ns] != nil
    buf << "ns"
    buf << inst[:ns].to_s()
  if inst[:months] != nil
    buf << "mo"
    buf << inst[:months].to_s()
  if inst[:ms] != nil
    buf << "ms"
    buf << inst[:ms].to_s()
  if inst[:year] != nil
    buf << "dt"
    buf << inst[:year].to_s()
    buf << "-"
    buf << inst[:month].to_s()
    buf << "-"
    buf << inst[:day].to_s()
    buf << "T"
    buf << inst[:hour].to_s()
    buf << ":"
    buf << inst[:min].to_s()
    buf << ":"
    buf << inst[:sec].to_s()
    buf << "z"
    buf << inst[:tz].to_s()
  if inst[:cidr] != nil
    buf << "ip"
    buf << inst[:a].to_s()
    buf << "."
    buf << inst[:b].to_s()
    buf << "."
    buf << inst[:c].to_s()
    buf << "."
    buf << inst[:d].to_s()
    buf << "/"
    buf << inst[:cidr].to_s()
  if inst[:num] != nil
    buf << "rn"
    buf << inst[:num].to_s()
  if inst[:den] != nil
    buf << "rd"
    buf << inst[:den].to_s()
  if inst[:r] != nil
    buf << "col"
    buf << inst[:r].to_s()
    buf << ","
    buf << inst[:g].to_s()
    buf << ","
    buf << inst[:b].to_s()
    buf << ","
    buf << inst[:a].to_s()
  if inst[:string_id] != nil
    buf << "sid"
    buf << inst[:string_id].to_s()
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

# Canonical content for an entire function. Keeping the content alongside its
# fast hash lets the dedup pass prove equality instead of treating a 64-bit
# digest as proof. Hash collisions must only lengthen a symbol, never merge two
# functions.
-> canonical_content(func, mod, fn_hashes, op_codes)
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

  # Embedded ll/asm bodies carry no WIRE instructions — the verbatim text
  # (plus the parameter names the IR/asm references) IS the content.  Without
  # this, every embedded fn of the same arity hashes identically and the
  # compact-symbol pass merges them.
  if func[:embedded_ll] != nil || func[:embedded_asm] != nil
    pi2 = 0
    while pi2 < func[:params].size()
      buf << func[:params][pi2]
      buf << ","
      pi2 += 1
    buf << "|"
    if func[:embedded_ll] != nil
      buf << "LL|"
      buf << func[:embedded_ll]
    else
      buf << "ASM|"
      buf << func[:embedded_asm]
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
  encoded

-> canonical_hash(func, mod, fn_hashes, op_codes)
  wyhash64_hex_string(canonical_content(func, mod, fn_hashes, op_codes))

# Rename maps carry their source key inside the value. This makes every lookup
# self-validating: a host Hash collision can at worst become a miss, never
# rewrite a different function whose name happens to share a bucket/prefix.
-> rename_map_put(rename_map, source, replacement)
  rename_map[source] = {source: source, replacement: replacement}

-> rename_map_entry(rename_map, source)
  entry = rename_map[source]
  if entry == nil || !exact_string_key?(entry[:source], source)
    return nil
  entry

-> rename_map_get(rename_map, source)
  entry = rename_map_entry(rename_map, source)
  if entry == nil
    return nil
  entry[:replacement]

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
          replacement = rename_map_get(rename_map, inst[:name])
          if replacement != nil
            inst[:name] = replacement
        if op == :closure_new
          replacement = rename_map_get(rename_map, inst[:fn_name])
          if replacement != nil
            inst[:fn_name] = replacement
        # Devirtualized direct-call target on an IC dispatch site — the
        # method function gets compact-symbol renamed like any function.
        if op == :call_method_i64 && inst[:devirt_fn] != nil
          replacement = rename_map_get(rename_map, inst[:devirt_fn])
          if replacement != nil
            inst[:devirt_fn] = replacement
        # Fused-loop worker address (ptrtoint ptr @name) — the referenced
        # worker gets compact-symbol renamed like any function.
        if op == :fn_addr_i64
          replacement = rename_map_get(rename_map, inst[:name])
          if replacement != nil
            inst[:name] = replacement
        if op in (:memo_call0_i64 :memo_call1_i64 :memo_call2_i64)
          replacement = rename_map_get(rename_map, inst[:fn_name])
          if replacement != nil
            inst[:fn_name] = replacement
        if op in (:class_add_method :class_add_static_method)
          replacement = rename_map_get(rename_map, inst[:fn_name])
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
          replacement = rename_map_get(rename_map, old_fn)
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
      replacement = rename_map_get(rename_map, kcalls[kk[ki]])
      if replacement != nil
        kcalls[kk[ki]] = replacement
      ki += 1

  kpure = mod[:known_pure_calls]
  if kpure != nil
    kk = kpure.keys()
    ki = 0
    while ki < kk.size()
      replacement = rename_map_get(rename_map, kpure[kk[ki]])
      if replacement != nil
        kpure[kk[ki]] = replacement
      ki += 1

  statics = mod[:known_static_methods]
  if statics != nil
    sk = statics.keys()
    si = 0
    while si < sk.size()
      info = statics[sk[si]]
      replacement = rename_map_get(rename_map, info[:fn_name])
      if replacement != nil
        info[:fn_name] = replacement
      replacement = rename_map_get(rename_map, info[:method_fn_name])
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
  hkeys = hash_groups.keys()
  hi = 0
  while hi < hkeys.size()
    h = hkeys[hi]
    hash_symbols[h] = {hash: h, symbol: compact_symbol_for_hash(h, used, min_prefix)}
    hi += 1
  hash_symbols

-> hash_symbol_get(hash_symbols, hash)
  entry = hash_symbols[hash]
  if entry == nil || !exact_string_key?(entry[:hash], hash)
    return nil
  entry[:symbol]

-> hash_group_add(hash_groups, hash, function_name)
  entry = hash_groups[hash]
  if entry == nil || !exact_string_key?(entry[:hash], hash)
    entry = {hash: hash, functions: []}
    hash_groups[hash] = entry
  entry[:functions].push(function_name)

-> hash_group_get(hash_groups, hash)
  entry = hash_groups[hash]
  if entry == nil || !exact_string_key?(entry[:hash], hash)
    return []
  entry[:functions]

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

-> function_physical_abi(func)
  out = StringBuffer(32)
  out << func[:return_type]
  out << "("
  out << func[:params].size().to_s()
  extra = func[:extra_params]
  if extra != nil
    i = 0
    while i < extra.size()
      out << ","
      out << extra[i][:type]
      i += 1
  out << ")"
  out.to_s()

-> function_by_exact_name(functions, name)
  i = 0
  while i < functions.size()
    if exact_string_key?(functions[i][:name], name)
      return functions[i]
    i += 1
  nil

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

  hkeys = hash_groups.keys()
  hi = 0
  while hi < hkeys.size()
    h = hkeys[hi]
    out << "    "
    out << json_quote(h)
    out << ": {\"symbol\": "
    out << json_quote(hash_symbol_get(hash_symbols, h))
    out << ", \"originals\": \["

    group = hash_group_get(hash_groups, h).sort()
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
  compact_owners = {}
  functions = mod[:functions]
  fi = 0
  while fi < functions.size()
    func = functions[fi]
    h = fn_hash_get(fn_hashes, func[:name])
    if h != nil
      compact = hash_symbol_get(hash_symbols, h)
      if compact != nil && compact != func[:name]
        owner = compact_owners[compact]
        abi = function_physical_abi(func)
        if owner != nil && owner[:symbol] == compact && owner[:abi] != abi
          raise "content symbol ABI collision for " + compact + ": " + owner[:source] + "=" + owner[:hash] + " " + owner[:abi] + " vs " + func[:name] + "=" + h + " " + abi
        compact_owners[compact] = {symbol: compact, source: func[:name], hash: h, abi: abi}
        if func[:original_name] == nil
          func[:original_name] = func[:name]
        rename_map_put(rename_map, func[:name], compact)
    fi += 1

  if rename_map.keys().size() > 0
    rewrite_references(mod, rename_map)
    rewrite_known_name_maps(mod, rename_map)
    rewrite_memo_globals(mod, rename_map)

    fi = 0
    while fi < functions.size()
      replacement = rename_map_get(rename_map, functions[fi][:name])
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
  fn_contents = {}
  hash_contents = {}
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
      content = canonical_content(func, mod, fn_hashes, op_codes)
      h = wyhash64_hex_string(content)
      salt = 0
      resolved = false
      while !resolved
        prior = hash_contents[h]
        if prior == nil
          hash_contents[h] = {hash: h, content: content}
          resolved = true
        elsif prior[:hash] == h && prior[:content] == content
          resolved = true
        else
          # A real hash collision (or a defensive mismatch returned by a host
          # Hash implementation) gets a deterministic rehash. The full
          # canonical content is still compared below before deduplication.
          salt += 1
          h = wyhash64_hex_string("collision:" + salt.to_s() + ":" + content)
      fn_hash_put(fn_hashes, func[:name], h)
      fn_content_put(fn_contents, func[:name], content)
    oi += 1

  # Group by hash
  hash_groups = {}  # hash → [fn_name, ...]
  hkeys = fn_hashes.keys()
  hi = 0
  while hi < hkeys.size()
    fname = hkeys[hi]
    h = fn_hash_get(fn_hashes, fname)
    hash_group_add(hash_groups, h, fname)
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
    group = hash_group_get(hash_groups, gkeys[gi])
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
        candidate_content = fn_content_get(fn_contents, group[ci])
        canonical_content_value = fn_content_get(fn_contents, canonical)
        candidate_func = function_by_exact_name(functions, group[ci])
        canonical_func = function_by_exact_name(functions, canonical)
        same_abi = candidate_func != nil && canonical_func != nil && function_physical_abi(candidate_func) == function_physical_abi(canonical_func)
        if group[ci] != canonical && same_abi && candidate_content != nil && canonical_content_value != nil && candidate_content == canonical_content_value
          rename_map_put(rename_map, group[ci], canonical)
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
      if rename_map_get(rename_map, functions[fi][:name]) == nil
        new_functions.push(functions[fi])
      fi += 1
    mod[:functions] = new_functions

    # Update known_calls, known_pure_calls, fn_memo_tables
    kcalls = mod[:known_calls]
    if kcalls != nil
      kk = kcalls.keys()
      ki = 0
      while ki < kk.size()
        replacement = rename_map_get(rename_map, kcalls[kk[ki]])
        if replacement != nil
          kcalls[kk[ki]] = replacement
        ki += 1

    kpure = mod[:known_pure_calls]
    if kpure != nil
      kk = kpure.keys()
      ki = 0
      while ki < kk.size()
        replacement = rename_map_get(rename_map, kpure[kk[ki]])
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
            replacement = rename_map_get(rename_map, old_fn)
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
