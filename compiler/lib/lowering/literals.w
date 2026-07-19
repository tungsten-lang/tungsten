# Lowering / literals — value lowering for every literal node type
# (basic literals, arrays/hashes/symbols, ranges, regexes, and the deep
# domain types: floats, decimals, dates, times, durations, currencies,
# quantities, IPs, CIDRs, characters, codepoints, colors, and so on).
#
# Depends on pass_registry.w, types.w, analysis.w, monomorphize.w.
# This file deliberately has no `use` directives — see pass_registry.w.


# -- Literals --

-> lower_int(ctx, node)
  val = node.value
  # Literals beyond the 48-bit NaN-box payload must NOT silently truncate
  # when boxed. Flow those as :raw_i64 (boxed via the checked `w_int`,
  # which promotes to BigInt above i48) instead of :raw_int (nanbox, which
  # masks to 48 bits). Small literals stay :raw_int to keep the inline
  # compile-time-constant fast path (no boxing IR, used directly as
  # `add i64 %acc, 42` immediates). i64 machine arithmetic still wraps
  # (C semantics) — only the *box* promotes. Literals beyond i64 are
  # handled separately (lower_int_bigint_literal), since `val` has already
  # wrapped at parse time and can't represent them.
  if int_literal_exceeds_i64?(node)
    return lower_int_bigint_literal(ctx, node)
  # Non-decimal literals (hex/bin/oct) whose true magnitude exceeds signed
  # i64: parse_*_int kept `val` as a correct BigInt, but the :raw_i64 path
  # below would truncate it to an i64 immediate (0xFFFFFFFFFFFFFFFF → -1).
  # Emit it from val's exact decimal text instead. Over-i64 *decimal* literals
  # are handled by int_literal_exceeds_i64? above (their `val` wrapped).
  if val > 9223372036854775807
    return lower_int_bigint_from_text(ctx, "" + val.to_s())
  if val > 140737488355327 || val < -140737488355328
    # Beyond i48: flow as :raw_i64 (checked box → BigInt). Prefer the
    # faithful decimal text over val.to_s(): for the i64-minimum literal
    # (`-9223372036854775808`) the positive magnitude 2^63 wraps at parse
    # time, so the recomputed value is unreliable; the raw text is exact.
    raw = node.raw
    if decimal_int_literal?(raw)
      return typed_value(:raw_i64, "" + raw.replace("_", ""))
    return typed_value(:raw_i64, val.to_s())
  # Raw int: no emit, just a typed_value carrying the literal text.
  # Boxing boundaries choose the correct representation later; raw
  # machine slots must preserve all 64 bits, including tag constants.
  typed_value(:raw_int, val.to_s())

# True when a decimal integer literal's magnitude exceeds the signed i64
# range — meaning `node.value` has already wrapped at parse time and the
# literal must be built as a BigInt from its original text. Hex/bin/oct
# literals keep their current behavior (range-checked separately later).
-> int_literal_exceeds_i64?(node)
  raw = node.raw
  if !decimal_int_literal?(raw)
    return false
  decimal_text_exceeds_i64?(raw)

# True when `raw` is a plain decimal integer literal (no 0x/0b/0o base
# prefix) — i.e. its text is a base-10 number usable directly as a decimal
# i64 immediate or fed to w_bigint_from_dec_str.
-> decimal_int_literal?(raw)
  if raw == nil
    return false
  if raw.starts_with?("0x") || raw.starts_with?("0X")
    return false
  if raw.starts_with?("0b") || raw.starts_with?("0B")
    return false
  if raw.starts_with?("0o") || raw.starts_with?("0O")
    return false
  true

-> decimal_text_exceeds_i64?(text)
  s = "" + text.replace("_", "")
  neg = false
  if s.starts_with?("-")
    neg = true
    s = s.slice(1, s.size() - 1)
  elsif s.starts_with?("+")
    s = s.slice(1, s.size() - 1)
  # Strip leading zeros (keep at least one digit).
  i = 0
  while i < s.size() - 1 && s.slice(i, 1) == "0"
    i += 1
  s = s.slice(i, s.size() - i)
  n = s.size()
  if n > 19
    return true
  if n < 19
    return false
  # Exactly 19 digits: lexical compare against the i64 bound magnitude
  # (same length, so byte order matches numeric order).
  limit = "9223372036854775807"
  if neg
    limit = "9223372036854775808"
  s > limit

# Build a BigInt literal from the original decimal text. `node.value` can't
# represent it (it wrapped at i64), so parse the cleaned text at runtime via
# w_bigint_from_dec_str, which accumulates through the promoting w_mul/w_add.
-> lower_int_bigint_literal(ctx, node)
  lower_int_bigint_from_text(ctx, "" + node.raw.replace("_", ""))

# Build a BigInt at runtime from a decimal-digit string. Shared by the
# over-i64 decimal path (raw text) and the over-i64 hex/bin/oct path (the
# node's already-correct value rendered back to decimal via val.to_s()).
-> lower_int_bigint_from_text(ctx, text)
  wfn = ctx[:func]
  str_tv = lower_string(ctx, Tungsten:AST:String.new(text))
  str_reg = ensure_i64_value(wfn, str_tv)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_bigint_from_dec_str", args: [str_reg]})
  typed_value(:i64, temp)

-> lower_wvalue(ctx, node)
  typed_value(:i64, wvalue_literal_text(node.value))

-> lower_bool(node)
  if node.value == true
    return typed_value(:i64, w_true.to_s())
  typed_value(:i64, w_false.to_s())

# `__DIR__` is a deployment anchor, unlike the diagnostic spelling preserved
# by `__FILE__`.  Resolve a relative entry/import path while the compiler still
# has the invocation cwd; a native executable launched elsewhere cannot recover
# that cwd later.  `pwd -P` also gives the real directory semantics expected of
# the magic constant when the source arrived through a symlinked checkout.
-> magic_source_dir(source_path)
  parts = source_path.split("/")
  parts.pop()
  dir = parts.join("/")
  if dir == ""
    dir = "."
  quoted = "'" + dir.replace("'", "'\"'\"'") + "'"
  absolute = capture("cd " + quoted + " 2>/dev/null && pwd -P").strip()
  if absolute != ""
    return absolute
  dir

-> lower_magic_constant(ctx, node)
  # Locations use FileOffset mode, so the payload carries a file id and source
  # offset rather than an inline line number. Resolve it through the registered
  # per-file lookup table; treating the offset bits as the legacy line field
  # makes __LINE__ silently evaluate to zero near the start of a file.
  loc = ast_get(node, :loc)
  line = 0
  if loc != nil
    line = location_line(loc)
  case node.name
  when "FILE"
    lower_string(ctx, Tungsten:AST:String.new(ctx[:source_path]))
  when "DIR"
    lower_string(ctx, Tungsten:AST:String.new(magic_source_dir(ctx[:source_path])))
  when "LINE"
    lower_int(ctx, Tungsten:AST:Int.new(line))
  else
    raise compile_error_for_node(:E_LOWER_UNKNOWN_MAGIC, "Unknown magic constant: " + node.name, ctx[:source_path], node)

-> lower_string(ctx, node)
  s = node.value
  byte_len = utf8_byte_length(s)
  # SSO-5: strings ≤5 bytes are encoded directly as an i64 constant — no global, no w_string call
  if byte_len <= 5
    v = w_tag_stringsym + byte_len * 2
    bytes = s.bytes()
    i = 0
    while i < byte_len
      v = v + bytes[i] * (1 << (4 + 8 * i))
      i += 1
    return typed_value(:i64, wvalue_literal_text(v))
  str_id = module_string_constant(ctx[:mod], s)
  temp_ptr = next_temp(ctx[:func])
  temp = next_temp(ctx[:func])
  emit_instruction(ctx[:func], {op: :string_i64, temp: temp, temp_ptr: temp_ptr, string_id: str_id, byte_len: byte_len + 1})
  typed_value(:i64, temp)

-> lower_string_interp(ctx, node)
  wfn = ctx[:func]
  parts = node.parts
  result = nil
  i = 0
  while i < parts.size()
    part = parts[i]
    if part[0] == :str
      str_tv = lower_string(ctx, Tungsten:AST:String.new(part[1]))
      part_reg = ensure_i64_value(wfn, str_tv)
    else
      expr_tv = lower_expression(ctx, part[1])
      expr_reg = ensure_i64_value(wfn, expr_tv)
      part_reg = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: part_reg, name: "w_to_s", args: [expr_reg]})
    if result == nil
      result = part_reg
    else
      concat = next_temp(wfn)
      emit_instruction(wfn, {op: :call_direct_i64, temp: concat, name: "w_str_concat", args: [result, part_reg]})
      result = concat
    i += 1
  if result == nil
    return lower_string(ctx, Tungsten:AST:String.new(""))
  typed_value(:i64, result)

# -- Arrays --

# Phase 5g: try to fold a literal `[c1, c2, ...]` whose elements are all
# integer constants ≥0, ≤255, into a compile-time SmallArray. Returns
# {ebits, size, bytes} on success or nil to bail to dynamic construction.
# Bounds: 1..255 elements, u8 only for first cut (covers lookup tables,
# byte sequences — the most common use case). Wider ebits + signedness
# are deferred until there's demand.
-> try_const_small_array(elements)
  if elements == nil
    return nil
  n = elements.size()
  if n == 0 || n > 255
    return nil
  bytes = []
  i = 0
  while i < n
    e = elements[i]
    if e == nil || ast_kind(e) != :int
      return nil
    v = e.value
    if v == nil || v < 0 || v > 255
      return nil
    bytes.push(v)
    i += 1
  {ebits: 8, size: n, bytes: bytes}

# `%w[a b c]` / `%i[a b c]` — desugar the word/symbol list into a plain
# Array of String literal nodes and lower that. The token value (@words /
# @symbols) is a bare list of strings; reusing lower_array gives the result
# real Array semantics (.each/.map/.size/.push), matching the interpreter.
-> lower_word_or_symbol_array(ctx, words)
  elements = []
  i = 0
  while i < words.size()
    elements.push(Tungsten:AST:String.new(words[i]))
    i = i + 1
  lower_array(ctx, Tungsten:AST:Array.new(elements))

-> lower_array(ctx, node)
  wfn = ctx[:func]
  arr = next_temp(wfn)
  # Phase 5g: const-folding to SmallArray is gated off by default. The
  # element-only check in try_const_small_array bails on non-constant
  # *elements* but doesn't account for non-read-only *uses* — Array has
  # .each/.map/.push, SmallArray's dispatch is thin (size/cap/[]/empty?).
  # Folding `[1,2,3]` would break any caller that iterates or mutates it.
  # The infrastructure (mod[:small_array_consts], emitter pass, opcode)
  # stays so a future escape-analysis pass can flip this on. Opt-in via
  # node.const_safe when that pass exists.
  if node.const_safe == true
    cf = try_const_small_array(node.elements)
    if cf != nil
      consts = ctx[:mod][:small_array_consts]
      const_id = consts.size()
      name = "@.const_small_array_" + const_id.to_s()
      consts.push({name: name, ebits: cf[:ebits], size: cf[:size], bytes: cf[:bytes]})
      emit_instruction(wfn, {op: :small_array_const_load, temp: arr, const_name: name})
      return typed_value(:i64, arr)
  # ## reuse — empty [] gets a per-site thread-local slot, reused across calls.
  if node.reuse_safe == true && (node.elements == nil || node.elements.size() == 0)
    site_id = ctx[:mod][:next_reuse_site]
    ctx[:mod][:next_reuse_site] = site_id + 1
    slot_name = "reuse.site." + site_id.to_s()
    ctx[:mod][:reuse_sites].push(slot_name)
    emit_instruction(wfn, {op: :call_reuse_or_new_array, temp: arr, slot: slot_name})
    return typed_value(:i64, arr)
  # ## recycle — pop from thread-local pool or allocate. Recycled at scope exit.
  if node.recycle_safe == true && (node.elements == nil || node.elements.size() == 0)
    emit_instruction(wfn, {op: :call_recycle_or_new_array, temp: arr})
    track_recycle_temp(wfn, arr, :array)
    return typed_value(:i64, arr)
  emit_instruction(wfn, {op: :call_direct_i64, temp: arr, name: "w_array_new_empty", args: []})
  i = 0
  while i < node.elements.size()
    elem = node.elements[i]
    val = lower_expression(ctx, elem)
    # Per-element type ascription (`[1 ## T, …]`, concrete after
    # monomorphization `[1 ## f64, …]`). A float-typed integer literal must
    # enter the array as a float WValue, not a boxed int — otherwise the
    # matrix `inverse` (`cofactor / determinant`) and any element division
    # would do integer arithmetic. Mirrors the assignment-hint coercion.
    eh = elem.type_hint
    if eh != nil
      ht = eh.to_sym()
      if is_machine_float_type(ht)
        raw = nil
        if ht in (:f32 :raw_f32)
          raw = ensure_raw_f32(wfn, val)
        else
          raw = ensure_raw_f64(wfn, val)
        val = typed_value(raw_float_value_type(ht), raw)
    val_reg = ensure_i64_value(wfn, val)
    push_temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: push_temp, name: "w_array_push", args: [arr, val_reg]})
    i += 1
  typed_value(:i64, arr)

-> lower_hash_literal(ctx, node)
  wfn = ctx[:func]
  hash_reg = next_temp(wfn)
  # ## reuse_drain — reuse slot + recycle values to pools on reset.
  if node.reuse_safe == true && node.drain_safe == true && (node.entries == nil || node.entries.size() == 0)
    site_id = ctx[:mod][:next_reuse_site]
    ctx[:mod][:next_reuse_site] = site_id + 1
    slot_name = "reuse.site." + site_id.to_s()
    ctx[:mod][:reuse_sites].push(slot_name)
    emit_instruction(wfn, {op: :call_reuse_and_drain_or_new_hash, temp: hash_reg, slot: slot_name})
    return typed_value(:i64, hash_reg)
  # ## reuse — empty {} gets a per-site thread-local slot, reused across calls.
  if node.reuse_safe == true && (node.entries == nil || node.entries.size() == 0)
    site_id = ctx[:mod][:next_reuse_site]
    ctx[:mod][:next_reuse_site] = site_id + 1
    slot_name = "reuse.site." + site_id.to_s()
    ctx[:mod][:reuse_sites].push(slot_name)
    emit_instruction(wfn, {op: :call_reuse_or_new_hash, temp: hash_reg, slot: slot_name})
    return typed_value(:i64, hash_reg)
  # ## recycle — pop from thread-local pool or allocate. Recycled at scope exit.
  if node.recycle_safe == true && (node.entries == nil || node.entries.size() == 0)
    emit_instruction(wfn, {op: :call_recycle_or_new_hash, temp: hash_reg})
    track_recycle_temp(wfn, hash_reg, :hash)
    return typed_value(:i64, hash_reg)
  emit_instruction(wfn, {op: :call_direct_i64, temp: hash_reg, name: "w_hash_new", args: []})
  entries = node.entries
  i = 0
  while i < entries.size()
    entry = entries[i]
    key_val = lower_expression(ctx, entry[0])
    key_reg = ensure_i64_value(wfn, key_val)
    val_val = lower_expression(ctx, entry[1])
    val_reg = ensure_i64_value(wfn, val_val)
    set_temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: set_temp, name: "w_hash_set", args: [hash_reg, key_reg, val_reg]})
    i += 1
  # A call-site kwargs group (`f(a: 1)`) passes as ONE hash argument marked
  # W_HASH_FLAG_KWARGS; keyword-param callees rebind it by name at entry
  # (w_kwargs_remap12 prologue), everyone else receives a plain hash.
  if node.from_kwargs == true
    mark_temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: mark_temp, name: "w_hash_mark_kwargs", args: [hash_reg]})
  typed_value(:i64, hash_reg)

-> lower_symbol(ctx, node)
  s = node.value.to_s()
  byte_len = utf8_byte_length(s)
  # SSO-5: symbols ≤5 bytes are inline constants (string WValue | 1 for symbol bit).
  if byte_len <= 5
    v = sso5_wvalue(s) + 1
    return typed_value(:i64, wvalue_literal_text(v))
  # Slab-interned symbols (6-61 bytes) — WValue is resolved at emit
  # time once build_string_wvalues has assigned slab slot indices.
  # Symbols >61 bytes would force the runtime intern path
  # (w_string + w_str_to_sym), which defeats the purpose of symbols:
  # the resulting WValue depends on heap-allocator placement, so the
  # value isn't a stable identity, isn't switchable on its i64
  # representation, and breaks equality semantics for code that
  # interns them at different sites. The bootstrap codebase has zero
  # symbol literals over 61 bytes; rather than carry the runtime
  # path for a feature nothing exercises, reject the literal here.
  if byte_len > 61
    raise compile_error_for_node(:E_LOWER_SYMBOL_TOO_LONG, "Symbol literal too long ([byte_len] bytes; max 61). Use a string and ensure stable identity via your own logic if you really need a long-name handle.", ctx[:source_path], node)
  wfn = ctx[:func]
  str_id = module_string_constant(ctx[:mod], s)
  temp_ptr = next_temp(wfn)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :symbol_i64, temp: temp, temp_ptr: temp_ptr, string_id: str_id, byte_len: byte_len + 1})
  typed_value(:i64, temp)

-> lower_regex(ctx, node)
  wfn = ctx[:func]
  pattern_tv = lower_string(ctx, Tungsten:AST:String.new(node.pattern))
  options_tv = lower_string(ctx, Tungsten:AST:String.new(node.options))
  pattern_reg = ensure_i64_value(wfn, pattern_tv)
  options_reg = ensure_i64_value(wfn, options_tv)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_regex_new", args: [pattern_reg, options_reg]})
  typed_value(:i64, temp)

-> lower_regex_capture(ctx, node)
  wfn = ctx[:func]
  index_tv = lower_int(ctx, Tungsten:AST:Int.new(ast_get(node, :index)))
  index_reg = ensure_i64_value(wfn, index_tv)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_regex_capture", args: [index_reg]})
  typed_value(:i64, temp)

-> lower_range(ctx, node)
  wfn = ctx[:func]

  # Lower bounds and unbox to raw i64
  from_tv = lower_expression(ctx, node.from)
  from_reg = ensure_i64_value(wfn, from_tv)
  to_tv = lower_expression(ctx, node.to)
  to_reg = ensure_i64_value(wfn, to_tv)

  from_raw = next_temp(wfn)
  emit_instruction(wfn, {op: :nanunbox_int, temp: from_raw, temp_shl: from_raw + ".shl", boxed: from_reg})
  to_raw = next_temp(wfn)
  emit_instruction(wfn, {op: :nanunbox_int, temp: to_raw, temp_shl: to_raw + ".shl", boxed: to_reg})

  # Create empty array
  arr = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: arr, name: "w_array_new_empty", args: []})

  # Loop: phi counter from start to end, push each
  pre_label = next_label(wfn, "range.pre")
  header_label = next_label(wfn, "range.hdr")
  body_label = next_label(wfn, "range.body")
  exit_label = next_label(wfn, "range.exit")

  emit_instruction(wfn, {op: :br, label: pre_label})
  start_block(wfn, pre_label)
  emit_instruction(wfn, {op: :br, label: header_label})

  start_block(wfn, header_label)
  phi_reg = next_temp(wfn)
  inc_reg = next_temp(wfn)
  emit_instruction(wfn, {op: :phi_i64, temp: phi_reg, a_value: from_raw, a_label: pre_label, b_value: inc_reg, b_label: body_label})

  # Bound check
  cmp_op = "sle"
  if node.exclusive == true
    cmp_op = "slt"
  cmp_reg = next_temp(wfn)
  emit_instruction(wfn, {op: :icmp_i64, temp: cmp_reg, pred: cmp_op, lhs: phi_reg, rhs: to_raw})
  emit_instruction(wfn, {op: :cond_br, cond: cmp_reg, then_label: body_label, else_label: exit_label})

  # Body: nanbox counter, push to array, increment
  start_block(wfn, body_label)
  boxed = next_temp(wfn)
  emit_instruction(wfn, {op: :nanbox_int, temp: boxed, temp_masked: boxed + ".m", raw: phi_reg})
  push_tmp = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: push_tmp, name: "w_array_push", args: [arr, boxed]})
  emit_instruction(wfn, {op: :add_i64, temp: inc_reg, lhs: phi_reg, rhs: "1"})
  emit_instruction(wfn, {op: :br, label: header_label})

  # Exit
  start_block(wfn, exit_label)
  typed_value(:i64, arr)



# -- Deep literal lowerings (Phase 6 domain types) --

-> lower_float(ctx, node)
  typed_value(:raw_f64, node.value.to_s())

-> lower_decimal(ctx, node)
  wfn = ctx[:func]
  # Parse decimal string into sig * 10^scale
  s = node.value.to_s()
  # Remove underscores
  clean = ""
  i = 0
  while i < s.size()
    c = s[i]
    if c != "_"
      clean = clean + c
    i = i + 1
  s = clean
  neg = false
  if s.size() > 0 && s[0] == "-"
    neg = true
    s = s.slice(1, s.size())
  # Handle scientific notation (e.g., 1.5e-3)
  e_idx = s.index("e")
  if e_idx == nil
    e_idx = s.index("E")
  exp_adj = 0
  if e_idx != nil
    exp_str = s.slice(e_idx + 1, s.size())
    exp_adj = exp_str.to_i()
    s = s.slice(0, e_idx)
  # Find decimal point
  dot = s.index(".")
  if dot == nil
    sig = s.to_i()
    scale = 0 + exp_adj
  else
    int_part = s.slice(0, dot)
    frac_part = s.slice(dot + 1, s.size())
    sig_str = int_part + frac_part
    sig = sig_str.to_i()
    scale = 0 - frac_part.size() + exp_adj
  if neg
    sig = 0 - sig
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :const_decimal, temp: temp, sig: sig, scale: scale})
  typed_value(:i64, temp)

-> lower_typed_array_new(ctx, node)
  wfn = ctx[:func]
  etype = node.element_type
  size_tv = lower_expression(ctx, ast_get(node, :size))
  size_reg = ensure_i64_value(wfn, size_tv)
  # Unbox the size to raw i64 for the runtime call
  size_raw = nanunbox_int_emit(wfn, size_reg)
  if etype == "bool"
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_bool_array_new", args: [size_raw]})
    return typed_value(:i64, temp)

  # Map type name to element bits.
  # Extended bits carry signed/float-ish element identity in the runtime.
  # Bits == 65 is the w64 sentinel (64-bit WValue storage, no int coercion).
  bits = 0
  if etype == "u1" || etype == "i1"
    # 1-bit packed array. Same storage as bool[N] / BoolArray.new(N),
    # but raw — caller is responsible for passing 0/1 (or true/false,
    # which the runtime's ebits==1 fast path normalizes). BoolArray is
    # the wrapper class that surfaces a true/false API on top of this.
    bits = 1
  elsif etype == "u4"
    bits = 4
  elsif etype == "i4"
    bits = -4
  elsif etype == "u8"
    bits = 8
  elsif etype == "i8"
    bits = 108
  elsif etype == "u16"
    bits = 16
  elsif etype == "i16"
    bits = 116
  elsif etype in ("u32" "i32")
    bits = 32
  elsif etype in ("u64" "i64")
    bits = 64
  elsif etype == "f32"
    bits = -32
  elsif etype == "bf16"
    bits = -116
  elsif etype == "w64"
    bits = 65
  elsif etype == "f64"
    bits = -64

  if bits != 0
    # ## reuse — per-site thread-local slot reused across calls. Shape is
    # stable (same element_bits) at a given site; capacity grows as needed.
    if node.reuse_safe == true
      site_id = ctx[:mod][:next_reuse_site]
      ctx[:mod][:next_reuse_site] = site_id + 1
      slot_name = "reuse.site." + site_id.to_s()
      ctx[:mod][:reuse_sites].push(slot_name)
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_reuse_or_new_typed, temp: temp, slot: slot_name, bits: bits, cap: size_raw})
      return typed_value(:i64, temp)
    # ## recycle — pop from shape-keyed pool. Recycled at scope exit.
    if node.recycle_safe == true
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :call_recycle_or_new_typed, temp: temp, bits: bits, cap: size_raw})
      track_recycle_temp(wfn, temp, :typed)
      return typed_value(:i64, temp)
    # T[N] semantics: zero-filled buffer with size = cap = N, ready to
    # read or index-write without bounds-growth checks. Push-to-fill
    # (`t = i32[N]; t.push(…)`) is no longer the canonical idiom; the
    # inline `[]=` path assumes size == cap and skips the size update.
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_array_zeros", args: [bits.to_s(), size_raw]})
    return typed_value(:i64, temp)

  # Fallback: unsupported typed array → regular array
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_array_new_empty", args: []})
  typed_value(:i64, temp)

-> lookup_currency_id(prefix, suffix)
  # Map currency symbol to symbol_id matching runtime.c currency_symbols table
  # Prefix currencies
  if prefix != nil
    case prefix
      "$" => 0
      "€" => 1
      "£" => 2
      "¥" => 3
      "₹" => 4
      "₩" => 6
      "₿" => 7
      "₽" => 12
      "฿" => 13
      "Fr" => 8
      "C$" => 9
      "A$" => 10
      "R$" => 11
      "zł" => 14
      => 0
  # Suffix currencies
  if suffix != nil
    case suffix
      "p" => 2
      "¢" => 0
      "円" => 3
      "元" => 5
      "/-" => 4
      => 0
  0

# Sub-unit suffixes denominate in 1/100 of the family's main unit: 25¢ is
# $0.25, 5p is £0.05. Main-unit suffixes (円, 元, /-) shift nothing.
-> currency_suffix_scale_shift(suffix)
  if suffix == "¢" || suffix == "p"
    return -2
  0

-> lower_currency(ctx, node)
  wfn = ctx[:func]
  amount_str = node.amount.replace("_", "")
  prefix = node.prefix
  suffix = node.suffix

  # Map symbol to symbol_id
  symbol_id = lookup_currency_id(prefix, suffix)

  # Parse amount string into sig and scale
  sig_scale = parse_sig_scale(amount_str)
  sig = sig_scale[0]
  scale = sig_scale[1]
  if suffix != nil
    scale = scale + currency_suffix_scale_shift(suffix)

  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :const_currency, temp: temp, symbol_id: symbol_id, sig: sig, scale: scale})
  typed_value(:i64, temp)

-> lower_quantity(ctx, node)
  wfn = ctx[:func]
  number_str = node.number_str.replace("_", "")
  unit = node.unit

  # Parse number into sig and scale
  sig_scale = parse_sig_scale(number_str)
  sig = sig_scale[0]
  scale = sig_scale[1]

  # Map unit string to unit_id
  unit_id = lookup_unit_id(ctx, unit, node)

  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :const_quantity, temp: temp, unit_id: unit_id, sig: sig, scale: scale})
  typed_value(:i64, temp)

# Conservative static quantity inference. It deliberately proves only facts
# available without executing user code; unknown expressions return nil and
# continue through the runtime dimension checker.
-> static_quantity_signature(ctx, node)
  if node == nil || !is_ast_node?(node)
    return nil
  kind = ast_kind(node)
  if kind == :quantity
    return lookup_unit_static_signature(node.unit)
  if kind == :var && ctx[:quantity_dimensions] != nil
    return ctx[:quantity_dimensions][node.name]
  if kind == :call && node.receiver != nil && node.name in ("point" "delta")
    return static_quantity_signature(ctx, node.receiver)
  if kind == :binary_op
    left = static_quantity_signature(ctx, node.left)
    right = static_quantity_signature(ctx, node.right)
    if node.op in (:PLUS :MINUS) && left != nil && left == right
      return left
  nil

-> static_quantity_add_compatible?(left, right)
  if left == right
    return true
  temperature = "0,0,0,0,1,0,0,0,"
  temperature_delta = "0,0,0,0,1,0,0,0,temperature_delta:1"
  if left == temperature && right == temperature_delta
    return true
  if left == temperature_delta && right == temperature
    return true
  false

-> lower_duration(ctx, node)
  wfn = ctx[:func]
  raw = node.raw

  # Parse duration string into ns or months+ms
  parsed = parse_duration(raw, ctx, node)

  temp = next_temp(wfn)
  if parsed[:mode] == 0
    emit_instruction(wfn, {op: :const_duration_ns, temp: temp, ns: parsed[:ns]})
  else
    emit_instruction(wfn, {op: :const_duration_months_ms, temp: temp, months: parsed[:months], ms: parsed[:ms]})
  typed_value(:i64, temp)

-> lower_uuid(ctx, node)
  wfn = ctx[:func]
  str_id = module_string_constant(ctx[:mod], node.value)
  byte_len = utf8_byte_length(node.value) + 1
  temp_ptr = next_temp(wfn)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :const_uuid, temp: temp, temp_ptr: temp_ptr, string_id: str_id, byte_len: byte_len})
  typed_value(:i64, temp)

-> lower_date(ctx, node)
  wfn = ctx[:func]
  # Parse "YYYY-MM-DD" or "YYYY-DDD" (ordinal)
  raw = node.value
  parts = raw.split("-")
  year = parts[0].to_i()
  month = 0
  day = 0
  if parts.size() == 3
    month = parts[1].to_i()
    day = parts[2].to_i()
    validate_date(year, month, day, raw, ctx, node)
  elsif parts.size() == 2 && parts[1].size() == 3
    # Ordinal date YYYY-DDD: store day-of-year, month=0
    day = parts[1].to_i()
    if day < 1 || day > 366
      raise compile_error_for_node(:E_LOWER_DATE_INVALID_ORDINAL, "Invalid ordinal day in date literal: " + raw, ctx[:source_path], node)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :const_date, temp: temp, year: year, month: month, day: day, hour: 0, min: 0, sec: 0, tz: 0})
  typed_value(:i64, temp)

-> lower_datetime(ctx, node)
  wfn = ctx[:func]
  # Parse "YYYY-MM-DDThh:mm:ss[.frac][±hh:mm|Z]"
  raw = node.value
  t_idx = raw.index("T")
  date_part = raw.slice(0, t_idx)
  time_part = raw.slice(t_idx + 1, raw.size() - t_idx - 1)
  # Parse date
  dp = date_part.split("-")
  year = dp[0].to_i()
  month = dp[1].to_i()
  day = dp[2].to_i()
  validate_date(year, month, day, raw, ctx, node)
  # Parse time with timezone
  parsed = parse_time_string(time_part)
  validate_time(parsed[:hour], parsed[:min], parsed[:sec], raw, ctx, node)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :const_date, temp: temp, year: year, month: month, day: day, hour: parsed[:hour], min: parsed[:min], sec: parsed[:sec], tz: parsed[:tz]})
  typed_value(:i64, temp)

-> lower_time(ctx, node)
  wfn = ctx[:func]
  # Parse "hh:mm:ss[.frac][±hh:mm|Z]"
  parsed = parse_time_string(node.value)
  validate_time(parsed[:hour], parsed[:min], parsed[:sec], node.value, ctx, node)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :const_date, temp: temp, year: 0, month: 0, day: 0, hour: parsed[:hour], min: parsed[:min], sec: parsed[:sec], tz: parsed[:tz]})
  typed_value(:i64, temp)

-> parse_time_string(s)
  # Parse "hh:mm:ss[.frac][±hh:mm|Z]" → {hour, min, sec, tz}
  hour = 0
  min = 0
  sec = 0
  tz = 0
  # Strip timezone suffix
  if s.ends_with?("Z")
    s = s.slice(0, s.size() - 1)
    tz = 0
  else
    # Check for +/-hh:mm or +/-hh timezone
    plus_idx = s.rindex("+")
    minus_idx = s.rindex("-")
    tz_idx = nil
    if plus_idx != nil && plus_idx > 2
      tz_idx = plus_idx
    elsif minus_idx != nil && minus_idx > 2
      tz_idx = minus_idx
    if tz_idx != nil
      tz_str = s.slice(tz_idx, s.size() - tz_idx)
      s = s.slice(0, tz_idx)
      tz_parts = tz_str.split(":")
      # to_i keeps the sign ("-05" -> -5); take the magnitude so minutes
      # add toward zero, then apply the sign once to the whole offset.
      neg = tz_str.starts_with?("-")
      tz_h = tz_parts[0].to_i()
      if tz_h < 0
        tz_h = 0 - tz_h
      tz_m = 0
      if tz_parts.size() > 1
        tz_m = tz_parts[1].to_i()
      tz = tz_h * 60 + tz_m
      if neg
        tz = 0 - tz
  # Parse hh:mm:ss[.frac]
  time_parts = s.split(":")
  hour = time_parts[0].to_i()
  if time_parts.size() > 1
    min = time_parts[1].to_i()
  if time_parts.size() > 2
    sec_str = time_parts[2]
    # Strip fractional seconds
    dot_idx = sec_str.index(".")
    if dot_idx != nil
      sec_str = sec_str.slice(0, dot_idx)
    sec = sec_str.to_i()
  {hour: hour, min: min, sec: sec, tz: tz}

-> validate_date(year, month, day, raw, ctx, node)
  if month < 1 || month > 12
    raise compile_error_for_node(:E_LOWER_DATE_INVALID_MONTH, "Invalid month in date literal: " + raw, ctx[:source_path], node)
  max_day = 31
  if month in (4 6 9 11)
    max_day = 30
  elsif month == 2
    # Leap year check
    is_leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
    if is_leap
      max_day = 29
    else
      max_day = 28
  if day < 1 || day > max_day
    raise compile_error_for_node(:E_LOWER_DATE_INVALID_DAY, "Invalid day in date literal: " + raw, ctx[:source_path], node)
  nil

-> validate_time(hour, min, sec, raw, ctx, node)
  if hour < 0 || hour > 23
    raise compile_error_for_node(:E_LOWER_TIME_INVALID_HOUR, "Invalid hour in time literal: " + raw, ctx[:source_path], node)
  if min < 0 || min > 59
    raise compile_error_for_node(:E_LOWER_TIME_INVALID_MINUTE, "Invalid minute in time literal: " + raw, ctx[:source_path], node)
  if sec < 0 || sec > 59
    raise compile_error_for_node(:E_LOWER_TIME_INVALID_SECOND, "Invalid second in time literal: " + raw, ctx[:source_path], node)
  nil

-> check_type_algebra(lt, rt, op, node)
  # Detect obviously invalid type combinations at compile time
  # Valid arithmetic combinations pass through to runtime dispatch
  if lt in (:date :time)
    if op == :PLUS
      # date + duration → OK, date + int → OK, date + date → ERROR
      if rt in (:date :time :ip4 :ip6 :rational :uuid)
        raise compile_error_for_node(:E_TYPE_CANNOT_ADD, "Invalid operation: cannot add " + lt.to_s() + " + " + rt.to_s(), nil, node)
    if op == :MINUS
      # date - date → OK (duration), date - duration → OK, date - string → ERROR
      if rt in (:ip4 :ip6 :uuid :string)
        raise compile_error_for_node(:E_TYPE_CANNOT_SUBTRACT, "Invalid operation: cannot subtract " + lt.to_s() + " - " + rt.to_s(), nil, node)
  if lt in (:ip4 :ip6)
    if rt in (:date :time :string :rational :uuid)
      if op in (:PLUS :MINUS :STAR :SLASH)
        raise compile_error_for_node(:E_TYPE_CANNOT_USE_OP, "Invalid operation: cannot use " + op.to_s() + " with " + lt.to_s() + " and " + rt.to_s(), nil, node)
  if lt == :uuid
    if op in (:PLUS :MINUS :STAR :SLASH)
      raise compile_error_for_node(:E_TYPE_UUID_ARITHMETIC, "Invalid operation: cannot use arithmetic on UUID", nil, node)
  nil

-> lower_ipv4(ctx, node)
  wfn = ctx[:func]
  # Parse "a.b.c.d" or "a.b.c.d:port"
  raw = node.value
  # Strip port if present
  colon_idx = raw.index(":")
  if colon_idx != nil
    raw = raw.slice(0, colon_idx)
  parts = raw.split(".")
  a = parts[0].to_i()
  b = parts[1].to_i()
  c = parts[2].to_i()
  d = parts[3].to_i()
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :const_ipv4, temp: temp, a: a, b: b, c: c, d: d, cidr: -1})
  typed_value(:i64, temp)

-> lower_cidr4(ctx, node)
  wfn = ctx[:func]
  # Parse "a.b.c.d/prefix"
  raw = node.value
  slash_idx = raw.index("/")
  ip_part = raw.slice(0, slash_idx)
  prefix = raw.slice(slash_idx + 1, raw.size() - slash_idx - 1).to_i()
  parts = ip_part.split(".")
  a = parts[0].to_i()
  b = parts[1].to_i()
  c = parts[2].to_i()
  d = parts[3].to_i()
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :const_ipv4, temp: temp, a: a, b: b, c: c, d: d, cidr: prefix})
  typed_value(:i64, temp)

-> lower_ipv6(ctx, node)
  wfn = ctx[:func]
  # String-based (like lower_uuid): intern the canonical address text and let
  # the runtime parse it into 16 bytes. cidr -1 = plain address.
  str_id = module_string_constant(ctx[:mod], node.value)
  byte_len = utf8_byte_length(node.value) + 1
  temp_ptr = next_temp(wfn)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :const_ipv6, temp: temp, temp_ptr: temp_ptr, string_id: str_id, byte_len: byte_len, cidr: -1})
  typed_value(:i64, temp)

-> lower_cidr6(ctx, node)
  wfn = ctx[:func]
  # "addr/prefix" — intern the address without the prefix; pass prefix as cidr.
  raw = node.value
  slash_idx = raw.index("/")
  addr = raw.slice(0, slash_idx)
  prefix = raw.slice(slash_idx + 1, raw.size() - slash_idx - 1).to_i()
  str_id = module_string_constant(ctx[:mod], addr)
  byte_len = utf8_byte_length(addr) + 1
  temp_ptr = next_temp(wfn)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :const_ipv6, temp: temp, temp_ptr: temp_ptr, string_id: str_id, byte_len: byte_len, cidr: prefix})
  typed_value(:i64, temp)

-> lower_rational(ctx, node)
  wfn = ctx[:func]
  # Parse "num/den"
  raw = node.value
  slash_idx = raw.index("/")
  num = raw.slice(0, slash_idx).to_i()
  den = raw.slice(slash_idx + 1, raw.size() - slash_idx - 1).to_i()
  if den == 0
    raise compile_error_for_node(:E_LOWER_RATIONAL_ZERO_DENOM, "Rational literal with zero denominator: " + raw, ctx[:source_path], node)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :const_rational, temp: temp, num: num, den: den})
  typed_value(:i64, temp)

-> lower_char(ctx, node)
  # `:-X` ASCII char literal → `:char`-typed compile-time constant.
  # At the machine level `:char` compiles to u8 (zero-extended to i64
  # when nanboxed), but at the type level it's a distinct `:char` so
  # downstream arithmetic and method dispatch can preserve character
  # semantics.
  typed_value(:char, node.value.to_s())

-> lower_codepoint(ctx, node)
  # `U+XXXX` Unicode codepoint literal → boxed Codepoint wvalue.
  # Emits const_char (the IR op name predates the CHAR vs CODEPOINT
  # token split) which calls w_box_char at runtime. Use when you
  # need a first-class codepoint value with the 0xFFFC tag.
  wfn = ctx[:func]
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :const_char, temp: temp, codepoint: node.value})
  typed_value(:i64, temp)

-> lower_color(ctx, node)
  wfn = ctx[:func]
  temp = next_temp(wfn)
  packed = node.rgba
  emit_instruction(wfn, {op: :const_color, temp: temp,
    r: (packed >> 24) & 0xff,
    g: (packed >> 16) & 0xff,
    b: (packed >> 8) & 0xff,
    a: packed & 0xff})
  typed_value(:i64, temp)

-> lower_cidr_match(ctx, node)
  wfn = ctx[:func]
  # Lower both the subject (IP) and the CIDR pattern
  subj_tv = lower_expression(ctx, node.subject)
  cidr_tv = lower_expression(ctx, node.cidr)
  subj_reg = ensure_i64_value(wfn, subj_tv)
  cidr_reg = ensure_i64_value(wfn, cidr_tv)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_ipv4_in_cidr", args: [subj_reg, cidr_reg]})
  typed_value(:i64, temp)

-> lower_regex_match(ctx, node)
  wfn = ctx[:func]
  regex_tv = lower_expression(ctx, node.regex)
  subject_tv = lower_expression(ctx, node.subject)
  regex_reg = ensure_i64_value(wfn, regex_tv)
  subject_reg = ensure_i64_value(wfn, subject_tv)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_regex_match", args: [regex_reg, subject_reg]})
  typed_value(:i64, temp)



# -- Domain helpers (sig/scale, units, durations) --

-> parse_sig_scale(s)
  # Parse a decimal number string into [significand, scale]
  # Convention: negative scale = fractional digits
  # "5.25" → [525, -2], "100" → [100, 0], "3.5" → [35, -1]
  # "2e46" → [2, 46], "1.5e-3" → [15, -4]

  # Handle scientific notation: split on e/E
  e_idx = s.index("e")
  if e_idx == nil
    e_idx = s.index("E")
  if e_idx != nil
    base = s.slice(0, e_idx)
    exp_str = s.slice(e_idx + 1, s.size() - e_idx - 1)
    base_result = parse_sig_scale(base)
    exp = exp_str.to_i()
    return [base_result[0], base_result[1] + exp]

  dot = s.index(".")
  if dot == nil
    return [s.to_i(), 0]
  int_part = s.slice(0, dot)
  frac_part = s.slice(dot + 1, s.size() - dot - 1)
  scale = 0 - frac_part.size()
  sig = (int_part + frac_part).to_i()
  [sig, scale]

# --- BEGIN GENERATED: lookup_unit_id ---
-> lookup_unit_id(ctx, raw_unit, node)
  # Materialize the scrutinee: node-field strings can be lexer slices, whose
  # WValue bits never equal the interned case keys in the switch_i64 dispatch.
  unit = "" + raw_unit
  case unit
    "%" => 255
    "1/mol" => 101
    "A" => 3
    "A/m²" => 652
    "AU tbsp" => 601
    "Apgar" => 700
    "B" => 89
    "B/flop" => 676
    "BOE" => 531
    "BPM" => 703
    "BTU" => 369
    "Ba" => 359
    "Beaufort" => 694
    "Bortle" => 693
    "Bps" => 392
    "Bq" => 23
    "C" => 12
    "C/m³" => 655
    "CWT" => 293
    "Ci" => 376
    "D" => 480
    "DMIPS" => 732
    "DWORD" => 605
    "Da" => 296
    "EF" => 697
    "EF-scale" => 697
    "EFLOPS" => 718
    "EOPS" => 729
    "EV" => 612
    "Eflops" => 717
    "Eh" => 584
    "EiB" => 390
    "F" => 14
    "F-scale" => 696
    "F/m" => 104
    "FLOPS" => 706
    "FPS" => 704
    "Fr_catheter" => 637
    "GB" => 92
    "GFLOPS" => 712
    "GHz" => 43
    "GIPS" => 731
    "GJ" => 47
    "GMAC/s" => 735
    "GOPS" => 726
    "GPa" => 59
    "GT/s" => 743
    "GW" => 50
    "Ga" => 375
    "Gal" => 385
    "Gb" => 479
    "Gflops" => 711
    "GiB" => 97
    "Gtok/s" => 740
    "Gy" => 24
    "H" => 19
    "HB" => 488
    "HRC" => 487
    "HU" => 702
    "HV" => 486
    "Hz" => 7
    "IOPS" => 754
    "ISO" => 614
    "ISO sensitivity" => 614
    "ISO_speed" => 614
    "J" => 10
    "J/(kg·K)" => 648
    "J/(mol·K)" => 103
    "J/K" => 102
    "J/kg" => 660
    "J/kg/K" => 648
    "J/m³" => 659
    "J/op" => 674
    "J/tok" => 675
    "Jy" => 466
    "J·s" => 99
    "K" => 4
    "KB" => 90
    "KOPS" => 724
    "KiB" => 95
    "L" => 78
    "L per 100 km" => 525
    "L/100km" => 525
    "L/min" => 644
    "LT" => 295
    "La" => 426
    "MAC/s" => 733
    "MB" => 91
    "MFLOPS" => 710
    "MHz" => 42
    "MIPS" => 730
    "MJ" => 46
    "MMAC/s" => 734
    "MOPS" => 725
    "MPG" => 523
    "MPGe" => 524
    "MPa" => 58
    "MT/s" => 742
    "MV" => 56
    "MW" => 49
    "MWh" => 52
    "M_bol" => 469
    "Mach at 20 C" => 692
    "Mach in air at 20 C" => 692
    "Mag" => 468
    "Mbol" => 469
    "Mflops" => 709
    "MiB" => 96
    "Mohs" => 485
    "Mtok/s" => 739
    "Mw" => 699
    "Mx" => 422
    "M⊕" => 399
    "M☉" => 398
    "M☽" => 401
    "M♃" => 400
    "N" => 8
    "N/A²" => 105
    "N/m" => 656
    "N·m" => 672
    "N·s" => 671
    "Oe" => 478
    "P" => 394
    "PB" => 94
    "PFLOPS" => 716
    "POPS" => 728
    "PPS" => 752
    "PS" => 374
    "Pa" => 9
    "Pflops" => 715
    "PiB" => 389
    "Planck length" => 287
    "Planck mass" => 299
    "Planck time" => 326
    "QALY" => 688
    "QALYs" => 688
    "QPS" => 746
    "QWORD" => 606
    "RBE" => 701
    "RPS" => 748
    "RU" => 277
    "Richter" => 698
    "Ry" => 585
    "R⊕" => 403
    "R☉" => 402
    "S" => 16
    "S/m" => 654
    "SS_category" => 695
    "Saffir-Simpson" => 695
    "St" => 396
    "Sv" => 25
    "T" => 18
    "T/s" => 741
    "TB" => 93
    "TCE" => 532
    "TFLOPS" => 714
    "THz" => 44
    "TMAC/s" => 736
    "TOPS" => 727
    "TPS" => 750
    "TT/s" => 744
    "Tflops" => 713
    "TiB" => 98
    "Torr" => 113
    "V" => 13
    "V/m" => 651
    "W" => 11
    "W/(m²·K⁴)" => 106
    "W/(m·K)" => 649
    "W/m/K" => 649
    "W/m²" => 650
    "Wb" => 17
    "YFLOPS" => 722
    "Yflops" => 721
    "ZFLOPS" => 720
    "Zflops" => 719
    "a0" => 586
    "a_0" => 586
    "ab-1" => 475
    "ab^-1" => 475
    "abarn" => 471
    "abinv" => 475
    "absolute magnitude" => 468
    "ab⁻¹" => 475
    "ac" => 327
    "acre" => 74
    "acres" => 327
    "alpha" => 590
    "altuve" => 409
    "altuves" => 409
    "amah" => 496
    "amot" => 496
    "ampere" => 3
    "amperes" => 3
    "amperes per square meter" => 652
    "amphora" => 572
    "amphorae" => 572
    "amphoras" => 572
    "angstrom" => 278
    "angstroms" => 278
    "angular acceleration" => 668
    "angular velocity" => 667
    "apgar" => 700
    "apgar score" => 700
    "apostilb" => 428
    "apostilbs" => 428
    "apparent magnitude" => 467
    "arcmin" => 379
    "arcsec" => 380
    "areal density" => 658
    "aroura" => 577
    "arourae" => 577
    "arouras" => 577
    "arpent" => 564
    "arpents" => 564
    "arshin" => 555
    "arshins" => 555
    "asb" => 428
    "astronomical unit" => 116
    "astronomical units" => 116
    "at" => 360
    "atm" => 110
    "atmosphere" => 110
    "atmospheres" => 110
    "attobarn" => 471
    "attobarns" => 471
    "au" => 116
    "australian tablespoon" => 601
    "australian tablespoons" => 601
    "australian tbsp" => 601
    "australian_tbsp" => 601
    "b" => 386
    "baker's dozen" => 493
    "bakers dozen" => 493
    "bakers_dozen" => 493
    "ban" => 458
    "banana" => 417
    "banana for scale" => 641
    "banana_for_scale" => 641
    "bananas" => 417
    "bananas for scale" => 641
    "bar" => 111
    "barleycorn" => 625
    "barleycorns" => 625
    "barn" => 328
    "barn megaparsec" => 416
    "barn-megaparsec" => 416
    "barn-megaparsecs" => 416
    "barns" => 328
    "barrel" => 412
    "barrel of oil equivalent" => 531
    "barrels" => 412
    "barye" => 359
    "basis point" => 619
    "basis points" => 619
    "basis_point" => 619
    "basis_points" => 619
    "bath" => 506
    "baths" => 506
    "baud" => 393
    "beard second" => 415
    "beard seconds" => 415
    "beard-second" => 415
    "beard-seconds" => 415
    "beat" => 435
    "beats" => 435
    "beats per minute" => 703
    "beaufort" => 694
    "becquerel" => 23
    "becquerels" => 23
    "beka" => 514
    "bekah" => 514
    "bekas" => 514
    "biblical talent" => 512
    "biblical_mil" => 500
    "biblical_mina" => 511
    "biblical_talent" => 512
    "billions and billions" => 639
    "bit" => 88
    "bit/(s·Hz)" => 673
    "bit/s/Hz" => 673
    "bits" => 386
    "bits per second per hertz" => 673
    "block" => 610
    "blocks" => 610
    "boe" => 531
    "bohr magneton" => 481
    "bohr_magneton" => 481
    "bohr_radius" => 586
    "boiler horsepower" => 595
    "boiler_horsepower" => 595
    "bolometric magnitude" => 469
    "bortle" => 693
    "bottle" => 353
    "bottles" => 353
    "bp_finance" => 619
    "bpm" => 703
    "bps" => 391
    "brad" => 384
    "brads" => 384
    "brinell" => 488
    "bu" => 335
    "bushel" => 335
    "bushels" => 335
    "butt" => 349
    "byte" => 89
    "bytes" => 89
    "bytes per flop" => 676
    "cP" => 395
    "cSt" => 397
    "cable" => 280
    "cable length" => 629
    "cable lengths" => 629
    "cable_length" => 629
    "cables" => 280
    "cal" => 108
    "calorie" => 108
    "calories" => 108
    "candela" => 6
    "candela per square meter" => 664
    "candelas" => 6
    "carat" => 306
    "carats" => 306
    "catalytic activity concentration" => 663
    "cd" => 6
    "cd/m²" => 664
    "celsius" => 20
    "celsius difference" => 263
    "cent" => 615
    "cent_pitch" => 615
    "centipoise" => 395
    "centistokes" => 397
    "cents" => 615
    "centuries" => 317
    "century" => 317
    "ch" => 273
    "chain" => 273
    "chains" => 273
    "charge density" => 655
    "chelakim" => 515
    "chelek" => 515
    "chetvert" => 560
    "chetverts" => 560
    "chi" => 545
    "chinese dan" => 553
    "chinese li" => 549
    "chinese_dan" => 553
    "chinese_li" => 549
    "chis" => 545
    "cicero" => 408
    "cloth nail" => 628
    "cluster" => 611
    "clusters" => 611
    "cm" => 28
    "cm-1" => 484
    "cmH2O" => 365
    "cm^-1" => 484
    "cm²" => 71
    "cm³" => 77
    "cm⁻¹" => 484
    "compton wavelength" => 587
    "compton wavelength electron" => 587
    "compton wavelength neutron" => 589
    "compton wavelength proton" => 588
    "compton_e" => 587
    "compton_n" => 589
    "compton_p" => 588
    "compton_wavelength" => 587
    "conductivity" => 654
    "cord" => 414
    "cords" => 414
    "coulomb" => 12
    "coulombs" => 12
    "coulombs per cubic meter" => 655
    "crumb" => 604
    "crumbs" => 604
    "css rem" => 684
    "ct" => 306
    "cubic meters per second" => 643
    "cubit" => 496
    "cubits" => 496
    "cun" => 546
    "cuns" => 546
    "cup" => 330
    "cups" => 330
    "curie" => 376
    "curies" => 376
    "current density" => 652
    "cwt" => 292
    "cyc" => 436
    "cycle" => 436
    "cycles" => 436
    "d" => 310
    "dalton" => 296
    "daltons" => 296
    "dan_cn" => 553
    "dash" => 340
    "dashes" => 340
    "day" => 310
    "days" => 310
    "debye" => 480
    "debyes" => 480
    "decade" => 314
    "decades" => 314
    "decay" => 444
    "decays" => 444
    "deciban" => 459
    "decibans" => 459
    "decitex" => 636
    "deg" => 378
    "degree" => 378
    "degrees" => 378
    "delisle" => 257
    "delta celsius" => 263
    "delta fahrenheit" => 264
    "delta kelvin" => 262
    "delta rankine" => 265
    "denier" => 634
    "deniers" => 634
    "didot" => 407
    "digit" => 575
    "digits" => 575
    "dit" => 458
    "dits" => 458
    "dog year" => 325
    "dog years" => 325
    "dogyear" => 325
    "donkey power" => 598
    "donkey-power" => 598
    "donkeypower" => 598
    "dots per inch" => 682
    "dots per pixel" => 683
    "dozen" => 489
    "dozens" => 489
    "dpi" => 682
    "dppx" => 683
    "dr" => 289
    "drachm" => 289
    "drams" => 289
    "drop" => 339
    "drops" => 339
    "dword" => 605
    "dwords" => 605
    "dwt" => 305
    "dyn" => 372
    "dyne" => 372
    "dynes" => 372
    "eV" => 107
    "earth mass" => 399
    "earth radius" => 403
    "earthmass" => 399
    "earthradius" => 403
    "egypt_palm" => 574
    "egyptian palm" => 574
    "egyptian palms" => 574
    "electric field" => 651
    "electric horsepower" => 596
    "electric_horsepower" => 596
    "electron mass" => 591
    "electron_mass" => 591
    "electronvolt" => 107
    "electronvolts" => 107
    "em" => 430
    "en" => 431
    "energy density" => 659
    "english cubit" => 627
    "english cubits" => 627
    "english_cubit" => 627
    "enhanced fujita" => 697
    "entropy" => 647
    "ephah" => 504
    "ephahs" => 504
    "ephas" => 504
    "erg" => 368
    "etzba" => 499
    "etzbaot" => 499
    "ev" => 612
    "e₀" => 118
    "f stop" => 613
    "f-stop" => 613
    "f-stops" => 613
    "fL" => 427
    "f_stop" => 613
    "fahrenheit" => 87
    "fahrenheit difference" => 264
    "farad" => 14
    "farads" => 14
    "fathom" => 279
    "fathoms" => 279
    "fb-1" => 474
    "fb^-1" => 474
    "fbarn" => 470
    "fbinv" => 474
    "fb⁻¹" => 474
    "feet" => 61
    "feet of water" => 632
    "femtobarn" => 470
    "femtobarns" => 470
    "fen" => 547
    "fens" => 547
    "fine structure constant" => 590
    "fine_structure" => 590
    "fingerbreadth" => 499
    "firkin" => 344
    "firkins" => 344
    "fl dr" => 333
    "fl oz" => 66
    "fldr" => 333
    "flop" => 446
    "flops" => 705
    "flops_count" => 446
    "floz" => 332
    "fluid dram" => 333
    "fluid drams" => 333
    "fluid ounce" => 332
    "fluid ounces" => 332
    "foot" => 61
    "foot of water" => 632
    "foot pound" => 371
    "foot pounds" => 371
    "foot-lambert" => 427
    "foot-pound" => 371
    "foot-pounds" => 371
    "fortnight" => 316
    "fortnights" => 316
    "fps" => 704
    "frame" => 437
    "frames" => 437
    "frames per second" => 704
    "french gauge" => 637
    "french_gauge" => 637
    "fstop" => 613
    "ft" => 61
    "ft H2O" => 632
    "ft of water" => 632
    "ftH2O" => 632
    "ftlbf" => 371
    "ft²" => 75
    "fujita" => 696
    "fujita scale" => 696
    "funt" => 559
    "funt_ru" => 559
    "fur" => 271
    "furlong" => 271
    "furlongs" => 271
    "g" => 33
    "g CO2e" => 678
    "g0" => 520
    "gCO₂e" => 678
    "gCO₂e/kWh" => 679
    "gCO₂e/pkm" => 680
    "g_n" => 521
    "gal" => 67
    "gallon" => 67
    "gallons" => 67
    "gauss" => 375
    "gaz" => 579
    "gazes" => 579
    "gee" => 522
    "gerah" => 513
    "gerahs" => 513
    "gigaton" => 529
    "gigatons" => 529
    "gilbert" => 479
    "gilberts" => 479
    "gill" => 331
    "gills" => 331
    "gon" => 381
    "googol" => 494
    "googolplex" => 495
    "googolplexes" => 495
    "googols" => 494
    "gos" => 542
    "gr" => 288
    "grad" => 381
    "gradian" => 381
    "gradians" => 381
    "grain" => 288
    "grains" => 288
    "gram" => 33
    "grams" => 33
    "grams CO2e" => 678
    "grape jelly" => 434
    "grave" => 1
    "gray" => 24
    "grays" => 24
    "great gross" => 491
    "great_gross" => 491
    "grid carbon intensity" => 679
    "gross" => 490
    "gō" => 542
    "g₀" => 520
    "h" => 309
    "ha" => 73
    "halakim" => 515
    "half step" => 616
    "halfstep" => 616
    "hand" => 275
    "handbreadth" => 498
    "handbreadths" => 498
    "hands" => 275
    "hartley" => 458
    "hartleys" => 458
    "hartree" => 584
    "hartrees" => 584
    "hath" => 578
    "haths" => 578
    "heap" => 533
    "heaps" => 533
    "heat capacity" => 646
    "heat flux" => 650
    "heat_capacity" => 646
    "hectare" => 73
    "hectares" => 73
    "helek" => 515
    "henries" => 19
    "henry" => 19
    "henrys" => 19
    "hertz" => 7
    "hin" => 505
    "hins" => 505
    "hogshead" => 347
    "hogsheads" => 347
    "hole" => 534
    "holes" => 534
    "horsepower" => 373
    "hounsfield" => 702
    "hounsfield_unit" => 702
    "hour" => 309
    "hours" => 309
    "hp" => 373
    "imp gal" => 334
    "imperial bottle" => 356
    "imperial gallon" => 334
    "imperial gallons" => 334
    "imperial pint" => 603
    "imperial pints" => 603
    "imperial_pint" => 603
    "impgal" => 334
    "impulse" => 671
    "in" => 60
    "in H2O" => 631
    "in of water" => 631
    "inH2O" => 631
    "inHg" => 364
    "inch" => 60
    "inch of water" => 631
    "inches" => 60
    "inches of water" => 631
    "indian kos" => 580
    "instant" => 438
    "instants" => 438
    "instruction" => 449
    "instructions" => 449
    "inv_ab" => 475
    "inv_fb" => 474
    "inv_nb" => 477
    "inv_pb" => 476
    "inverse attobarn" => 475
    "inverse femtobarn" => 474
    "inverse nanobarn" => 477
    "inverse picobarn" => 476
    "io" => 456
    "io_op" => 456
    "io_ops" => 456
    "iops" => 753
    "ios" => 456
    "isaron" => 503
    "iso" => 614
    "issaron" => 503
    "iugera" => 569
    "iugerum" => 569
    "j" => 434
    "jam" => 434
    "janskies" => 466
    "jansky" => 466
    "janskys" => 466
    "japanese cup" => 602
    "japanese cups" => 602
    "japanese_cup" => 602
    "jelly" => 434
    "jerk" => 669
    "jeroboam" => 355
    "jeroboams" => 355
    "jiffies" => 439
    "jiffy" => 439
    "jigger" => 343
    "jiggers" => 343
    "jin" => 551
    "jins" => 551
    "jo" => 538
    "jos" => 538
    "joule" => 10
    "joules" => 10
    "joules per kelvin" => 102
    "joules per operation" => 674
    "joules per token" => 675
    "jubilee" => 518
    "jubilees" => 518
    "jugerum" => 569
    "julian year" => 321
    "julian years" => 321
    "julianyear" => 321
    "jupiter mass" => 400
    "jupitermass" => 400
    "kFLOPS" => 708
    "kHz" => 41
    "kJ" => 45
    "kPa" => 57
    "kV" => 55
    "kW" => 48
    "kWh" => 51
    "kab" => 509
    "kabim" => 509
    "kabs" => 509
    "kanme" => 544
    "kanmes" => 544
    "kat" => 26
    "kat/m³" => 663
    "katal" => 26
    "katals" => 26
    "kayser" => 484
    "kaysers" => 484
    "kcal" => 109
    "kelvin" => 4
    "kelvin difference" => 262
    "kflops" => 707
    "kg" => 1
    "kg CO2e" => 677
    "kg/m" => 657
    "kg/m²" => 658
    "kg/m³" => 642
    "kg/s" => 645
    "kgCO₂e" => 677
    "kgf" => 367
    "kg·m/s" => 670
    "khet" => 576
    "khets" => 576
    "kikar" => 512
    "kilderkin" => 351
    "kilderkins" => 351
    "kilocalorie" => 109
    "kilocalories" => 109
    "kilogram" => 1
    "kilogram force" => 367
    "kilogram-force" => 367
    "kilograms" => 1
    "kilograms CO2e" => 677
    "kilograms per cubic meter" => 642
    "kilograms per second" => 645
    "kiloton" => 527
    "kilotons" => 527
    "kilowarhol" => 419
    "kilowarhols" => 419
    "kilowatt hour" => 51
    "kilowatt hours" => 51
    "kilowatt-hour" => 51
    "kilowatt-hours" => 51
    "km" => 27
    "km/h" => 81
    "km²" => 72
    "kn" => 281
    "knot" => 281
    "knots" => 281
    "koku" => 541
    "kokus" => 541
    "kor" => 508
    "korim" => 508
    "kors" => 508
    "kos" => 580
    "kos_indian" => 580
    "kph" => 282
    "kt" => 281
    "ktok/s" => 738
    "l" => 329
    "l/100km" => 525
    "lambert" => 426
    "lamberts" => 426
    "lb" => 65
    "lbf" => 366
    "lbs" => 119
    "league" => 276
    "leagues" => 276
    "li_cn" => 549
    "liang" => 552
    "liangs" => 552
    "libra romana" => 570
    "libra_roma" => 570
    "lieue de poste" => 565
    "lieue_de_poste" => 565
    "lieues de poste" => 565
    "light hour" => 286
    "light hours" => 286
    "light minute" => 285
    "light minutes" => 285
    "light nanosecond" => 640
    "light second" => 284
    "light seconds" => 284
    "light year" => 115
    "light years" => 115
    "light-nanosecond" => 640
    "light_nanosecond" => 640
    "lighthour" => 286
    "lighthours" => 286
    "lightminute" => 285
    "lightminutes" => 285
    "lightsecond" => 284
    "lightseconds" => 284
    "lightyear" => 115
    "lightyears" => 115
    "linear density" => 657
    "link" => 622
    "link_chain" => 622
    "links" => 622
    "liter" => 78
    "liters" => 78
    "liters per 100 km" => 525
    "liters per minute" => 644
    "litre" => 78
    "litres" => 78
    "litres per minute" => 644
    "lm" => 21
    "lm·s" => 666
    "long ton" => 295
    "long tons" => 295
    "lumen" => 21
    "lumens" => 21
    "luminous energy" => 666
    "luminous exposure" => 665
    "lunar month" => 323
    "lunar months" => 323
    "lunarmonth" => 323
    "lustra" => 324
    "lustrum" => 324
    "lustrums" => 324
    "lux" => 22
    "lx" => 22
    "lx·s" => 665
    "ly" => 115
    "m" => 0
    "m H2O" => 630
    "m of water" => 630
    "m/s" => 80
    "m/s²" => 83
    "m/s³" => 669
    "mA" => 53
    "mH2O" => 630
    "mL" => 79
    "m_e" => 591
    "m_n" => 593
    "m_p" => 592
    "m_μ" => 594
    "mac" => 448
    "mach" => 283
    "mach_air_20C" => 692
    "macs" => 448
    "mag" => 467
    "magnitude" => 467
    "magnitudes" => 467
    "magnum" => 354
    "magnums" => 354
    "maneh" => 511
    "mass density" => 642
    "mass flow" => 645
    "maund" => 583
    "maunds" => 583
    "maxwell" => 422
    "maxwells" => 422
    "mbar" => 112
    "megaton" => 528
    "megatons" => 528
    "melchizedek" => 358
    "melchizedeks" => 358
    "meter" => 0
    "meter of water" => 630
    "meters" => 0
    "meters of water" => 630
    "methuselah" => 356
    "methuselahs" => 356
    "metric cup" => 599
    "metric cups" => 599
    "metric tablespoon" => 600
    "metric tablespoons" => 600
    "metric tbsp" => 600
    "metric ton" => 36
    "metric tons" => 36
    "metric_cup" => 599
    "metric_tbsp" => 600
    "mg" => 34
    "mg/dL glucose" => 690
    "mg/dL_glucose" => 690
    "mho" => 16
    "mi" => 63
    "mi/h" => 122
    "mickey" => 638
    "mickeys" => 638
    "microlife" => 483
    "microlives" => 483
    "micromort" => 482
    "micromorts" => 482
    "mil" => 383
    "mile" => 63
    "mile per hour" => 82
    "miles" => 63
    "miles per gallon" => 523
    "miles per gallon equivalent" => 524
    "miles per hour" => 82
    "mill_finance" => 620
    "mille passuum" => 568
    "mille_passuum" => 568
    "millennia" => 315
    "millennium" => 315
    "millenniums" => 315
    "millihelen" => 423
    "millihelens" => 423
    "mils" => 383
    "min" => 308
    "mina" => 511
    "minas" => 511
    "minute" => 308
    "minutes" => 308
    "mm" => 29
    "mmHg" => 363
    "mmol/L glucose" => 691
    "mmol/L_glucose" => 691
    "mo" => 312
    "mohs" => 485
    "mol" => 5
    "mol/mol" => 662
    "molal" => 756
    "molar" => 755
    "mole" => 5
    "mole fraction" => 662
    "moles" => 5
    "moment" => 440
    "moment magnitude" => 699
    "moment_magnitude" => 699
    "moments" => 440
    "momentum" => 670
    "momme" => 543
    "mommes" => 543
    "month" => 312
    "months" => 312
    "moon mass" => 401
    "moonmass" => 401
    "mpg" => 523
    "mpge" => 524
    "mph" => 82
    "ms" => 37
    "mu" => 550
    "muB" => 481
    "muon mass" => 594
    "muon_mass" => 594
    "mus" => 550
    "m²" => 70
    "m³" => 76
    "m³/(kg·s²)" => 100
    "m³/s" => 643
    "mₚₗ" => 299
    "nail_cloth" => 628
    "nanobarn" => 473
    "nanobarns" => 473
    "nat" => 457
    "nats" => 457
    "nautical mile" => 114
    "nautical miles" => 114
    "nb-1" => 477
    "nb^-1" => 477
    "nbarn" => 473
    "nb⁻¹" => 477
    "nebuchadnezzar" => 357
    "nebuchadnezzars" => 357
    "neutron mass" => 593
    "neutron_mass" => 593
    "newton" => 8
    "newtons" => 8
    "newtons per meter" => 656
    "nibble" => 387
    "nibbles" => 387
    "nit" => 424
    "nits" => 424
    "nm" => 31
    "nmi" => 114
    "ns" => 39
    "o" => 388
    "octave" => 618
    "octaves" => 618
    "octet" => 388
    "octets" => 388
    "oersted" => 478
    "oersteds" => 478
    "ohm" => 15
    "ohm meter" => 653
    "ohms" => 15
    "oil barrel" => 530
    "oil barrels" => 530
    "oil_barrel" => 530
    "omer" => 503
    "omers" => 503
    "onah" => 517
    "onot" => 517
    "op" => 447
    "ops" => 447
    "ops_per_s" => 723
    "ounce" => 64
    "ounces" => 64
    "outhouse" => 410
    "oz" => 64
    "ozt" => 304
    "packet" => 455
    "packets" => 455
    "page" => 609
    "pages" => 609
    "paragraph" => 607
    "paragraphs" => 607
    "parsa" => 501
    "parsec" => 117
    "parsecs" => 117
    "parts per billion" => 461
    "parts per hundred million" => 463
    "parts per million" => 460
    "parts per trillion" => 462
    "parts-per-billion" => 461
    "parts-per-million" => 460
    "parts-per-trillion" => 462
    "pascal" => 9
    "pascals" => 9
    "passus" => 567
    "passuses" => 567
    "pb" => 433
    "pb-1" => 476
    "pb^-1" => 476
    "pbarn" => 472
    "pb⁻¹" => 476
    "pc" => 117
    "peanut butter" => 433
    "peanutbutter" => 433
    "peck" => 336
    "pecks" => 336
    "pedes" => 566
    "pennyweight" => 305
    "pennyweights" => 305
    "perch" => 624
    "perches" => 624
    "person hour" => 687
    "person hours" => 687
    "person_hour" => 687
    "pes" => 566
    "petabyte" => 94
    "petabytes" => 94
    "petroleum barrel" => 530
    "petroleum_barrel" => 530
    "phon" => 465
    "phons" => 465
    "pica" => 405
    "picas" => 405
    "piccolo" => 352
    "picobarn" => 472
    "picobarns" => 472
    "pied" => 561
    "pied du roi" => 561
    "pieds" => 561
    "pieds du roi" => 561
    "pieze" => 633
    "pinch" => 341
    "pinches" => 341
    "pint" => 69
    "pints" => 69
    "pip" => 621
    "pipe" => 349
    "pipes" => 349
    "pips" => 621
    "pixel" => 681
    "pixels" => 681
    "pk" => 336
    "planck length" => 287
    "planck mass" => 299
    "planck time" => 326
    "pm" => 32
    "point" => 404
    "points" => 404
    "poise" => 394
    "pouce" => 562
    "pouces" => 562
    "pound" => 65
    "pound force" => 366
    "pound-force" => 366
    "pounds" => 65
    "ppb" => 461
    "pphm" => 463
    "ppm" => 460
    "pps" => 751
    "ppt" => 462
    "proton mass" => 592
    "proton_mass" => 592
    "ps" => 40
    "psi" => 361
    "pt" => 69
    "pud" => 558
    "puds" => 558
    "puncheon" => 348
    "puncheons" => 348
    "px" => 681
    "qps" => 745
    "qquad" => 432
    "qr" => 291
    "qt" => 68
    "quad" => 430
    "quality adjusted life year" => 688
    "quality-adjusted life year" => 688
    "quart" => 68
    "quarter" => 291
    "quarters" => 291
    "quarts" => 68
    "queries" => 452
    "query" => 452
    "quintal" => 307
    "quintals" => 307
    "qword" => 606
    "qwords" => 606
    "rack unit" => 277
    "rack units" => 277
    "rad" => 84
    "rad/s" => 667
    "rad/s²" => 668
    "radian" => 84
    "radians" => 84
    "rankine" => 256
    "rankine difference" => 265
    "rbe" => 701
    "rd" => 421
    "reaumur" => 259
    "rega" => 516
    "regaim" => 516
    "rehoboam" => 355
    "relative biological effectiveness" => 701
    "rem" => 377
    "rem_css" => 684
    "rems" => 377
    "request" => 453
    "requests" => 453
    "resistivity" => 653
    "rev" => 443
    "revolution" => 443
    "revolutions" => 443
    "revolutions per minute" => 420
    "revs" => 443
    "ri" => 537
    "richter" => 698
    "richter scale" => 698
    "rockwell" => 487
    "rod" => 272
    "rods" => 272
    "roman libra" => 570
    "roman mile" => 568
    "roman uncia" => 571
    "romer" => 260
    "rope" => 623
    "ropes" => 623
    "rot" => 445
    "rotation" => 445
    "rotations" => 445
    "rotations per minute" => 420
    "royal cubit" => 573
    "royal cubits" => 573
    "royal_cubit" => 573
    "rpm" => 420
    "rps" => 747
    "rundlet" => 345
    "rundlets" => 345
    "russian funt" => 559
    "russian_funt" => 559
    "rutherford" => 421
    "rutherfords" => 421
    "rydberg" => 585
    "rydberg_unit" => 585
    "rydbergs" => 585
    "réaumur" => 259
    "rømer" => 260
    "s" => 2
    "sabbath day's journey" => 502
    "sabbatical" => 519
    "saffir simpson" => 695
    "saffir_simpson" => 695
    "sagan" => 639
    "sagans" => 639
    "sample" => 441
    "samples" => 441
    "savart" => 617
    "savarts" => 617
    "sazhen" => 556
    "sazhens" => 556
    "sb" => 425
    "score" => 492
    "scores" => 492
    "scruple" => 300
    "scruples" => 300
    "seah" => 507
    "seahs" => 507
    "second" => 2
    "seconds" => 2
    "sector" => 608
    "sectors" => 608
    "seer" => 582
    "seers" => 582
    "seim" => 507
    "semitone" => 616
    "semitones" => 616
    "shaftment" => 626
    "shaftments" => 626
    "shake" => 318
    "shakes" => 318
    "shaku" => 535
    "shakus" => 535
    "shed" => 411
    "shekalim" => 510
    "shekel" => 510
    "shekels" => 510
    "shmita" => 519
    "shmitas" => 519
    "shmitta" => 519
    "short ton" => 294
    "short tons" => 294
    "sidereal day" => 322
    "sidereal days" => 322
    "sidereal year" => 319
    "sidereal years" => 319
    "siderealday" => 322
    "siderealyear" => 319
    "siemens" => 16
    "siemens per meter" => 654
    "sievert" => 25
    "sieverts" => 25
    "sk" => 429
    "skot" => 429
    "skots" => 429
    "slug" => 298
    "slugs" => 298
    "smidgen" => 342
    "smidgens" => 342
    "smoot" => 274
    "smoots" => 274
    "solar mass" => 398
    "solar radius" => 402
    "solarmass" => 398
    "solarradius" => 402
    "sone" => 464
    "sones" => 464
    "span" => 497
    "spans" => 497
    "specific energy" => 661
    "specific heat capacity" => 648
    "specific_energy" => 661
    "spectral efficiency" => 673
    "split" => 352
    "splits" => 352
    "sq ft" => 120
    "sqft" => 120
    "sqm" => 121
    "square feet" => 120
    "square foot" => 120
    "sr" => 86
    "st" => 290
    "standard gravity" => 520
    "steradian" => 86
    "steradians" => 86
    "stere" => 413
    "stick" => 526
    "stick of butter" => 526
    "sticks" => 526
    "sticks of butter" => 526
    "stilb" => 425
    "stilbs" => 425
    "stokes" => 396
    "stone" => 290
    "stones" => 290
    "stop" => 612
    "stops" => 612
    "story point" => 689
    "story points" => 689
    "story_point" => 689
    "stère" => 413
    "stères" => 413
    "sun" => 536
    "suns" => 536
    "surface tension" => 656
    "synodic month" => 323
    "synodic months" => 323
    "t" => 36
    "tablespoon" => 337
    "tablespoons" => 337
    "talent" => 512
    "talents" => 512
    "talmudic mil" => 500
    "talmudic_mil" => 500
    "tatami" => 540
    "tatamis" => 540
    "tbsp" => 337
    "tce" => 532
    "teaspoon" => 338
    "teaspoons" => 338
    "techum" => 502
    "techum shabbat" => 502
    "tefach" => 498
    "tefachim" => 498
    "tenth cent" => 620
    "tenth_cent" => 620
    "tertian" => 348
    "tesla" => 18
    "teslas" => 18
    "tex" => 635
    "texpt" => 406
    "therm" => 370
    "thermal conductivity" => 649
    "therms" => 370
    "tick" => 442
    "ticks" => 442
    "tierce" => 346
    "tierces" => 346
    "tn" => 294
    "toise" => 563
    "toises" => 563
    "tok" => 450
    "tok/s" => 737
    "token" => 450
    "tokens" => 450
    "tola" => 581
    "tolas" => 581
    "ton" => 294
    "tonne" => 36
    "tonne of coal equivalent" => 532
    "tonnes" => 36
    "tons" => 294
    "torque" => 672
    "torr" => 362
    "torrs" => 362
    "tps" => 749
    "transaction" => 454
    "transactions" => 454
    "transfer" => 451
    "transfers" => 451
    "transport carbon intensity" => 680
    "tropical year" => 320
    "tropical years" => 320
    "tropicalyear" => 320
    "troy ounce" => 304
    "troy ounces" => 304
    "troyounce" => 304
    "tsp" => 338
    "tsubo" => 539
    "tsubos" => 539
    "tun" => 350
    "tuns" => 350
    "turn" => 382
    "turns" => 382
    "txn" => 454
    "tₚ" => 326
    "u" => 297
    "uncia_roma" => 571
    "vershok" => 557
    "vershoks" => 557
    "verst" => 554
    "versts" => 554
    "vh" => 686
    "vickers" => 486
    "viewport height" => 686
    "viewport width" => 685
    "volt" => 13
    "volts" => 13
    "volts per meter" => 651
    "volumetric flow" => 643
    "vw" => 685
    "warhol" => 418
    "warhols" => 418
    "water horsepower" => 597
    "water_horsepower" => 597
    "watt" => 11
    "watts" => 11
    "watts per square meter" => 650
    "wavenumber" => 484
    "weber" => 17
    "webers" => 17
    "wedgwood" => 261
    "week" => 311
    "weeks" => 311
    "wk" => 311
    "yard" => 62
    "yards" => 62
    "yd" => 62
    "year" => 313
    "years" => 313
    "yovel" => 518
    "yovels" => 518
    "yr" => 313
    "zeret" => 497
    "zhang" => 548
    "zhangs" => 548
    "°" => 85
    "°C" => 20
    "°De" => 257
    "°F" => 87
    "°N" => 258
    "°R" => 256
    "°Ra" => 256
    "°Re" => 259
    "°Ré" => 259
    "°Rø" => 260
    "°W" => 261
    "°r" => 259
    "µA" => 54
    "µg" => 35
    "µm" => 30
    "µs" => 38
    "Å" => 278
    "ångström" => 278
    "ɡ" => 520
    "ʒ" => 301
    "ΔK" => 262
    "Δ°C" => 263
    "Δ°De" => 266
    "Δ°F" => 264
    "Δ°N" => 267
    "Δ°R" => 265
    "Δ°Ré" => 268
    "Δ°Rø" => 269
    "Δ°W" => 270
    "Ω" => 15
    "Ω·m" => 653
    "α" => 590
    "μ_B" => 481
    "μlife" => 483
    "μmort" => 482
    "℃" => 20
    "℈" => 300
    "℉" => 87
    "ℓₚ" => 287
    "℔" => 303
    "℥" => 302
    "℧" => 16
    "㍳" => 116
    => assign_custom_unit(ctx, unit, node)

# Compile-time-only dimension identity. Kept separate from unit ids: aliases
# and scaled units intentionally collapse to one physical signature.
-> lookup_unit_static_signature(raw_unit)
  unit = "" + raw_unit
  case unit
    "%" => "0,0,0,0,0,0,0,0,%:1"
    "1/mol" => "0,0,0,0,0,-1,0,0,"
    "A" => "0,0,0,1,0,0,0,0,"
    "A/m²" => "-2,0,0,1,0,0,0,0,"
    "AU tbsp" => "3,0,0,0,0,0,0,0,"
    "Apgar" => "0,0,0,0,0,0,0,0,apgar:1"
    "B" => "0,0,0,0,0,0,0,1,"
    "B/flop" => "0,0,0,0,0,0,0,1,flop:-1"
    "BOE" => "2,1,-2,0,0,0,0,0,"
    "BPM" => "0,0,-1,0,0,0,0,0,beat:1"
    "BTU" => "2,1,-2,0,0,0,0,0,"
    "Ba" => "-1,1,-2,0,0,0,0,0,"
    "Beaufort" => "0,0,0,0,0,0,0,0,beaufort:1"
    "Bortle" => "0,0,0,0,0,0,0,0,bortle:1"
    "Bps" => "0,0,-1,0,0,0,0,1,"
    "Bq" => "0,0,-1,0,0,0,0,0,decay:1"
    "C" => "0,0,1,1,0,0,0,0,"
    "C/m³" => "-3,0,1,1,0,0,0,0,"
    "CWT" => "0,1,0,0,0,0,0,0,"
    "Ci" => "0,0,-1,0,0,0,0,0,decay:1"
    "D" => "1,0,1,1,0,0,0,0,"
    "DMIPS" => "0,0,-1,0,0,0,0,0,instruction:1"
    "DWORD" => "0,0,0,0,0,0,0,1,"
    "Da" => "0,1,0,0,0,0,0,0,"
    "EF" => "0,0,0,0,0,0,0,0,ef:1"
    "EF-scale" => "0,0,0,0,0,0,0,0,ef:1"
    "EFLOPS" => "0,0,-1,0,0,0,0,0,flop:1"
    "EOPS" => "0,0,-1,0,0,0,0,0,op:1"
    "EV" => "0,0,0,0,0,0,0,0,exposure_value:1"
    "Eflops" => "0,0,-1,0,0,0,0,0,flop:1"
    "Eh" => "2,1,-2,0,0,0,0,0,"
    "EiB" => "0,0,0,0,0,0,0,1,"
    "F" => "-2,-1,4,2,0,0,0,0,"
    "F-scale" => "0,0,0,0,0,0,0,0,fujita:1"
    "F/m" => "-3,-1,4,2,0,0,0,0,"
    "FLOPS" => "0,0,-1,0,0,0,0,0,flop:1"
    "FPS" => "0,0,-1,0,0,0,0,0,frame:1"
    "Fr_catheter" => "1,0,0,0,0,0,0,0,"
    "GB" => "0,0,0,0,0,0,0,1,"
    "GFLOPS" => "0,0,-1,0,0,0,0,0,flop:1"
    "GHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "GIPS" => "0,0,-1,0,0,0,0,0,instruction:1"
    "GJ" => "2,1,-2,0,0,0,0,0,"
    "GMAC/s" => "0,0,-1,0,0,0,0,0,mac:1"
    "GOPS" => "0,0,-1,0,0,0,0,0,op:1"
    "GPa" => "-1,1,-2,0,0,0,0,0,"
    "GT/s" => "0,0,-1,0,0,0,0,0,transfer:1"
    "GW" => "2,1,-3,0,0,0,0,0,"
    "Ga" => "0,1,-2,-1,0,0,0,0,"
    "Gal" => "1,0,-2,0,0,0,0,0,"
    "Gb" => "0,0,0,1,0,0,0,0,"
    "Gflops" => "0,0,-1,0,0,0,0,0,flop:1"
    "GiB" => "0,0,0,0,0,0,0,1,"
    "Gtok/s" => "0,0,-1,0,0,0,0,0,token:1"
    "Gy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "H" => "2,1,-2,-2,0,0,0,0,"
    "HB" => "0,0,0,0,0,0,0,0,hardness_brinell:1"
    "HRC" => "0,0,0,0,0,0,0,0,hardness_rockwell:1"
    "HU" => "0,0,0,0,0,0,0,0,hounsfield:1"
    "HV" => "0,0,0,0,0,0,0,0,hardness_vickers:1"
    "Hz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "IOPS" => "0,0,-1,0,0,0,0,0,io:1"
    "ISO" => "0,0,0,0,0,0,0,0,iso_sensitivity:1"
    "ISO sensitivity" => "0,0,0,0,0,0,0,0,iso_sensitivity:1"
    "ISO_speed" => "0,0,0,0,0,0,0,0,iso_sensitivity:1"
    "J" => "2,1,-2,0,0,0,0,0,"
    "J/(kg·K)" => "2,0,-2,0,-1,0,0,0,"
    "J/(mol·K)" => "2,1,-2,0,-1,-1,0,0,"
    "J/K" => "2,1,-2,0,-1,0,0,0,"
    "J/kg" => "2,0,-2,0,0,0,0,0,"
    "J/kg/K" => "2,0,-2,0,-1,0,0,0,"
    "J/m³" => "-1,1,-2,0,0,0,0,0,"
    "J/op" => "2,1,-2,0,0,0,0,0,op:-1"
    "J/tok" => "2,1,-2,0,0,0,0,0,token:-1"
    "Jy" => "0,0,0,0,0,0,0,0,spectral_flux_density:1"
    "J·s" => "2,1,-1,0,0,0,0,0,"
    "K" => "0,0,0,0,1,0,0,0,"
    "KB" => "0,0,0,0,0,0,0,1,"
    "KOPS" => "0,0,-1,0,0,0,0,0,op:1"
    "KiB" => "0,0,0,0,0,0,0,1,"
    "L" => "3,0,0,0,0,0,0,0,"
    "L per 100 km" => "2,0,0,0,0,0,0,0,"
    "L/100km" => "2,0,0,0,0,0,0,0,"
    "L/min" => "3,0,-1,0,0,0,0,0,"
    "LT" => "0,1,0,0,0,0,0,0,"
    "La" => "-2,0,0,0,0,0,1,0,luminance:1"
    "MAC/s" => "0,0,-1,0,0,0,0,0,mac:1"
    "MB" => "0,0,0,0,0,0,0,1,"
    "MFLOPS" => "0,0,-1,0,0,0,0,0,flop:1"
    "MHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "MIPS" => "0,0,-1,0,0,0,0,0,instruction:1"
    "MJ" => "2,1,-2,0,0,0,0,0,"
    "MMAC/s" => "0,0,-1,0,0,0,0,0,mac:1"
    "MOPS" => "0,0,-1,0,0,0,0,0,op:1"
    "MPG" => "-2,0,0,0,0,0,0,0,"
    "MPGe" => "-2,0,0,0,0,0,0,0,"
    "MPa" => "-1,1,-2,0,0,0,0,0,"
    "MT/s" => "0,0,-1,0,0,0,0,0,transfer:1"
    "MV" => "2,1,-3,-1,0,0,0,0,"
    "MW" => "2,1,-3,0,0,0,0,0,"
    "MWh" => "2,1,-2,0,0,0,0,0,"
    "M_bol" => "0,0,0,0,0,0,0,0,magnitude_bolometric:1"
    "Mach at 20 C" => "1,0,-1,0,0,0,0,0,"
    "Mach in air at 20 C" => "1,0,-1,0,0,0,0,0,"
    "Mag" => "0,0,0,0,0,0,0,0,magnitude_absolute:1"
    "Mbol" => "0,0,0,0,0,0,0,0,magnitude_bolometric:1"
    "Mflops" => "0,0,-1,0,0,0,0,0,flop:1"
    "MiB" => "0,0,0,0,0,0,0,1,"
    "Mohs" => "0,0,0,0,0,0,0,0,hardness_mohs:1"
    "Mtok/s" => "0,0,-1,0,0,0,0,0,token:1"
    "Mw" => "0,0,0,0,0,0,0,0,magnitude:1"
    "Mx" => "2,1,-2,-1,0,0,0,0,"
    "M⊕" => "0,1,0,0,0,0,0,0,"
    "M☉" => "0,1,0,0,0,0,0,0,"
    "M☽" => "0,1,0,0,0,0,0,0,"
    "M♃" => "0,1,0,0,0,0,0,0,"
    "N" => "1,1,-2,0,0,0,0,0,"
    "N/A²" => "1,1,-2,-2,0,0,0,0,"
    "N/m" => "0,1,-2,0,0,0,0,0,"
    "N·m" => "2,1,-2,0,0,0,0,0,torque:1"
    "N·s" => "1,1,-1,0,0,0,0,0,impulse:1"
    "Oe" => "-1,0,0,1,0,0,0,0,"
    "P" => "-1,1,-1,0,0,0,0,0,"
    "PB" => "0,0,0,0,0,0,0,1,"
    "PFLOPS" => "0,0,-1,0,0,0,0,0,flop:1"
    "POPS" => "0,0,-1,0,0,0,0,0,op:1"
    "PPS" => "0,0,-1,0,0,0,0,0,packet:1"
    "PS" => "2,1,-3,0,0,0,0,0,"
    "Pa" => "-1,1,-2,0,0,0,0,0,"
    "Pflops" => "0,0,-1,0,0,0,0,0,flop:1"
    "PiB" => "0,0,0,0,0,0,0,1,"
    "Planck length" => "1,0,0,0,0,0,0,0,"
    "Planck mass" => "0,1,0,0,0,0,0,0,"
    "Planck time" => "0,0,1,0,0,0,0,0,"
    "QALY" => "0,0,1,0,0,0,0,0,quality_adjusted_life:1"
    "QALYs" => "0,0,1,0,0,0,0,0,quality_adjusted_life:1"
    "QPS" => "0,0,-1,0,0,0,0,0,query:1"
    "QWORD" => "0,0,0,0,0,0,0,1,"
    "RBE" => "0,0,0,0,0,0,0,0,rbe:1"
    "RPS" => "0,0,-1,0,0,0,0,0,request:1"
    "RU" => "1,0,0,0,0,0,0,0,"
    "Richter" => "0,0,0,0,0,0,0,0,magnitude:1"
    "Ry" => "2,1,-2,0,0,0,0,0,"
    "R⊕" => "1,0,0,0,0,0,0,0,"
    "R☉" => "1,0,0,0,0,0,0,0,"
    "S" => "-2,-1,3,2,0,0,0,0,"
    "S/m" => "-3,-1,3,2,0,0,0,0,"
    "SS_category" => "0,0,0,0,0,0,0,0,saffir_simpson:1"
    "Saffir-Simpson" => "0,0,0,0,0,0,0,0,saffir_simpson:1"
    "St" => "2,0,-1,0,0,0,0,0,"
    "Sv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "T" => "0,1,-2,-1,0,0,0,0,"
    "T/s" => "0,0,-1,0,0,0,0,0,transfer:1"
    "TB" => "0,0,0,0,0,0,0,1,"
    "TCE" => "2,1,-2,0,0,0,0,0,"
    "TFLOPS" => "0,0,-1,0,0,0,0,0,flop:1"
    "THz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "TMAC/s" => "0,0,-1,0,0,0,0,0,mac:1"
    "TOPS" => "0,0,-1,0,0,0,0,0,op:1"
    "TPS" => "0,0,-1,0,0,0,0,0,transaction:1"
    "TT/s" => "0,0,-1,0,0,0,0,0,transfer:1"
    "Tflops" => "0,0,-1,0,0,0,0,0,flop:1"
    "TiB" => "0,0,0,0,0,0,0,1,"
    "Torr" => "-1,1,-2,0,0,0,0,0,"
    "V" => "2,1,-3,-1,0,0,0,0,"
    "V/m" => "1,1,-3,-1,0,0,0,0,"
    "W" => "2,1,-3,0,0,0,0,0,"
    "W/(m²·K⁴)" => "0,1,-3,0,-4,0,0,0,"
    "W/(m·K)" => "1,1,-3,0,-1,0,0,0,"
    "W/m/K" => "1,1,-3,0,-1,0,0,0,"
    "W/m²" => "0,1,-3,0,0,0,0,0,"
    "Wb" => "2,1,-2,-1,0,0,0,0,"
    "YFLOPS" => "0,0,-1,0,0,0,0,0,flop:1"
    "Yflops" => "0,0,-1,0,0,0,0,0,flop:1"
    "ZFLOPS" => "0,0,-1,0,0,0,0,0,flop:1"
    "Zflops" => "0,0,-1,0,0,0,0,0,flop:1"
    "a0" => "1,0,0,0,0,0,0,0,"
    "a_0" => "1,0,0,0,0,0,0,0,"
    "ab-1" => "-2,0,0,0,0,0,0,0,"
    "ab^-1" => "-2,0,0,0,0,0,0,0,"
    "abarn" => "2,0,0,0,0,0,0,0,"
    "abinv" => "-2,0,0,0,0,0,0,0,"
    "absolute magnitude" => "0,0,0,0,0,0,0,0,magnitude_absolute:1"
    "ab⁻¹" => "-2,0,0,0,0,0,0,0,"
    "ac" => "2,0,0,0,0,0,0,0,"
    "acre" => "2,0,0,0,0,0,0,0,"
    "acres" => "2,0,0,0,0,0,0,0,"
    "alpha" => "0,0,0,0,0,0,0,0,"
    "altuve" => "1,0,0,0,0,0,0,0,"
    "altuves" => "1,0,0,0,0,0,0,0,"
    "amah" => "1,0,0,0,0,0,0,0,"
    "amot" => "1,0,0,0,0,0,0,0,"
    "ampere" => "0,0,0,1,0,0,0,0,"
    "amperes" => "0,0,0,1,0,0,0,0,"
    "amperes per square meter" => "-2,0,0,1,0,0,0,0,"
    "amphora" => "3,0,0,0,0,0,0,0,"
    "amphorae" => "3,0,0,0,0,0,0,0,"
    "amphoras" => "3,0,0,0,0,0,0,0,"
    "angstrom" => "1,0,0,0,0,0,0,0,"
    "angstroms" => "1,0,0,0,0,0,0,0,"
    "angular acceleration" => "0,0,-2,0,0,0,0,0,angle:1"
    "angular velocity" => "0,0,-1,0,0,0,0,0,angle:1"
    "apgar" => "0,0,0,0,0,0,0,0,apgar:1"
    "apgar score" => "0,0,0,0,0,0,0,0,apgar:1"
    "apostilb" => "-2,0,0,0,0,0,1,0,luminance:1"
    "apostilbs" => "-2,0,0,0,0,0,1,0,luminance:1"
    "apparent magnitude" => "0,0,0,0,0,0,0,0,magnitude_apparent:1"
    "arcmin" => "0,0,0,0,0,0,0,0,angle:1"
    "arcsec" => "0,0,0,0,0,0,0,0,angle:1"
    "areal density" => "-2,1,0,0,0,0,0,0,"
    "aroura" => "2,0,0,0,0,0,0,0,"
    "arourae" => "2,0,0,0,0,0,0,0,"
    "arouras" => "2,0,0,0,0,0,0,0,"
    "arpent" => "2,0,0,0,0,0,0,0,"
    "arpents" => "2,0,0,0,0,0,0,0,"
    "arshin" => "1,0,0,0,0,0,0,0,"
    "arshins" => "1,0,0,0,0,0,0,0,"
    "asb" => "-2,0,0,0,0,0,1,0,luminance:1"
    "astronomical unit" => "1,0,0,0,0,0,0,0,"
    "astronomical units" => "1,0,0,0,0,0,0,0,"
    "at" => "-1,1,-2,0,0,0,0,0,"
    "atm" => "-1,1,-2,0,0,0,0,0,"
    "atmosphere" => "-1,1,-2,0,0,0,0,0,"
    "atmospheres" => "-1,1,-2,0,0,0,0,0,"
    "attobarn" => "2,0,0,0,0,0,0,0,"
    "attobarns" => "2,0,0,0,0,0,0,0,"
    "au" => "1,0,0,0,0,0,0,0,"
    "australian tablespoon" => "3,0,0,0,0,0,0,0,"
    "australian tablespoons" => "3,0,0,0,0,0,0,0,"
    "australian tbsp" => "3,0,0,0,0,0,0,0,"
    "australian_tbsp" => "3,0,0,0,0,0,0,0,"
    "b" => "0,0,0,0,0,0,0,1,"
    "baker's dozen" => "0,0,0,0,0,0,0,0,"
    "bakers dozen" => "0,0,0,0,0,0,0,0,"
    "bakers_dozen" => "0,0,0,0,0,0,0,0,"
    "ban" => "0,0,0,0,0,0,0,1,"
    "banana" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "banana for scale" => "1,0,0,0,0,0,0,0,"
    "banana_for_scale" => "1,0,0,0,0,0,0,0,"
    "bananas" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "bananas for scale" => "1,0,0,0,0,0,0,0,"
    "bar" => "-1,1,-2,0,0,0,0,0,"
    "barleycorn" => "1,0,0,0,0,0,0,0,"
    "barleycorns" => "1,0,0,0,0,0,0,0,"
    "barn" => "2,0,0,0,0,0,0,0,"
    "barn megaparsec" => "3,0,0,0,0,0,0,0,"
    "barn-megaparsec" => "3,0,0,0,0,0,0,0,"
    "barn-megaparsecs" => "3,0,0,0,0,0,0,0,"
    "barns" => "2,0,0,0,0,0,0,0,"
    "barrel" => "3,0,0,0,0,0,0,0,"
    "barrel of oil equivalent" => "2,1,-2,0,0,0,0,0,"
    "barrels" => "3,0,0,0,0,0,0,0,"
    "barye" => "-1,1,-2,0,0,0,0,0,"
    "basis point" => "0,0,0,0,0,0,0,0,"
    "basis points" => "0,0,0,0,0,0,0,0,"
    "basis_point" => "0,0,0,0,0,0,0,0,"
    "basis_points" => "0,0,0,0,0,0,0,0,"
    "bath" => "3,0,0,0,0,0,0,0,"
    "baths" => "3,0,0,0,0,0,0,0,"
    "baud" => "0,0,-1,0,0,0,0,1,"
    "beard second" => "1,0,0,0,0,0,0,0,"
    "beard seconds" => "1,0,0,0,0,0,0,0,"
    "beard-second" => "1,0,0,0,0,0,0,0,"
    "beard-seconds" => "1,0,0,0,0,0,0,0,"
    "beat" => "0,0,0,0,0,0,0,0,beat:1"
    "beats" => "0,0,0,0,0,0,0,0,beat:1"
    "beats per minute" => "0,0,-1,0,0,0,0,0,beat:1"
    "beaufort" => "0,0,0,0,0,0,0,0,beaufort:1"
    "becquerel" => "0,0,-1,0,0,0,0,0,decay:1"
    "becquerels" => "0,0,-1,0,0,0,0,0,decay:1"
    "beka" => "0,1,0,0,0,0,0,0,"
    "bekah" => "0,1,0,0,0,0,0,0,"
    "bekas" => "0,1,0,0,0,0,0,0,"
    "biblical talent" => "0,1,0,0,0,0,0,0,"
    "biblical_mil" => "1,0,0,0,0,0,0,0,"
    "biblical_mina" => "0,1,0,0,0,0,0,0,"
    "biblical_talent" => "0,1,0,0,0,0,0,0,"
    "billions and billions" => "0,0,0,0,0,0,0,0,"
    "bit" => "0,0,0,0,0,0,0,1,"
    "bit/(s·Hz)" => "0,0,0,0,0,0,0,1,spectral_efficiency:1"
    "bit/s/Hz" => "0,0,0,0,0,0,0,1,spectral_efficiency:1"
    "bits" => "0,0,0,0,0,0,0,1,"
    "bits per second per hertz" => "0,0,0,0,0,0,0,1,spectral_efficiency:1"
    "block" => "0,0,0,0,0,0,0,1,"
    "blocks" => "0,0,0,0,0,0,0,1,"
    "boe" => "2,1,-2,0,0,0,0,0,"
    "bohr magneton" => "2,0,0,1,0,0,0,0,"
    "bohr_magneton" => "2,0,0,1,0,0,0,0,"
    "bohr_radius" => "1,0,0,0,0,0,0,0,"
    "boiler horsepower" => "2,1,-3,0,0,0,0,0,"
    "boiler_horsepower" => "2,1,-3,0,0,0,0,0,"
    "bolometric magnitude" => "0,0,0,0,0,0,0,0,magnitude_bolometric:1"
    "bortle" => "0,0,0,0,0,0,0,0,bortle:1"
    "bottle" => "3,0,0,0,0,0,0,0,"
    "bottles" => "3,0,0,0,0,0,0,0,"
    "bp_finance" => "0,0,0,0,0,0,0,0,"
    "bpm" => "0,0,-1,0,0,0,0,0,beat:1"
    "bps" => "0,0,-1,0,0,0,0,1,"
    "brad" => "0,0,0,0,0,0,0,0,angle:1"
    "brads" => "0,0,0,0,0,0,0,0,angle:1"
    "brinell" => "0,0,0,0,0,0,0,0,hardness_brinell:1"
    "bu" => "3,0,0,0,0,0,0,0,"
    "bushel" => "3,0,0,0,0,0,0,0,"
    "bushels" => "3,0,0,0,0,0,0,0,"
    "butt" => "3,0,0,0,0,0,0,0,"
    "byte" => "0,0,0,0,0,0,0,1,"
    "bytes" => "0,0,0,0,0,0,0,1,"
    "bytes per flop" => "0,0,0,0,0,0,0,1,flop:-1"
    "cP" => "-1,1,-1,0,0,0,0,0,"
    "cSt" => "2,0,-1,0,0,0,0,0,"
    "cable" => "1,0,0,0,0,0,0,0,"
    "cable length" => "1,0,0,0,0,0,0,0,"
    "cable lengths" => "1,0,0,0,0,0,0,0,"
    "cable_length" => "1,0,0,0,0,0,0,0,"
    "cables" => "1,0,0,0,0,0,0,0,"
    "cal" => "2,1,-2,0,0,0,0,0,"
    "calorie" => "2,1,-2,0,0,0,0,0,"
    "calories" => "2,1,-2,0,0,0,0,0,"
    "candela" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "candela per square meter" => "-2,0,0,0,0,0,1,0,luminance:1"
    "candelas" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "carat" => "0,1,0,0,0,0,0,0,"
    "carats" => "0,1,0,0,0,0,0,0,"
    "catalytic activity concentration" => "-3,0,-1,0,0,1,0,0,"
    "cd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "cd/m²" => "-2,0,0,0,0,0,1,0,luminance:1"
    "celsius" => "0,0,0,0,1,0,0,0,"
    "celsius difference" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "cent" => "0,0,0,0,0,0,0,0,pitch:1"
    "cent_pitch" => "0,0,0,0,0,0,0,0,pitch:1"
    "centipoise" => "-1,1,-1,0,0,0,0,0,"
    "centistokes" => "2,0,-1,0,0,0,0,0,"
    "cents" => "0,0,0,0,0,0,0,0,pitch:1"
    "centuries" => "0,0,1,0,0,0,0,0,"
    "century" => "0,0,1,0,0,0,0,0,"
    "ch" => "1,0,0,0,0,0,0,0,"
    "chain" => "1,0,0,0,0,0,0,0,"
    "chains" => "1,0,0,0,0,0,0,0,"
    "charge density" => "-3,0,1,1,0,0,0,0,"
    "chelakim" => "0,0,1,0,0,0,0,0,"
    "chelek" => "0,0,1,0,0,0,0,0,"
    "chetvert" => "3,0,0,0,0,0,0,0,"
    "chetverts" => "3,0,0,0,0,0,0,0,"
    "chi" => "1,0,0,0,0,0,0,0,"
    "chinese dan" => "0,1,0,0,0,0,0,0,"
    "chinese li" => "1,0,0,0,0,0,0,0,"
    "chinese_dan" => "0,1,0,0,0,0,0,0,"
    "chinese_li" => "1,0,0,0,0,0,0,0,"
    "chis" => "1,0,0,0,0,0,0,0,"
    "cicero" => "1,0,0,0,0,0,0,0,"
    "cloth nail" => "1,0,0,0,0,0,0,0,"
    "cluster" => "0,0,0,0,0,0,0,1,"
    "clusters" => "0,0,0,0,0,0,0,1,"
    "cm" => "1,0,0,0,0,0,0,0,"
    "cm-1" => "-1,0,0,0,0,0,0,0,"
    "cmH2O" => "-1,1,-2,0,0,0,0,0,"
    "cm^-1" => "-1,0,0,0,0,0,0,0,"
    "cm²" => "2,0,0,0,0,0,0,0,"
    "cm³" => "3,0,0,0,0,0,0,0,"
    "cm⁻¹" => "-1,0,0,0,0,0,0,0,"
    "compton wavelength" => "1,0,0,0,0,0,0,0,"
    "compton wavelength electron" => "1,0,0,0,0,0,0,0,"
    "compton wavelength neutron" => "1,0,0,0,0,0,0,0,"
    "compton wavelength proton" => "1,0,0,0,0,0,0,0,"
    "compton_e" => "1,0,0,0,0,0,0,0,"
    "compton_n" => "1,0,0,0,0,0,0,0,"
    "compton_p" => "1,0,0,0,0,0,0,0,"
    "compton_wavelength" => "1,0,0,0,0,0,0,0,"
    "conductivity" => "-3,-1,3,2,0,0,0,0,"
    "cord" => "3,0,0,0,0,0,0,0,"
    "cords" => "3,0,0,0,0,0,0,0,"
    "coulomb" => "0,0,1,1,0,0,0,0,"
    "coulombs" => "0,0,1,1,0,0,0,0,"
    "coulombs per cubic meter" => "-3,0,1,1,0,0,0,0,"
    "crumb" => "0,0,0,0,0,0,0,1,"
    "crumbs" => "0,0,0,0,0,0,0,1,"
    "css rem" => "0,0,0,0,0,0,0,0,css_root_font_size:1"
    "ct" => "0,1,0,0,0,0,0,0,"
    "cubic meters per second" => "3,0,-1,0,0,0,0,0,"
    "cubit" => "1,0,0,0,0,0,0,0,"
    "cubits" => "1,0,0,0,0,0,0,0,"
    "cun" => "1,0,0,0,0,0,0,0,"
    "cuns" => "1,0,0,0,0,0,0,0,"
    "cup" => "3,0,0,0,0,0,0,0,"
    "cups" => "3,0,0,0,0,0,0,0,"
    "curie" => "0,0,-1,0,0,0,0,0,decay:1"
    "curies" => "0,0,-1,0,0,0,0,0,decay:1"
    "current density" => "-2,0,0,1,0,0,0,0,"
    "cwt" => "0,1,0,0,0,0,0,0,"
    "cyc" => "0,0,0,0,0,0,0,0,cycle:1"
    "cycle" => "0,0,0,0,0,0,0,0,cycle:1"
    "cycles" => "0,0,0,0,0,0,0,0,cycle:1"
    "d" => "0,0,1,0,0,0,0,0,"
    "dalton" => "0,1,0,0,0,0,0,0,"
    "daltons" => "0,1,0,0,0,0,0,0,"
    "dan_cn" => "0,1,0,0,0,0,0,0,"
    "dash" => "3,0,0,0,0,0,0,0,"
    "dashes" => "3,0,0,0,0,0,0,0,"
    "day" => "0,0,1,0,0,0,0,0,"
    "days" => "0,0,1,0,0,0,0,0,"
    "debye" => "1,0,1,1,0,0,0,0,"
    "debyes" => "1,0,1,1,0,0,0,0,"
    "decade" => "0,0,1,0,0,0,0,0,"
    "decades" => "0,0,1,0,0,0,0,0,"
    "decay" => "0,0,0,0,0,0,0,0,decay:1"
    "decays" => "0,0,0,0,0,0,0,0,decay:1"
    "deciban" => "0,0,0,0,0,0,0,1,"
    "decibans" => "0,0,0,0,0,0,0,1,"
    "decitex" => "0,0,0,0,0,0,0,0,linear_density:1"
    "deg" => "0,0,0,0,0,0,0,0,angle:1"
    "degree" => "0,0,0,0,0,0,0,0,angle:1"
    "degrees" => "0,0,0,0,0,0,0,0,angle:1"
    "delisle" => "0,0,0,0,1,0,0,0,"
    "delta celsius" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "delta fahrenheit" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "delta kelvin" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "delta rankine" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "denier" => "0,0,0,0,0,0,0,0,linear_density:1"
    "deniers" => "0,0,0,0,0,0,0,0,linear_density:1"
    "didot" => "1,0,0,0,0,0,0,0,"
    "digit" => "1,0,0,0,0,0,0,0,"
    "digits" => "1,0,0,0,0,0,0,0,"
    "dit" => "0,0,0,0,0,0,0,1,"
    "dits" => "0,0,0,0,0,0,0,1,"
    "dog year" => "0,0,1,0,0,0,0,0,"
    "dog years" => "0,0,1,0,0,0,0,0,"
    "dogyear" => "0,0,1,0,0,0,0,0,"
    "donkey power" => "2,1,-3,0,0,0,0,0,"
    "donkey-power" => "2,1,-3,0,0,0,0,0,"
    "donkeypower" => "2,1,-3,0,0,0,0,0,"
    "dots per inch" => "-1,0,0,0,0,0,0,0,"
    "dots per pixel" => "-1,0,0,0,0,0,0,0,"
    "dozen" => "0,0,0,0,0,0,0,0,"
    "dozens" => "0,0,0,0,0,0,0,0,"
    "dpi" => "-1,0,0,0,0,0,0,0,"
    "dppx" => "-1,0,0,0,0,0,0,0,"
    "dr" => "0,1,0,0,0,0,0,0,"
    "drachm" => "0,1,0,0,0,0,0,0,"
    "drams" => "0,1,0,0,0,0,0,0,"
    "drop" => "3,0,0,0,0,0,0,0,"
    "drops" => "3,0,0,0,0,0,0,0,"
    "dword" => "0,0,0,0,0,0,0,1,"
    "dwords" => "0,0,0,0,0,0,0,1,"
    "dwt" => "0,1,0,0,0,0,0,0,"
    "dyn" => "1,1,-2,0,0,0,0,0,"
    "dyne" => "1,1,-2,0,0,0,0,0,"
    "dynes" => "1,1,-2,0,0,0,0,0,"
    "eV" => "2,1,-2,0,0,0,0,0,"
    "earth mass" => "0,1,0,0,0,0,0,0,"
    "earth radius" => "1,0,0,0,0,0,0,0,"
    "earthmass" => "0,1,0,0,0,0,0,0,"
    "earthradius" => "1,0,0,0,0,0,0,0,"
    "egypt_palm" => "1,0,0,0,0,0,0,0,"
    "egyptian palm" => "1,0,0,0,0,0,0,0,"
    "egyptian palms" => "1,0,0,0,0,0,0,0,"
    "electric field" => "1,1,-3,-1,0,0,0,0,"
    "electric horsepower" => "2,1,-3,0,0,0,0,0,"
    "electric_horsepower" => "2,1,-3,0,0,0,0,0,"
    "electron mass" => "0,1,0,0,0,0,0,0,"
    "electron_mass" => "0,1,0,0,0,0,0,0,"
    "electronvolt" => "2,1,-2,0,0,0,0,0,"
    "electronvolts" => "2,1,-2,0,0,0,0,0,"
    "em" => "0,0,0,0,0,0,0,0,em:1"
    "en" => "0,0,0,0,0,0,0,0,em:1"
    "energy density" => "-1,1,-2,0,0,0,0,0,"
    "english cubit" => "1,0,0,0,0,0,0,0,"
    "english cubits" => "1,0,0,0,0,0,0,0,"
    "english_cubit" => "1,0,0,0,0,0,0,0,"
    "enhanced fujita" => "0,0,0,0,0,0,0,0,ef:1"
    "entropy" => "2,1,-2,0,-1,0,0,0,entropy:1"
    "ephah" => "3,0,0,0,0,0,0,0,"
    "ephahs" => "3,0,0,0,0,0,0,0,"
    "ephas" => "3,0,0,0,0,0,0,0,"
    "erg" => "2,1,-2,0,0,0,0,0,"
    "etzba" => "1,0,0,0,0,0,0,0,"
    "etzbaot" => "1,0,0,0,0,0,0,0,"
    "ev" => "0,0,0,0,0,0,0,0,exposure_value:1"
    "e₀" => "0,0,0,0,0,0,0,0,e₀:1"
    "f stop" => "0,0,0,0,0,0,0,0,f_stop:1"
    "f-stop" => "0,0,0,0,0,0,0,0,f_stop:1"
    "f-stops" => "0,0,0,0,0,0,0,0,f_stop:1"
    "fL" => "-2,0,0,0,0,0,1,0,luminance:1"
    "f_stop" => "0,0,0,0,0,0,0,0,f_stop:1"
    "fahrenheit" => "0,0,0,0,1,0,0,0,"
    "fahrenheit difference" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "farad" => "-2,-1,4,2,0,0,0,0,"
    "farads" => "-2,-1,4,2,0,0,0,0,"
    "fathom" => "1,0,0,0,0,0,0,0,"
    "fathoms" => "1,0,0,0,0,0,0,0,"
    "fb-1" => "-2,0,0,0,0,0,0,0,"
    "fb^-1" => "-2,0,0,0,0,0,0,0,"
    "fbarn" => "2,0,0,0,0,0,0,0,"
    "fbinv" => "-2,0,0,0,0,0,0,0,"
    "fb⁻¹" => "-2,0,0,0,0,0,0,0,"
    "feet" => "1,0,0,0,0,0,0,0,"
    "feet of water" => "-1,1,-2,0,0,0,0,0,"
    "femtobarn" => "2,0,0,0,0,0,0,0,"
    "femtobarns" => "2,0,0,0,0,0,0,0,"
    "fen" => "1,0,0,0,0,0,0,0,"
    "fens" => "1,0,0,0,0,0,0,0,"
    "fine structure constant" => "0,0,0,0,0,0,0,0,"
    "fine_structure" => "0,0,0,0,0,0,0,0,"
    "fingerbreadth" => "1,0,0,0,0,0,0,0,"
    "firkin" => "3,0,0,0,0,0,0,0,"
    "firkins" => "3,0,0,0,0,0,0,0,"
    "fl dr" => "3,0,0,0,0,0,0,0,"
    "fl oz" => "3,0,0,0,0,0,0,0,"
    "fldr" => "3,0,0,0,0,0,0,0,"
    "flop" => "0,0,0,0,0,0,0,0,flop:1"
    "flops" => "0,0,-1,0,0,0,0,0,flop:1"
    "flops_count" => "0,0,0,0,0,0,0,0,flop:1"
    "floz" => "3,0,0,0,0,0,0,0,"
    "fluid dram" => "3,0,0,0,0,0,0,0,"
    "fluid drams" => "3,0,0,0,0,0,0,0,"
    "fluid ounce" => "3,0,0,0,0,0,0,0,"
    "fluid ounces" => "3,0,0,0,0,0,0,0,"
    "foot" => "1,0,0,0,0,0,0,0,"
    "foot of water" => "-1,1,-2,0,0,0,0,0,"
    "foot pound" => "2,1,-2,0,0,0,0,0,"
    "foot pounds" => "2,1,-2,0,0,0,0,0,"
    "foot-lambert" => "-2,0,0,0,0,0,1,0,luminance:1"
    "foot-pound" => "2,1,-2,0,0,0,0,0,"
    "foot-pounds" => "2,1,-2,0,0,0,0,0,"
    "fortnight" => "0,0,1,0,0,0,0,0,"
    "fortnights" => "0,0,1,0,0,0,0,0,"
    "fps" => "0,0,-1,0,0,0,0,0,frame:1"
    "frame" => "0,0,0,0,0,0,0,0,frame:1"
    "frames" => "0,0,0,0,0,0,0,0,frame:1"
    "frames per second" => "0,0,-1,0,0,0,0,0,frame:1"
    "french gauge" => "1,0,0,0,0,0,0,0,"
    "french_gauge" => "1,0,0,0,0,0,0,0,"
    "fstop" => "0,0,0,0,0,0,0,0,f_stop:1"
    "ft" => "1,0,0,0,0,0,0,0,"
    "ft H2O" => "-1,1,-2,0,0,0,0,0,"
    "ft of water" => "-1,1,-2,0,0,0,0,0,"
    "ftH2O" => "-1,1,-2,0,0,0,0,0,"
    "ftlbf" => "2,1,-2,0,0,0,0,0,"
    "ft²" => "2,0,0,0,0,0,0,0,"
    "fujita" => "0,0,0,0,0,0,0,0,fujita:1"
    "fujita scale" => "0,0,0,0,0,0,0,0,fujita:1"
    "funt" => "0,1,0,0,0,0,0,0,"
    "funt_ru" => "0,1,0,0,0,0,0,0,"
    "fur" => "1,0,0,0,0,0,0,0,"
    "furlong" => "1,0,0,0,0,0,0,0,"
    "furlongs" => "1,0,0,0,0,0,0,0,"
    "g" => "0,1,0,0,0,0,0,0,"
    "g CO2e" => "0,1,0,0,0,0,0,0,co2e:1"
    "g0" => "1,0,-2,0,0,0,0,0,"
    "gCO₂e" => "0,1,0,0,0,0,0,0,co2e:1"
    "gCO₂e/kWh" => "-2,0,2,0,0,0,0,0,co2e:1"
    "gCO₂e/pkm" => "-1,1,0,0,0,0,0,0,transport_co2e:1"
    "g_n" => "1,0,-2,0,0,0,0,0,"
    "gal" => "3,0,0,0,0,0,0,0,"
    "gallon" => "3,0,0,0,0,0,0,0,"
    "gallons" => "3,0,0,0,0,0,0,0,"
    "gauss" => "0,1,-2,-1,0,0,0,0,"
    "gaz" => "1,0,0,0,0,0,0,0,"
    "gazes" => "1,0,0,0,0,0,0,0,"
    "gee" => "1,0,-2,0,0,0,0,0,"
    "gerah" => "0,1,0,0,0,0,0,0,"
    "gerahs" => "0,1,0,0,0,0,0,0,"
    "gigaton" => "0,1,0,0,0,0,0,0,"
    "gigatons" => "0,1,0,0,0,0,0,0,"
    "gilbert" => "0,0,0,1,0,0,0,0,"
    "gilberts" => "0,0,0,1,0,0,0,0,"
    "gill" => "3,0,0,0,0,0,0,0,"
    "gills" => "3,0,0,0,0,0,0,0,"
    "gon" => "0,0,0,0,0,0,0,0,angle:1"
    "googol" => "0,0,0,0,0,0,0,0,"
    "googolplex" => "0,0,0,0,0,0,0,0,"
    "googolplexes" => "0,0,0,0,0,0,0,0,"
    "googols" => "0,0,0,0,0,0,0,0,"
    "gos" => "3,0,0,0,0,0,0,0,"
    "gr" => "0,1,0,0,0,0,0,0,"
    "grad" => "0,0,0,0,0,0,0,0,angle:1"
    "gradian" => "0,0,0,0,0,0,0,0,angle:1"
    "gradians" => "0,0,0,0,0,0,0,0,angle:1"
    "grain" => "0,1,0,0,0,0,0,0,"
    "grains" => "0,1,0,0,0,0,0,0,"
    "gram" => "0,1,0,0,0,0,0,0,"
    "grams" => "0,1,0,0,0,0,0,0,"
    "grams CO2e" => "0,1,0,0,0,0,0,0,co2e:1"
    "grape jelly" => "0,0,0,0,0,0,0,0,jelly:1"
    "grave" => "0,1,0,0,0,0,0,0,"
    "gray" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "grays" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "great gross" => "0,0,0,0,0,0,0,0,"
    "great_gross" => "0,0,0,0,0,0,0,0,"
    "grid carbon intensity" => "-2,0,2,0,0,0,0,0,co2e:1"
    "gross" => "0,0,0,0,0,0,0,0,"
    "gō" => "3,0,0,0,0,0,0,0,"
    "g₀" => "1,0,-2,0,0,0,0,0,"
    "h" => "0,0,1,0,0,0,0,0,"
    "ha" => "2,0,0,0,0,0,0,0,"
    "halakim" => "0,0,1,0,0,0,0,0,"
    "half step" => "0,0,0,0,0,0,0,0,pitch:1"
    "halfstep" => "0,0,0,0,0,0,0,0,pitch:1"
    "hand" => "1,0,0,0,0,0,0,0,"
    "handbreadth" => "1,0,0,0,0,0,0,0,"
    "handbreadths" => "1,0,0,0,0,0,0,0,"
    "hands" => "1,0,0,0,0,0,0,0,"
    "hartley" => "0,0,0,0,0,0,0,1,"
    "hartleys" => "0,0,0,0,0,0,0,1,"
    "hartree" => "2,1,-2,0,0,0,0,0,"
    "hartrees" => "2,1,-2,0,0,0,0,0,"
    "hath" => "1,0,0,0,0,0,0,0,"
    "haths" => "1,0,0,0,0,0,0,0,"
    "heap" => "0,0,0,0,0,0,0,0,heap:1"
    "heaps" => "0,0,0,0,0,0,0,0,heap:1"
    "heat capacity" => "2,1,-2,0,-1,0,0,0,heat_capacity:1"
    "heat flux" => "0,1,-3,0,0,0,0,0,"
    "heat_capacity" => "2,1,-2,0,-1,0,0,0,heat_capacity:1"
    "hectare" => "2,0,0,0,0,0,0,0,"
    "hectares" => "2,0,0,0,0,0,0,0,"
    "helek" => "0,0,1,0,0,0,0,0,"
    "henries" => "2,1,-2,-2,0,0,0,0,"
    "henry" => "2,1,-2,-2,0,0,0,0,"
    "henrys" => "2,1,-2,-2,0,0,0,0,"
    "hertz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "hin" => "3,0,0,0,0,0,0,0,"
    "hins" => "3,0,0,0,0,0,0,0,"
    "hogshead" => "3,0,0,0,0,0,0,0,"
    "hogsheads" => "3,0,0,0,0,0,0,0,"
    "hole" => "0,0,0,0,0,0,0,0,hole:1"
    "holes" => "0,0,0,0,0,0,0,0,hole:1"
    "horsepower" => "2,1,-3,0,0,0,0,0,"
    "hounsfield" => "0,0,0,0,0,0,0,0,hounsfield:1"
    "hounsfield_unit" => "0,0,0,0,0,0,0,0,hounsfield:1"
    "hour" => "0,0,1,0,0,0,0,0,"
    "hours" => "0,0,1,0,0,0,0,0,"
    "hp" => "2,1,-3,0,0,0,0,0,"
    "imp gal" => "3,0,0,0,0,0,0,0,"
    "imperial bottle" => "3,0,0,0,0,0,0,0,"
    "imperial gallon" => "3,0,0,0,0,0,0,0,"
    "imperial gallons" => "3,0,0,0,0,0,0,0,"
    "imperial pint" => "3,0,0,0,0,0,0,0,"
    "imperial pints" => "3,0,0,0,0,0,0,0,"
    "imperial_pint" => "3,0,0,0,0,0,0,0,"
    "impgal" => "3,0,0,0,0,0,0,0,"
    "impulse" => "1,1,-1,0,0,0,0,0,impulse:1"
    "in" => "1,0,0,0,0,0,0,0,"
    "in H2O" => "-1,1,-2,0,0,0,0,0,"
    "in of water" => "-1,1,-2,0,0,0,0,0,"
    "inH2O" => "-1,1,-2,0,0,0,0,0,"
    "inHg" => "-1,1,-2,0,0,0,0,0,"
    "inch" => "1,0,0,0,0,0,0,0,"
    "inch of water" => "-1,1,-2,0,0,0,0,0,"
    "inches" => "1,0,0,0,0,0,0,0,"
    "inches of water" => "-1,1,-2,0,0,0,0,0,"
    "indian kos" => "1,0,0,0,0,0,0,0,"
    "instant" => "0,0,0,0,0,0,0,0,instant:1"
    "instants" => "0,0,0,0,0,0,0,0,instant:1"
    "instruction" => "0,0,0,0,0,0,0,0,instruction:1"
    "instructions" => "0,0,0,0,0,0,0,0,instruction:1"
    "inv_ab" => "-2,0,0,0,0,0,0,0,"
    "inv_fb" => "-2,0,0,0,0,0,0,0,"
    "inv_nb" => "-2,0,0,0,0,0,0,0,"
    "inv_pb" => "-2,0,0,0,0,0,0,0,"
    "inverse attobarn" => "-2,0,0,0,0,0,0,0,"
    "inverse femtobarn" => "-2,0,0,0,0,0,0,0,"
    "inverse nanobarn" => "-2,0,0,0,0,0,0,0,"
    "inverse picobarn" => "-2,0,0,0,0,0,0,0,"
    "io" => "0,0,0,0,0,0,0,0,io:1"
    "io_op" => "0,0,0,0,0,0,0,0,io:1"
    "io_ops" => "0,0,0,0,0,0,0,0,io:1"
    "iops" => "0,0,-1,0,0,0,0,0,io:1"
    "ios" => "0,0,0,0,0,0,0,0,io:1"
    "isaron" => "3,0,0,0,0,0,0,0,"
    "iso" => "0,0,0,0,0,0,0,0,iso_sensitivity:1"
    "issaron" => "3,0,0,0,0,0,0,0,"
    "iugera" => "2,0,0,0,0,0,0,0,"
    "iugerum" => "2,0,0,0,0,0,0,0,"
    "j" => "0,0,0,0,0,0,0,0,jelly:1"
    "jam" => "0,0,0,0,0,0,0,0,jelly:1"
    "janskies" => "0,0,0,0,0,0,0,0,spectral_flux_density:1"
    "jansky" => "0,0,0,0,0,0,0,0,spectral_flux_density:1"
    "janskys" => "0,0,0,0,0,0,0,0,spectral_flux_density:1"
    "japanese cup" => "3,0,0,0,0,0,0,0,"
    "japanese cups" => "3,0,0,0,0,0,0,0,"
    "japanese_cup" => "3,0,0,0,0,0,0,0,"
    "jelly" => "0,0,0,0,0,0,0,0,jelly:1"
    "jerk" => "1,0,-3,0,0,0,0,0,"
    "jeroboam" => "3,0,0,0,0,0,0,0,"
    "jeroboams" => "3,0,0,0,0,0,0,0,"
    "jiffies" => "0,0,0,0,0,0,0,0,jiffy:1"
    "jiffy" => "0,0,0,0,0,0,0,0,jiffy:1"
    "jigger" => "3,0,0,0,0,0,0,0,"
    "jiggers" => "3,0,0,0,0,0,0,0,"
    "jin" => "0,1,0,0,0,0,0,0,"
    "jins" => "0,1,0,0,0,0,0,0,"
    "jo" => "1,0,0,0,0,0,0,0,"
    "jos" => "1,0,0,0,0,0,0,0,"
    "joule" => "2,1,-2,0,0,0,0,0,"
    "joules" => "2,1,-2,0,0,0,0,0,"
    "joules per kelvin" => "2,1,-2,0,-1,0,0,0,"
    "joules per operation" => "2,1,-2,0,0,0,0,0,op:-1"
    "joules per token" => "2,1,-2,0,0,0,0,0,token:-1"
    "jubilee" => "0,0,1,0,0,0,0,0,"
    "jubilees" => "0,0,1,0,0,0,0,0,"
    "jugerum" => "2,0,0,0,0,0,0,0,"
    "julian year" => "0,0,1,0,0,0,0,0,"
    "julian years" => "0,0,1,0,0,0,0,0,"
    "julianyear" => "0,0,1,0,0,0,0,0,"
    "jupiter mass" => "0,1,0,0,0,0,0,0,"
    "jupitermass" => "0,1,0,0,0,0,0,0,"
    "kFLOPS" => "0,0,-1,0,0,0,0,0,flop:1"
    "kHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "kJ" => "2,1,-2,0,0,0,0,0,"
    "kPa" => "-1,1,-2,0,0,0,0,0,"
    "kV" => "2,1,-3,-1,0,0,0,0,"
    "kW" => "2,1,-3,0,0,0,0,0,"
    "kWh" => "2,1,-2,0,0,0,0,0,"
    "kab" => "3,0,0,0,0,0,0,0,"
    "kabim" => "3,0,0,0,0,0,0,0,"
    "kabs" => "3,0,0,0,0,0,0,0,"
    "kanme" => "0,1,0,0,0,0,0,0,"
    "kanmes" => "0,1,0,0,0,0,0,0,"
    "kat" => "0,0,-1,0,0,1,0,0,"
    "kat/m³" => "-3,0,-1,0,0,1,0,0,"
    "katal" => "0,0,-1,0,0,1,0,0,"
    "katals" => "0,0,-1,0,0,1,0,0,"
    "kayser" => "-1,0,0,0,0,0,0,0,"
    "kaysers" => "-1,0,0,0,0,0,0,0,"
    "kcal" => "2,1,-2,0,0,0,0,0,"
    "kelvin" => "0,0,0,0,1,0,0,0,"
    "kelvin difference" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "kflops" => "0,0,-1,0,0,0,0,0,flop:1"
    "kg" => "0,1,0,0,0,0,0,0,"
    "kg CO2e" => "0,1,0,0,0,0,0,0,co2e:1"
    "kg/m" => "-1,1,0,0,0,0,0,0,"
    "kg/m²" => "-2,1,0,0,0,0,0,0,"
    "kg/m³" => "-3,1,0,0,0,0,0,0,"
    "kg/s" => "0,1,-1,0,0,0,0,0,"
    "kgCO₂e" => "0,1,0,0,0,0,0,0,co2e:1"
    "kgf" => "1,1,-2,0,0,0,0,0,"
    "kg·m/s" => "1,1,-1,0,0,0,0,0,momentum:1"
    "khet" => "1,0,0,0,0,0,0,0,"
    "khets" => "1,0,0,0,0,0,0,0,"
    "kikar" => "0,1,0,0,0,0,0,0,"
    "kilderkin" => "3,0,0,0,0,0,0,0,"
    "kilderkins" => "3,0,0,0,0,0,0,0,"
    "kilocalorie" => "2,1,-2,0,0,0,0,0,"
    "kilocalories" => "2,1,-2,0,0,0,0,0,"
    "kilogram" => "0,1,0,0,0,0,0,0,"
    "kilogram force" => "1,1,-2,0,0,0,0,0,"
    "kilogram-force" => "1,1,-2,0,0,0,0,0,"
    "kilograms" => "0,1,0,0,0,0,0,0,"
    "kilograms CO2e" => "0,1,0,0,0,0,0,0,co2e:1"
    "kilograms per cubic meter" => "-3,1,0,0,0,0,0,0,"
    "kilograms per second" => "0,1,-1,0,0,0,0,0,"
    "kiloton" => "0,1,0,0,0,0,0,0,"
    "kilotons" => "0,1,0,0,0,0,0,0,"
    "kilowarhol" => "0,0,0,0,0,0,0,0,fame:1"
    "kilowarhols" => "0,0,0,0,0,0,0,0,fame:1"
    "kilowatt hour" => "2,1,-2,0,0,0,0,0,"
    "kilowatt hours" => "2,1,-2,0,0,0,0,0,"
    "kilowatt-hour" => "2,1,-2,0,0,0,0,0,"
    "kilowatt-hours" => "2,1,-2,0,0,0,0,0,"
    "km" => "1,0,0,0,0,0,0,0,"
    "km/h" => "1,0,-1,0,0,0,0,0,"
    "km²" => "2,0,0,0,0,0,0,0,"
    "kn" => "1,0,-1,0,0,0,0,0,"
    "knot" => "1,0,-1,0,0,0,0,0,"
    "knots" => "1,0,-1,0,0,0,0,0,"
    "koku" => "3,0,0,0,0,0,0,0,"
    "kokus" => "3,0,0,0,0,0,0,0,"
    "kor" => "3,0,0,0,0,0,0,0,"
    "korim" => "3,0,0,0,0,0,0,0,"
    "kors" => "3,0,0,0,0,0,0,0,"
    "kos" => "1,0,0,0,0,0,0,0,"
    "kos_indian" => "1,0,0,0,0,0,0,0,"
    "kph" => "1,0,-1,0,0,0,0,0,"
    "kt" => "1,0,-1,0,0,0,0,0,"
    "ktok/s" => "0,0,-1,0,0,0,0,0,token:1"
    "l" => "3,0,0,0,0,0,0,0,"
    "l/100km" => "2,0,0,0,0,0,0,0,"
    "lambert" => "-2,0,0,0,0,0,1,0,luminance:1"
    "lamberts" => "-2,0,0,0,0,0,1,0,luminance:1"
    "lb" => "0,1,0,0,0,0,0,0,"
    "lbf" => "1,1,-2,0,0,0,0,0,"
    "lbs" => "0,1,0,0,0,0,0,0,"
    "league" => "1,0,0,0,0,0,0,0,"
    "leagues" => "1,0,0,0,0,0,0,0,"
    "li_cn" => "1,0,0,0,0,0,0,0,"
    "liang" => "0,1,0,0,0,0,0,0,"
    "liangs" => "0,1,0,0,0,0,0,0,"
    "libra romana" => "0,1,0,0,0,0,0,0,"
    "libra_roma" => "0,1,0,0,0,0,0,0,"
    "lieue de poste" => "1,0,0,0,0,0,0,0,"
    "lieue_de_poste" => "1,0,0,0,0,0,0,0,"
    "lieues de poste" => "1,0,0,0,0,0,0,0,"
    "light hour" => "1,0,0,0,0,0,0,0,"
    "light hours" => "1,0,0,0,0,0,0,0,"
    "light minute" => "1,0,0,0,0,0,0,0,"
    "light minutes" => "1,0,0,0,0,0,0,0,"
    "light nanosecond" => "1,0,0,0,0,0,0,0,"
    "light second" => "1,0,0,0,0,0,0,0,"
    "light seconds" => "1,0,0,0,0,0,0,0,"
    "light year" => "1,0,0,0,0,0,0,0,"
    "light years" => "1,0,0,0,0,0,0,0,"
    "light-nanosecond" => "1,0,0,0,0,0,0,0,"
    "light_nanosecond" => "1,0,0,0,0,0,0,0,"
    "lighthour" => "1,0,0,0,0,0,0,0,"
    "lighthours" => "1,0,0,0,0,0,0,0,"
    "lightminute" => "1,0,0,0,0,0,0,0,"
    "lightminutes" => "1,0,0,0,0,0,0,0,"
    "lightsecond" => "1,0,0,0,0,0,0,0,"
    "lightseconds" => "1,0,0,0,0,0,0,0,"
    "lightyear" => "1,0,0,0,0,0,0,0,"
    "lightyears" => "1,0,0,0,0,0,0,0,"
    "linear density" => "-1,1,0,0,0,0,0,0,"
    "link" => "1,0,0,0,0,0,0,0,"
    "link_chain" => "1,0,0,0,0,0,0,0,"
    "links" => "1,0,0,0,0,0,0,0,"
    "liter" => "3,0,0,0,0,0,0,0,"
    "liters" => "3,0,0,0,0,0,0,0,"
    "liters per 100 km" => "2,0,0,0,0,0,0,0,"
    "liters per minute" => "3,0,-1,0,0,0,0,0,"
    "litre" => "3,0,0,0,0,0,0,0,"
    "litres" => "3,0,0,0,0,0,0,0,"
    "litres per minute" => "3,0,-1,0,0,0,0,0,"
    "lm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "lm·s" => "0,0,1,0,0,0,1,0,luminous_flux:1"
    "long ton" => "0,1,0,0,0,0,0,0,"
    "long tons" => "0,1,0,0,0,0,0,0,"
    "lumen" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "lumens" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "luminous energy" => "0,0,1,0,0,0,1,0,luminous_flux:1"
    "luminous exposure" => "-2,0,1,0,0,0,1,0,illuminance:1"
    "lunar month" => "0,0,1,0,0,0,0,0,"
    "lunar months" => "0,0,1,0,0,0,0,0,"
    "lunarmonth" => "0,0,1,0,0,0,0,0,"
    "lustra" => "0,0,1,0,0,0,0,0,"
    "lustrum" => "0,0,1,0,0,0,0,0,"
    "lustrums" => "0,0,1,0,0,0,0,0,"
    "lux" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "lx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "lx·s" => "-2,0,1,0,0,0,1,0,illuminance:1"
    "ly" => "1,0,0,0,0,0,0,0,"
    "m" => "1,0,0,0,0,0,0,0,"
    "m H2O" => "-1,1,-2,0,0,0,0,0,"
    "m of water" => "-1,1,-2,0,0,0,0,0,"
    "m/s" => "1,0,-1,0,0,0,0,0,"
    "m/s²" => "1,0,-2,0,0,0,0,0,"
    "m/s³" => "1,0,-3,0,0,0,0,0,"
    "mA" => "0,0,0,1,0,0,0,0,"
    "mH2O" => "-1,1,-2,0,0,0,0,0,"
    "mL" => "3,0,0,0,0,0,0,0,"
    "m_e" => "0,1,0,0,0,0,0,0,"
    "m_n" => "0,1,0,0,0,0,0,0,"
    "m_p" => "0,1,0,0,0,0,0,0,"
    "m_μ" => "0,1,0,0,0,0,0,0,"
    "mac" => "0,0,0,0,0,0,0,0,mac:1"
    "mach" => "1,0,-1,0,0,0,0,0,"
    "mach_air_20C" => "1,0,-1,0,0,0,0,0,"
    "macs" => "0,0,0,0,0,0,0,0,mac:1"
    "mag" => "0,0,0,0,0,0,0,0,magnitude_apparent:1"
    "magnitude" => "0,0,0,0,0,0,0,0,magnitude_apparent:1"
    "magnitudes" => "0,0,0,0,0,0,0,0,magnitude_apparent:1"
    "magnum" => "3,0,0,0,0,0,0,0,"
    "magnums" => "3,0,0,0,0,0,0,0,"
    "maneh" => "0,1,0,0,0,0,0,0,"
    "mass density" => "-3,1,0,0,0,0,0,0,"
    "mass flow" => "0,1,-1,0,0,0,0,0,"
    "maund" => "0,1,0,0,0,0,0,0,"
    "maunds" => "0,1,0,0,0,0,0,0,"
    "maxwell" => "2,1,-2,-1,0,0,0,0,"
    "maxwells" => "2,1,-2,-1,0,0,0,0,"
    "mbar" => "-1,1,-2,0,0,0,0,0,"
    "megaton" => "0,1,0,0,0,0,0,0,"
    "megatons" => "0,1,0,0,0,0,0,0,"
    "melchizedek" => "3,0,0,0,0,0,0,0,"
    "melchizedeks" => "3,0,0,0,0,0,0,0,"
    "meter" => "1,0,0,0,0,0,0,0,"
    "meter of water" => "-1,1,-2,0,0,0,0,0,"
    "meters" => "1,0,0,0,0,0,0,0,"
    "meters of water" => "-1,1,-2,0,0,0,0,0,"
    "methuselah" => "3,0,0,0,0,0,0,0,"
    "methuselahs" => "3,0,0,0,0,0,0,0,"
    "metric cup" => "3,0,0,0,0,0,0,0,"
    "metric cups" => "3,0,0,0,0,0,0,0,"
    "metric tablespoon" => "3,0,0,0,0,0,0,0,"
    "metric tablespoons" => "3,0,0,0,0,0,0,0,"
    "metric tbsp" => "3,0,0,0,0,0,0,0,"
    "metric ton" => "0,1,0,0,0,0,0,0,"
    "metric tons" => "0,1,0,0,0,0,0,0,"
    "metric_cup" => "3,0,0,0,0,0,0,0,"
    "metric_tbsp" => "3,0,0,0,0,0,0,0,"
    "mg" => "0,1,0,0,0,0,0,0,"
    "mg/dL glucose" => "0,0,0,0,0,0,0,0,glucose_concentration:1"
    "mg/dL_glucose" => "0,0,0,0,0,0,0,0,glucose_concentration:1"
    "mho" => "-2,-1,3,2,0,0,0,0,"
    "mi" => "1,0,0,0,0,0,0,0,"
    "mi/h" => "1,0,-1,0,0,0,0,0,"
    "mickey" => "1,0,0,0,0,0,0,0,"
    "mickeys" => "1,0,0,0,0,0,0,0,"
    "microlife" => "0,0,1,0,0,0,0,0,"
    "microlives" => "0,0,1,0,0,0,0,0,"
    "micromort" => "0,0,0,0,0,0,0,0,"
    "micromorts" => "0,0,0,0,0,0,0,0,"
    "mil" => "0,0,0,0,0,0,0,0,angle:1"
    "mile" => "1,0,0,0,0,0,0,0,"
    "mile per hour" => "1,0,-1,0,0,0,0,0,"
    "miles" => "1,0,0,0,0,0,0,0,"
    "miles per gallon" => "-2,0,0,0,0,0,0,0,"
    "miles per gallon equivalent" => "-2,0,0,0,0,0,0,0,"
    "miles per hour" => "1,0,-1,0,0,0,0,0,"
    "mill_finance" => "0,0,0,0,0,0,0,0,"
    "mille passuum" => "1,0,0,0,0,0,0,0,"
    "mille_passuum" => "1,0,0,0,0,0,0,0,"
    "millennia" => "0,0,1,0,0,0,0,0,"
    "millennium" => "0,0,1,0,0,0,0,0,"
    "millenniums" => "0,0,1,0,0,0,0,0,"
    "millihelen" => "0,0,0,0,0,0,0,0,beauty:1"
    "millihelens" => "0,0,0,0,0,0,0,0,beauty:1"
    "mils" => "0,0,0,0,0,0,0,0,angle:1"
    "min" => "0,0,1,0,0,0,0,0,"
    "mina" => "0,1,0,0,0,0,0,0,"
    "minas" => "0,1,0,0,0,0,0,0,"
    "minute" => "0,0,1,0,0,0,0,0,"
    "minutes" => "0,0,1,0,0,0,0,0,"
    "mm" => "1,0,0,0,0,0,0,0,"
    "mmHg" => "-1,1,-2,0,0,0,0,0,"
    "mmol/L glucose" => "0,0,0,0,0,0,0,0,glucose_concentration:1"
    "mmol/L_glucose" => "0,0,0,0,0,0,0,0,glucose_concentration:1"
    "mo" => "0,0,1,0,0,0,0,0,"
    "mohs" => "0,0,0,0,0,0,0,0,hardness_mohs:1"
    "mol" => "0,0,0,0,0,1,0,0,"
    "mol/mol" => "0,0,0,0,0,0,0,0,ratio:1"
    "molal" => "0,-1,0,0,0,1,0,0,"
    "molar" => "-3,0,0,0,0,1,0,0,"
    "mole" => "0,0,0,0,0,1,0,0,"
    "mole fraction" => "0,0,0,0,0,0,0,0,ratio:1"
    "moles" => "0,0,0,0,0,1,0,0,"
    "moment" => "0,0,0,0,0,0,0,0,moment:1"
    "moment magnitude" => "0,0,0,0,0,0,0,0,magnitude:1"
    "moment_magnitude" => "0,0,0,0,0,0,0,0,magnitude:1"
    "moments" => "0,0,0,0,0,0,0,0,moment:1"
    "momentum" => "1,1,-1,0,0,0,0,0,momentum:1"
    "momme" => "0,1,0,0,0,0,0,0,"
    "mommes" => "0,1,0,0,0,0,0,0,"
    "month" => "0,0,1,0,0,0,0,0,"
    "months" => "0,0,1,0,0,0,0,0,"
    "moon mass" => "0,1,0,0,0,0,0,0,"
    "moonmass" => "0,1,0,0,0,0,0,0,"
    "mpg" => "-2,0,0,0,0,0,0,0,"
    "mpge" => "-2,0,0,0,0,0,0,0,"
    "mph" => "1,0,-1,0,0,0,0,0,"
    "ms" => "0,0,1,0,0,0,0,0,"
    "mu" => "2,0,0,0,0,0,0,0,"
    "muB" => "2,0,0,1,0,0,0,0,"
    "muon mass" => "0,1,0,0,0,0,0,0,"
    "muon_mass" => "0,1,0,0,0,0,0,0,"
    "mus" => "2,0,0,0,0,0,0,0,"
    "m²" => "2,0,0,0,0,0,0,0,"
    "m³" => "3,0,0,0,0,0,0,0,"
    "m³/(kg·s²)" => "3,-1,-2,0,0,0,0,0,"
    "m³/s" => "3,0,-1,0,0,0,0,0,"
    "mₚₗ" => "0,1,0,0,0,0,0,0,"
    "nail_cloth" => "1,0,0,0,0,0,0,0,"
    "nanobarn" => "2,0,0,0,0,0,0,0,"
    "nanobarns" => "2,0,0,0,0,0,0,0,"
    "nat" => "0,0,0,0,0,0,0,1,"
    "nats" => "0,0,0,0,0,0,0,1,"
    "nautical mile" => "1,0,0,0,0,0,0,0,"
    "nautical miles" => "1,0,0,0,0,0,0,0,"
    "nb-1" => "-2,0,0,0,0,0,0,0,"
    "nb^-1" => "-2,0,0,0,0,0,0,0,"
    "nbarn" => "2,0,0,0,0,0,0,0,"
    "nb⁻¹" => "-2,0,0,0,0,0,0,0,"
    "nebuchadnezzar" => "3,0,0,0,0,0,0,0,"
    "nebuchadnezzars" => "3,0,0,0,0,0,0,0,"
    "neutron mass" => "0,1,0,0,0,0,0,0,"
    "neutron_mass" => "0,1,0,0,0,0,0,0,"
    "newton" => "1,1,-2,0,0,0,0,0,"
    "newtons" => "1,1,-2,0,0,0,0,0,"
    "newtons per meter" => "0,1,-2,0,0,0,0,0,"
    "nibble" => "0,0,0,0,0,0,0,1,"
    "nibbles" => "0,0,0,0,0,0,0,1,"
    "nit" => "-2,0,0,0,0,0,1,0,luminance:1"
    "nits" => "-2,0,0,0,0,0,1,0,luminance:1"
    "nm" => "1,0,0,0,0,0,0,0,"
    "nmi" => "1,0,0,0,0,0,0,0,"
    "ns" => "0,0,1,0,0,0,0,0,"
    "o" => "0,0,0,0,0,0,0,1,"
    "octave" => "0,0,0,0,0,0,0,0,pitch:1"
    "octaves" => "0,0,0,0,0,0,0,0,pitch:1"
    "octet" => "0,0,0,0,0,0,0,1,"
    "octets" => "0,0,0,0,0,0,0,1,"
    "oersted" => "-1,0,0,1,0,0,0,0,"
    "oersteds" => "-1,0,0,1,0,0,0,0,"
    "ohm" => "2,1,-3,-2,0,0,0,0,"
    "ohm meter" => "3,1,-3,-2,0,0,0,0,"
    "ohms" => "2,1,-3,-2,0,0,0,0,"
    "oil barrel" => "3,0,0,0,0,0,0,0,"
    "oil barrels" => "3,0,0,0,0,0,0,0,"
    "oil_barrel" => "3,0,0,0,0,0,0,0,"
    "omer" => "3,0,0,0,0,0,0,0,"
    "omers" => "3,0,0,0,0,0,0,0,"
    "onah" => "0,0,1,0,0,0,0,0,"
    "onot" => "0,0,1,0,0,0,0,0,"
    "op" => "0,0,0,0,0,0,0,0,op:1"
    "ops" => "0,0,0,0,0,0,0,0,op:1"
    "ops_per_s" => "0,0,-1,0,0,0,0,0,op:1"
    "ounce" => "0,1,0,0,0,0,0,0,"
    "ounces" => "0,1,0,0,0,0,0,0,"
    "outhouse" => "2,0,0,0,0,0,0,0,"
    "oz" => "0,1,0,0,0,0,0,0,"
    "ozt" => "0,1,0,0,0,0,0,0,"
    "packet" => "0,0,0,0,0,0,0,0,packet:1"
    "packets" => "0,0,0,0,0,0,0,0,packet:1"
    "page" => "0,0,0,0,0,0,0,1,"
    "pages" => "0,0,0,0,0,0,0,1,"
    "paragraph" => "0,0,0,0,0,0,0,1,"
    "paragraphs" => "0,0,0,0,0,0,0,1,"
    "parsa" => "1,0,0,0,0,0,0,0,"
    "parsec" => "1,0,0,0,0,0,0,0,"
    "parsecs" => "1,0,0,0,0,0,0,0,"
    "parts per billion" => "0,0,0,0,0,0,0,0,ratio:1"
    "parts per hundred million" => "0,0,0,0,0,0,0,0,ratio:1"
    "parts per million" => "0,0,0,0,0,0,0,0,ratio:1"
    "parts per trillion" => "0,0,0,0,0,0,0,0,ratio:1"
    "parts-per-billion" => "0,0,0,0,0,0,0,0,ratio:1"
    "parts-per-million" => "0,0,0,0,0,0,0,0,ratio:1"
    "parts-per-trillion" => "0,0,0,0,0,0,0,0,ratio:1"
    "pascal" => "-1,1,-2,0,0,0,0,0,"
    "pascals" => "-1,1,-2,0,0,0,0,0,"
    "passus" => "1,0,0,0,0,0,0,0,"
    "passuses" => "1,0,0,0,0,0,0,0,"
    "pb" => "0,0,0,0,0,0,0,0,peanutbutter:1"
    "pb-1" => "-2,0,0,0,0,0,0,0,"
    "pb^-1" => "-2,0,0,0,0,0,0,0,"
    "pbarn" => "2,0,0,0,0,0,0,0,"
    "pb⁻¹" => "-2,0,0,0,0,0,0,0,"
    "pc" => "1,0,0,0,0,0,0,0,"
    "peanut butter" => "0,0,0,0,0,0,0,0,peanutbutter:1"
    "peanutbutter" => "0,0,0,0,0,0,0,0,peanutbutter:1"
    "peck" => "3,0,0,0,0,0,0,0,"
    "pecks" => "3,0,0,0,0,0,0,0,"
    "pedes" => "1,0,0,0,0,0,0,0,"
    "pennyweight" => "0,1,0,0,0,0,0,0,"
    "pennyweights" => "0,1,0,0,0,0,0,0,"
    "perch" => "1,0,0,0,0,0,0,0,"
    "perches" => "1,0,0,0,0,0,0,0,"
    "person hour" => "0,0,1,0,0,0,0,0,person:1"
    "person hours" => "0,0,1,0,0,0,0,0,person:1"
    "person_hour" => "0,0,1,0,0,0,0,0,person:1"
    "pes" => "1,0,0,0,0,0,0,0,"
    "petabyte" => "0,0,0,0,0,0,0,1,"
    "petabytes" => "0,0,0,0,0,0,0,1,"
    "petroleum barrel" => "3,0,0,0,0,0,0,0,"
    "petroleum_barrel" => "3,0,0,0,0,0,0,0,"
    "phon" => "0,0,0,0,0,0,0,0,loudness_level:1"
    "phons" => "0,0,0,0,0,0,0,0,loudness_level:1"
    "pica" => "1,0,0,0,0,0,0,0,"
    "picas" => "1,0,0,0,0,0,0,0,"
    "piccolo" => "3,0,0,0,0,0,0,0,"
    "picobarn" => "2,0,0,0,0,0,0,0,"
    "picobarns" => "2,0,0,0,0,0,0,0,"
    "pied" => "1,0,0,0,0,0,0,0,"
    "pied du roi" => "1,0,0,0,0,0,0,0,"
    "pieds" => "1,0,0,0,0,0,0,0,"
    "pieds du roi" => "1,0,0,0,0,0,0,0,"
    "pieze" => "-1,1,-2,0,0,0,0,0,"
    "pinch" => "3,0,0,0,0,0,0,0,"
    "pinches" => "3,0,0,0,0,0,0,0,"
    "pint" => "3,0,0,0,0,0,0,0,"
    "pints" => "3,0,0,0,0,0,0,0,"
    "pip" => "0,0,0,0,0,0,0,0,"
    "pipe" => "3,0,0,0,0,0,0,0,"
    "pipes" => "3,0,0,0,0,0,0,0,"
    "pips" => "0,0,0,0,0,0,0,0,"
    "pixel" => "1,0,0,0,0,0,0,0,"
    "pixels" => "1,0,0,0,0,0,0,0,"
    "pk" => "3,0,0,0,0,0,0,0,"
    "planck length" => "1,0,0,0,0,0,0,0,"
    "planck mass" => "0,1,0,0,0,0,0,0,"
    "planck time" => "0,0,1,0,0,0,0,0,"
    "pm" => "1,0,0,0,0,0,0,0,"
    "point" => "1,0,0,0,0,0,0,0,"
    "points" => "1,0,0,0,0,0,0,0,"
    "poise" => "-1,1,-1,0,0,0,0,0,"
    "pouce" => "1,0,0,0,0,0,0,0,"
    "pouces" => "1,0,0,0,0,0,0,0,"
    "pound" => "0,1,0,0,0,0,0,0,"
    "pound force" => "1,1,-2,0,0,0,0,0,"
    "pound-force" => "1,1,-2,0,0,0,0,0,"
    "pounds" => "0,1,0,0,0,0,0,0,"
    "ppb" => "0,0,0,0,0,0,0,0,ratio:1"
    "pphm" => "0,0,0,0,0,0,0,0,ratio:1"
    "ppm" => "0,0,0,0,0,0,0,0,ratio:1"
    "pps" => "0,0,-1,0,0,0,0,0,packet:1"
    "ppt" => "0,0,0,0,0,0,0,0,ratio:1"
    "proton mass" => "0,1,0,0,0,0,0,0,"
    "proton_mass" => "0,1,0,0,0,0,0,0,"
    "ps" => "0,0,1,0,0,0,0,0,"
    "psi" => "-1,1,-2,0,0,0,0,0,"
    "pt" => "3,0,0,0,0,0,0,0,"
    "pud" => "0,1,0,0,0,0,0,0,"
    "puds" => "0,1,0,0,0,0,0,0,"
    "puncheon" => "3,0,0,0,0,0,0,0,"
    "puncheons" => "3,0,0,0,0,0,0,0,"
    "px" => "1,0,0,0,0,0,0,0,"
    "qps" => "0,0,-1,0,0,0,0,0,query:1"
    "qquad" => "0,0,0,0,0,0,0,0,em:1"
    "qr" => "0,1,0,0,0,0,0,0,"
    "qt" => "3,0,0,0,0,0,0,0,"
    "quad" => "0,0,0,0,0,0,0,0,em:1"
    "quality adjusted life year" => "0,0,1,0,0,0,0,0,quality_adjusted_life:1"
    "quality-adjusted life year" => "0,0,1,0,0,0,0,0,quality_adjusted_life:1"
    "quart" => "3,0,0,0,0,0,0,0,"
    "quarter" => "0,1,0,0,0,0,0,0,"
    "quarters" => "0,1,0,0,0,0,0,0,"
    "quarts" => "3,0,0,0,0,0,0,0,"
    "queries" => "0,0,0,0,0,0,0,0,query:1"
    "query" => "0,0,0,0,0,0,0,0,query:1"
    "quintal" => "0,1,0,0,0,0,0,0,"
    "quintals" => "0,1,0,0,0,0,0,0,"
    "qword" => "0,0,0,0,0,0,0,1,"
    "qwords" => "0,0,0,0,0,0,0,1,"
    "rack unit" => "1,0,0,0,0,0,0,0,"
    "rack units" => "1,0,0,0,0,0,0,0,"
    "rad" => "0,0,0,0,0,0,0,0,angle:1"
    "rad/s" => "0,0,-1,0,0,0,0,0,angle:1"
    "rad/s²" => "0,0,-2,0,0,0,0,0,angle:1"
    "radian" => "0,0,0,0,0,0,0,0,angle:1"
    "radians" => "0,0,0,0,0,0,0,0,angle:1"
    "rankine" => "0,0,0,0,1,0,0,0,"
    "rankine difference" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "rbe" => "0,0,0,0,0,0,0,0,rbe:1"
    "rd" => "0,0,-1,0,0,0,0,0,decay:1"
    "reaumur" => "0,0,0,0,1,0,0,0,"
    "rega" => "0,0,1,0,0,0,0,0,"
    "regaim" => "0,0,1,0,0,0,0,0,"
    "rehoboam" => "3,0,0,0,0,0,0,0,"
    "relative biological effectiveness" => "0,0,0,0,0,0,0,0,rbe:1"
    "rem" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "rem_css" => "0,0,0,0,0,0,0,0,css_root_font_size:1"
    "rems" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "request" => "0,0,0,0,0,0,0,0,request:1"
    "requests" => "0,0,0,0,0,0,0,0,request:1"
    "resistivity" => "3,1,-3,-2,0,0,0,0,"
    "rev" => "0,0,0,0,0,0,0,0,revolution:1"
    "revolution" => "0,0,0,0,0,0,0,0,revolution:1"
    "revolutions" => "0,0,0,0,0,0,0,0,revolution:1"
    "revolutions per minute" => "0,0,-1,0,0,0,0,0,revolution:1"
    "revs" => "0,0,0,0,0,0,0,0,revolution:1"
    "ri" => "1,0,0,0,0,0,0,0,"
    "richter" => "0,0,0,0,0,0,0,0,magnitude:1"
    "richter scale" => "0,0,0,0,0,0,0,0,magnitude:1"
    "rockwell" => "0,0,0,0,0,0,0,0,hardness_rockwell:1"
    "rod" => "1,0,0,0,0,0,0,0,"
    "rods" => "1,0,0,0,0,0,0,0,"
    "roman libra" => "0,1,0,0,0,0,0,0,"
    "roman mile" => "1,0,0,0,0,0,0,0,"
    "roman uncia" => "0,1,0,0,0,0,0,0,"
    "romer" => "0,0,0,0,1,0,0,0,"
    "rope" => "1,0,0,0,0,0,0,0,"
    "ropes" => "1,0,0,0,0,0,0,0,"
    "rot" => "0,0,0,0,0,0,0,0,rotation:1"
    "rotation" => "0,0,0,0,0,0,0,0,rotation:1"
    "rotations" => "0,0,0,0,0,0,0,0,rotation:1"
    "rotations per minute" => "0,0,-1,0,0,0,0,0,revolution:1"
    "royal cubit" => "1,0,0,0,0,0,0,0,"
    "royal cubits" => "1,0,0,0,0,0,0,0,"
    "royal_cubit" => "1,0,0,0,0,0,0,0,"
    "rpm" => "0,0,-1,0,0,0,0,0,revolution:1"
    "rps" => "0,0,-1,0,0,0,0,0,request:1"
    "rundlet" => "3,0,0,0,0,0,0,0,"
    "rundlets" => "3,0,0,0,0,0,0,0,"
    "russian funt" => "0,1,0,0,0,0,0,0,"
    "russian_funt" => "0,1,0,0,0,0,0,0,"
    "rutherford" => "0,0,-1,0,0,0,0,0,decay:1"
    "rutherfords" => "0,0,-1,0,0,0,0,0,decay:1"
    "rydberg" => "2,1,-2,0,0,0,0,0,"
    "rydberg_unit" => "2,1,-2,0,0,0,0,0,"
    "rydbergs" => "2,1,-2,0,0,0,0,0,"
    "réaumur" => "0,0,0,0,1,0,0,0,"
    "rømer" => "0,0,0,0,1,0,0,0,"
    "s" => "0,0,1,0,0,0,0,0,"
    "sabbath day's journey" => "1,0,0,0,0,0,0,0,"
    "sabbatical" => "0,0,1,0,0,0,0,0,"
    "saffir simpson" => "0,0,0,0,0,0,0,0,saffir_simpson:1"
    "saffir_simpson" => "0,0,0,0,0,0,0,0,saffir_simpson:1"
    "sagan" => "0,0,0,0,0,0,0,0,"
    "sagans" => "0,0,0,0,0,0,0,0,"
    "sample" => "0,0,0,0,0,0,0,0,sample:1"
    "samples" => "0,0,0,0,0,0,0,0,sample:1"
    "savart" => "0,0,0,0,0,0,0,0,pitch:1"
    "savarts" => "0,0,0,0,0,0,0,0,pitch:1"
    "sazhen" => "1,0,0,0,0,0,0,0,"
    "sazhens" => "1,0,0,0,0,0,0,0,"
    "sb" => "-2,0,0,0,0,0,1,0,luminance:1"
    "score" => "0,0,0,0,0,0,0,0,"
    "scores" => "0,0,0,0,0,0,0,0,"
    "scruple" => "0,1,0,0,0,0,0,0,"
    "scruples" => "0,1,0,0,0,0,0,0,"
    "seah" => "3,0,0,0,0,0,0,0,"
    "seahs" => "3,0,0,0,0,0,0,0,"
    "second" => "0,0,1,0,0,0,0,0,"
    "seconds" => "0,0,1,0,0,0,0,0,"
    "sector" => "0,0,0,0,0,0,0,1,"
    "sectors" => "0,0,0,0,0,0,0,1,"
    "seer" => "0,1,0,0,0,0,0,0,"
    "seers" => "0,1,0,0,0,0,0,0,"
    "seim" => "3,0,0,0,0,0,0,0,"
    "semitone" => "0,0,0,0,0,0,0,0,pitch:1"
    "semitones" => "0,0,0,0,0,0,0,0,pitch:1"
    "shaftment" => "1,0,0,0,0,0,0,0,"
    "shaftments" => "1,0,0,0,0,0,0,0,"
    "shake" => "0,0,1,0,0,0,0,0,"
    "shakes" => "0,0,1,0,0,0,0,0,"
    "shaku" => "1,0,0,0,0,0,0,0,"
    "shakus" => "1,0,0,0,0,0,0,0,"
    "shed" => "2,0,0,0,0,0,0,0,"
    "shekalim" => "0,1,0,0,0,0,0,0,"
    "shekel" => "0,1,0,0,0,0,0,0,"
    "shekels" => "0,1,0,0,0,0,0,0,"
    "shmita" => "0,0,1,0,0,0,0,0,"
    "shmitas" => "0,0,1,0,0,0,0,0,"
    "shmitta" => "0,0,1,0,0,0,0,0,"
    "short ton" => "0,1,0,0,0,0,0,0,"
    "short tons" => "0,1,0,0,0,0,0,0,"
    "sidereal day" => "0,0,1,0,0,0,0,0,"
    "sidereal days" => "0,0,1,0,0,0,0,0,"
    "sidereal year" => "0,0,1,0,0,0,0,0,"
    "sidereal years" => "0,0,1,0,0,0,0,0,"
    "siderealday" => "0,0,1,0,0,0,0,0,"
    "siderealyear" => "0,0,1,0,0,0,0,0,"
    "siemens" => "-2,-1,3,2,0,0,0,0,"
    "siemens per meter" => "-3,-1,3,2,0,0,0,0,"
    "sievert" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "sieverts" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "sk" => "-2,0,0,0,0,0,1,0,luminance:1"
    "skot" => "-2,0,0,0,0,0,1,0,luminance:1"
    "skots" => "-2,0,0,0,0,0,1,0,luminance:1"
    "slug" => "0,1,0,0,0,0,0,0,"
    "slugs" => "0,1,0,0,0,0,0,0,"
    "smidgen" => "3,0,0,0,0,0,0,0,"
    "smidgens" => "3,0,0,0,0,0,0,0,"
    "smoot" => "1,0,0,0,0,0,0,0,"
    "smoots" => "1,0,0,0,0,0,0,0,"
    "solar mass" => "0,1,0,0,0,0,0,0,"
    "solar radius" => "1,0,0,0,0,0,0,0,"
    "solarmass" => "0,1,0,0,0,0,0,0,"
    "solarradius" => "1,0,0,0,0,0,0,0,"
    "sone" => "0,0,0,0,0,0,0,0,loudness:1"
    "sones" => "0,0,0,0,0,0,0,0,loudness:1"
    "span" => "1,0,0,0,0,0,0,0,"
    "spans" => "1,0,0,0,0,0,0,0,"
    "specific energy" => "2,0,-2,0,0,0,0,0,specific_energy:1"
    "specific heat capacity" => "2,0,-2,0,-1,0,0,0,"
    "specific_energy" => "2,0,-2,0,0,0,0,0,specific_energy:1"
    "spectral efficiency" => "0,0,0,0,0,0,0,1,spectral_efficiency:1"
    "split" => "3,0,0,0,0,0,0,0,"
    "splits" => "3,0,0,0,0,0,0,0,"
    "sq ft" => "2,0,0,0,0,0,0,0,"
    "sqft" => "2,0,0,0,0,0,0,0,"
    "sqm" => "2,0,0,0,0,0,0,0,"
    "square feet" => "2,0,0,0,0,0,0,0,"
    "square foot" => "2,0,0,0,0,0,0,0,"
    "sr" => "0,0,0,0,0,0,0,0,solid_angle:1"
    "st" => "0,1,0,0,0,0,0,0,"
    "standard gravity" => "1,0,-2,0,0,0,0,0,"
    "steradian" => "0,0,0,0,0,0,0,0,solid_angle:1"
    "steradians" => "0,0,0,0,0,0,0,0,solid_angle:1"
    "stere" => "3,0,0,0,0,0,0,0,"
    "stick" => "0,1,0,0,0,0,0,0,"
    "stick of butter" => "0,1,0,0,0,0,0,0,"
    "sticks" => "0,1,0,0,0,0,0,0,"
    "sticks of butter" => "0,1,0,0,0,0,0,0,"
    "stilb" => "-2,0,0,0,0,0,1,0,luminance:1"
    "stilbs" => "-2,0,0,0,0,0,1,0,luminance:1"
    "stokes" => "2,0,-1,0,0,0,0,0,"
    "stone" => "0,1,0,0,0,0,0,0,"
    "stones" => "0,1,0,0,0,0,0,0,"
    "stop" => "0,0,0,0,0,0,0,0,exposure_value:1"
    "stops" => "0,0,0,0,0,0,0,0,exposure_value:1"
    "story point" => "0,0,0,0,0,0,0,0,story_point:1"
    "story points" => "0,0,0,0,0,0,0,0,story_point:1"
    "story_point" => "0,0,0,0,0,0,0,0,story_point:1"
    "stère" => "3,0,0,0,0,0,0,0,"
    "stères" => "3,0,0,0,0,0,0,0,"
    "sun" => "1,0,0,0,0,0,0,0,"
    "suns" => "1,0,0,0,0,0,0,0,"
    "surface tension" => "0,1,-2,0,0,0,0,0,"
    "synodic month" => "0,0,1,0,0,0,0,0,"
    "synodic months" => "0,0,1,0,0,0,0,0,"
    "t" => "0,1,0,0,0,0,0,0,"
    "tablespoon" => "3,0,0,0,0,0,0,0,"
    "tablespoons" => "3,0,0,0,0,0,0,0,"
    "talent" => "0,1,0,0,0,0,0,0,"
    "talents" => "0,1,0,0,0,0,0,0,"
    "talmudic mil" => "1,0,0,0,0,0,0,0,"
    "talmudic_mil" => "1,0,0,0,0,0,0,0,"
    "tatami" => "2,0,0,0,0,0,0,0,"
    "tatamis" => "2,0,0,0,0,0,0,0,"
    "tbsp" => "3,0,0,0,0,0,0,0,"
    "tce" => "2,1,-2,0,0,0,0,0,"
    "teaspoon" => "3,0,0,0,0,0,0,0,"
    "teaspoons" => "3,0,0,0,0,0,0,0,"
    "techum" => "1,0,0,0,0,0,0,0,"
    "techum shabbat" => "1,0,0,0,0,0,0,0,"
    "tefach" => "1,0,0,0,0,0,0,0,"
    "tefachim" => "1,0,0,0,0,0,0,0,"
    "tenth cent" => "0,0,0,0,0,0,0,0,"
    "tenth_cent" => "0,0,0,0,0,0,0,0,"
    "tertian" => "3,0,0,0,0,0,0,0,"
    "tesla" => "0,1,-2,-1,0,0,0,0,"
    "teslas" => "0,1,-2,-1,0,0,0,0,"
    "tex" => "0,0,0,0,0,0,0,0,linear_density:1"
    "texpt" => "1,0,0,0,0,0,0,0,"
    "therm" => "2,1,-2,0,0,0,0,0,"
    "thermal conductivity" => "1,1,-3,0,-1,0,0,0,"
    "therms" => "2,1,-2,0,0,0,0,0,"
    "tick" => "0,0,0,0,0,0,0,0,tick:1"
    "ticks" => "0,0,0,0,0,0,0,0,tick:1"
    "tierce" => "3,0,0,0,0,0,0,0,"
    "tierces" => "3,0,0,0,0,0,0,0,"
    "tn" => "0,1,0,0,0,0,0,0,"
    "toise" => "1,0,0,0,0,0,0,0,"
    "toises" => "1,0,0,0,0,0,0,0,"
    "tok" => "0,0,0,0,0,0,0,0,token:1"
    "tok/s" => "0,0,-1,0,0,0,0,0,token:1"
    "token" => "0,0,0,0,0,0,0,0,token:1"
    "tokens" => "0,0,0,0,0,0,0,0,token:1"
    "tola" => "0,1,0,0,0,0,0,0,"
    "tolas" => "0,1,0,0,0,0,0,0,"
    "ton" => "0,1,0,0,0,0,0,0,"
    "tonne" => "0,1,0,0,0,0,0,0,"
    "tonne of coal equivalent" => "2,1,-2,0,0,0,0,0,"
    "tonnes" => "0,1,0,0,0,0,0,0,"
    "tons" => "0,1,0,0,0,0,0,0,"
    "torque" => "2,1,-2,0,0,0,0,0,torque:1"
    "torr" => "-1,1,-2,0,0,0,0,0,"
    "torrs" => "-1,1,-2,0,0,0,0,0,"
    "tps" => "0,0,-1,0,0,0,0,0,transaction:1"
    "transaction" => "0,0,0,0,0,0,0,0,transaction:1"
    "transactions" => "0,0,0,0,0,0,0,0,transaction:1"
    "transfer" => "0,0,0,0,0,0,0,0,transfer:1"
    "transfers" => "0,0,0,0,0,0,0,0,transfer:1"
    "transport carbon intensity" => "-1,1,0,0,0,0,0,0,transport_co2e:1"
    "tropical year" => "0,0,1,0,0,0,0,0,"
    "tropical years" => "0,0,1,0,0,0,0,0,"
    "tropicalyear" => "0,0,1,0,0,0,0,0,"
    "troy ounce" => "0,1,0,0,0,0,0,0,"
    "troy ounces" => "0,1,0,0,0,0,0,0,"
    "troyounce" => "0,1,0,0,0,0,0,0,"
    "tsp" => "3,0,0,0,0,0,0,0,"
    "tsubo" => "2,0,0,0,0,0,0,0,"
    "tsubos" => "2,0,0,0,0,0,0,0,"
    "tun" => "3,0,0,0,0,0,0,0,"
    "tuns" => "3,0,0,0,0,0,0,0,"
    "turn" => "0,0,0,0,0,0,0,0,angle:1"
    "turns" => "0,0,0,0,0,0,0,0,angle:1"
    "txn" => "0,0,0,0,0,0,0,0,transaction:1"
    "tₚ" => "0,0,1,0,0,0,0,0,"
    "u" => "0,1,0,0,0,0,0,0,"
    "uncia_roma" => "0,1,0,0,0,0,0,0,"
    "vershok" => "1,0,0,0,0,0,0,0,"
    "vershoks" => "1,0,0,0,0,0,0,0,"
    "verst" => "1,0,0,0,0,0,0,0,"
    "versts" => "1,0,0,0,0,0,0,0,"
    "vh" => "0,0,0,0,0,0,0,0,viewport_height_percent:1"
    "vickers" => "0,0,0,0,0,0,0,0,hardness_vickers:1"
    "viewport height" => "0,0,0,0,0,0,0,0,viewport_height_percent:1"
    "viewport width" => "0,0,0,0,0,0,0,0,viewport_width_percent:1"
    "volt" => "2,1,-3,-1,0,0,0,0,"
    "volts" => "2,1,-3,-1,0,0,0,0,"
    "volts per meter" => "1,1,-3,-1,0,0,0,0,"
    "volumetric flow" => "3,0,-1,0,0,0,0,0,"
    "vw" => "0,0,0,0,0,0,0,0,viewport_width_percent:1"
    "warhol" => "0,0,0,0,0,0,0,0,fame:1"
    "warhols" => "0,0,0,0,0,0,0,0,fame:1"
    "water horsepower" => "2,1,-3,0,0,0,0,0,"
    "water_horsepower" => "2,1,-3,0,0,0,0,0,"
    "watt" => "2,1,-3,0,0,0,0,0,"
    "watts" => "2,1,-3,0,0,0,0,0,"
    "watts per square meter" => "0,1,-3,0,0,0,0,0,"
    "wavenumber" => "-1,0,0,0,0,0,0,0,"
    "weber" => "2,1,-2,-1,0,0,0,0,"
    "webers" => "2,1,-2,-1,0,0,0,0,"
    "wedgwood" => "0,0,0,0,1,0,0,0,"
    "week" => "0,0,1,0,0,0,0,0,"
    "weeks" => "0,0,1,0,0,0,0,0,"
    "wk" => "0,0,1,0,0,0,0,0,"
    "yard" => "1,0,0,0,0,0,0,0,"
    "yards" => "1,0,0,0,0,0,0,0,"
    "yd" => "1,0,0,0,0,0,0,0,"
    "year" => "0,0,1,0,0,0,0,0,"
    "years" => "0,0,1,0,0,0,0,0,"
    "yovel" => "0,0,1,0,0,0,0,0,"
    "yovels" => "0,0,1,0,0,0,0,0,"
    "yr" => "0,0,1,0,0,0,0,0,"
    "zeret" => "1,0,0,0,0,0,0,0,"
    "zhang" => "1,0,0,0,0,0,0,0,"
    "zhangs" => "1,0,0,0,0,0,0,0,"
    "°" => "0,0,0,0,0,0,0,0,angle:1"
    "°C" => "0,0,0,0,1,0,0,0,"
    "°De" => "0,0,0,0,1,0,0,0,"
    "°F" => "0,0,0,0,1,0,0,0,"
    "°N" => "0,0,0,0,1,0,0,0,"
    "°R" => "0,0,0,0,1,0,0,0,"
    "°Ra" => "0,0,0,0,1,0,0,0,"
    "°Re" => "0,0,0,0,1,0,0,0,"
    "°Ré" => "0,0,0,0,1,0,0,0,"
    "°Rø" => "0,0,0,0,1,0,0,0,"
    "°W" => "0,0,0,0,1,0,0,0,"
    "°r" => "0,0,0,0,1,0,0,0,"
    "µA" => "0,0,0,1,0,0,0,0,"
    "µg" => "0,1,0,0,0,0,0,0,"
    "µm" => "1,0,0,0,0,0,0,0,"
    "µs" => "0,0,1,0,0,0,0,0,"
    "Å" => "1,0,0,0,0,0,0,0,"
    "ångström" => "1,0,0,0,0,0,0,0,"
    "ɡ" => "1,0,-2,0,0,0,0,0,"
    "ʒ" => "0,1,0,0,0,0,0,0,"
    "ΔK" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "Δ°C" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "Δ°De" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "Δ°F" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "Δ°N" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "Δ°R" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "Δ°Ré" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "Δ°Rø" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "Δ°W" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "Ω" => "2,1,-3,-2,0,0,0,0,"
    "Ω·m" => "3,1,-3,-2,0,0,0,0,"
    "α" => "0,0,0,0,0,0,0,0,"
    "μ_B" => "2,0,0,1,0,0,0,0,"
    "μlife" => "0,0,1,0,0,0,0,0,"
    "μmort" => "0,0,0,0,0,0,0,0,"
    "℃" => "0,0,0,0,1,0,0,0,"
    "℈" => "0,1,0,0,0,0,0,0,"
    "℉" => "0,0,0,0,1,0,0,0,"
    "ℓₚ" => "1,0,0,0,0,0,0,0,"
    "℔" => "0,1,0,0,0,0,0,0,"
    "℥" => "0,1,0,0,0,0,0,0,"
    "℧" => "-2,-1,3,2,0,0,0,0,"
    "㍳" => "1,0,0,0,0,0,0,0,"
    => nil

# --- END GENERATED: lookup_unit_id ---

# Custom-unit ids live on the module (seeded in wire.w's module literal), NOT
# on ctx: assigning a brand-new key into the live ctx hash mid-lowering was a
# real crash ("cannot add object/array + nil" downstream in lower_ast) — the
# hash's specialized reads don't survive the shape change. mod is shared by
# every child ctx, which custom units want anyway.
-> assign_custom_unit(ctx, unit, node)
  mod = ctx[:mod]
  if mod[:custom_units].has_key?(unit)
    return mod[:custom_units][unit]
  id = mod[:next_custom_unit_id]
  mod[:next_custom_unit_id] = id + 1
  if id >= 4096
    raise compile_error_for_node(:E_LOWER_TOO_MANY_UNITS, "Too many custom units (max 2048)", ctx[:source_path], node)
  mod[:custom_units][unit] = id
  id

-> parse_duration(raw, ctx, node)
  # Parse compact duration: 2h30m, 500ms, 1y2mo3d, etc.
  # Returns {mode: 0, ns: value} or {mode: 1, months: m, ms: ms}
  total_months = 0
  total_ms = 0
  total_ns = 0
  has_calendar = false
  has_ns = false

  pos = 0
  chars = raw.chars()
  while pos < chars.size()
    # Scan number
    num_str = ""
    while pos < chars.size() && (chars[pos] >= "0" && chars[pos] <= "9")
      num_str += chars[pos]
      pos += 1
    num = num_str.to_i()

    # Scan unit
    if pos + 1 < chars.size() && chars[pos] == "m" && chars[pos + 1] == "o"
      total_months += num
      has_calendar = true
      pos += 2
    elsif pos + 1 < chars.size() && chars[pos] == "m" && chars[pos + 1] == "s"
      total_ms += num
      pos += 2
    elsif pos + 1 < chars.size() && chars[pos] == "n" && chars[pos + 1] == "s"
      total_ns += num
      has_ns = true
      pos += 2
    elsif pos < chars.size() && chars[pos] == "y"
      total_months += num * 12
      has_calendar = true
      pos += 1
    elsif pos < chars.size() && chars[pos] == "w"
      total_ms += num * 7 * 24 * 3600 * 1000
      pos += 1
    elsif pos < chars.size() && chars[pos] == "d"
      total_ms += num * 24 * 3600 * 1000
      pos += 1
    elsif pos < chars.size() && chars[pos] == "h"
      total_ms += num * 3600 * 1000
      pos += 1
    elsif pos < chars.size() && chars[pos] == "m"
      total_ms += num * 60 * 1000
      pos += 1
    elsif pos < chars.size() && chars[pos] == "s"
      total_ms += num * 1000
      pos += 1
    else
      raise compile_error_for_node(:E_LOWER_DURATION_INVALID_UNIT, "Invalid duration unit at position [pos] in '[raw]'", ctx[:source_path], node)

  # Decide mode
  if has_calendar || (!has_ns && total_ms > 0)
    # Mode 1: months + ms
    return {mode: 1, months: total_months, ms: total_ms}

  if has_ns || total_ns > 0
    # Mode 0: nanoseconds
    ns = total_ns + total_ms * 1000000
    return {mode: 0, ns: ns}

  # Pure ms without calendar → mode 1
  {mode: 1, months: 0, ms: total_ms}
