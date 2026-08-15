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
  # A source literal is immutable and has module lifetime.  Give it a
  # dedicated publication slot rather than reparsing its decimal spelling at
  # every dynamic evaluation (for example, when the literal appears in a
  # loop).  The opt-out is retained solely for matched compiler A/Bs.
  # Restrict the cache to lexically repeated sites.  A one-shot literal would
  # still need its initial parse plus a template copy, so caching it is a pure
  # regression; a loop-local site amortizes that setup and is the measured
  # workload this opcode is intended to remove.
  if env("TUNGSTEN_BIGINT_LITERAL_CACHE") != "0" && current_loop(wfn) != nil
    mod = ctx[:mod]
    str_id = module_string_constant(mod, text)
    slot_id = mod[:next_bigint_literal]
    mod[:next_bigint_literal] = slot_id + 1
    temp_ptr = next_temp(wfn)
    temp = next_temp(wfn)
    emit_instruction(wfn, {
      op: :bigint_literal_i64,
      temp: temp,
      temp_ptr: temp_ptr,
      string_id: str_id,
      byte_len: utf8_byte_length(text) + 1,
      slot_id: slot_id
    })
    return typed_value(:i64, temp)

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
    v = (w_tag_stringsym + byte_len * 2) ## i64
    bytes = s.bytes()
    i = 0
    while i < byte_len
      v = (v + bytes[i] * (1 << (4 + 8 * i))) ## i64
      i += 1
    return typed_value(:i64, wvalue_literal_text(machine_i64_box(v)))
  str_id = module_string_constant(ctx[:mod], s)
  temp_ptr = next_temp(ctx[:func])
  temp = next_temp(ctx[:func])
  emit_instruction(ctx[:func], {op: :string_i64, temp: temp, temp_ptr: temp_ptr, string_id: str_id, byte_len: byte_len + 1})
  typed_value(:i64, temp)

-> lower_string_interp(ctx, node)
  wfn = ctx[:func]
  parts = node.parts
  result = nil
  result_is_chain = false
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
      # Chain links after the first concat: `result` is the PREVIOUS
      # concat's temp — anonymous by construction (interpolation builds
      # it; no user name exists) and consumed only here, so the freeing
      # variant reclaims each intermediate of an N-part interpolation
      # instead of leaking N-2 strings per evaluation.
      # env gate: TUNGSTEN_FREE=0 must silence every compiler-inserted free.
      cn = i >= 2 && result_is_chain && env("TUNGSTEN_FREE") != "0" ? "w_str_concat_free_lhs" : "w_str_concat"
      emit_instruction(wfn, {op: :call_direct_i64, temp: concat, name: cn, args: [result, part_reg]})
      result = concat
      result_is_chain = true
    i += 1
  if result == nil
    return lower_string(ctx, Tungsten:AST:String.new(""))
  typed_value(:i64, result)

# -- Arrays --

# Try to fold a literal `[c1, c2, ...]` whose elements are all
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

# `%i[a b c]` — same desugar, but the spellings become Symbol literal nodes
# so the elements evaluate to interned Symbols, matching the interpreter.
-> lower_symbol_array(ctx, symbols)
  elements = []
  i = 0
  while i < symbols.size()
    elements.push(Tungsten:AST:Symbol.new(symbols[i]))
    i = i + 1
  lower_array(ctx, Tungsten:AST:Array.new(elements))

-> lower_array(ctx, node)
  wfn = ctx[:func]
  arr = next_temp(wfn)
  # Const-folding to SmallArray is gated off by default. The
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
  # Non-empty literal: allocate at the EXACT final size once and store each
  # element straight into its slot (alwaysinline helper -> load slots ptr +
  # store). The old shape -- w_array_new_empty + one w_array_push per
  # element -- paid a call, a grow check, and an ebits-dispatched
  # array_write per element (~40% of the new_array primitive). Empty []
  # keeps w_array_new_empty for the recycle-pool reuse.
  n_elems = node.elements.size()
  if n_elems > 0
    emit_instruction(wfn, {op: :call_direct_i64, temp: arr, name: "w_array_new_uninit_sized", args: ["65", n_elems.to_s()]})
  else
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
    if eh != nil && ast_kind(elem) != :type_ascription
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
    emit_instruction(wfn, {op: :call_direct_i64, temp: push_temp, name: "__w_array_lit_store", args: [arr, i.to_s(), val_reg]})
    i += 1
  typed_value(:i64, arr)

# Lower a boxed array literal immediately as a typed float buffer. A
# `[...] ## f64[N]` result previously allocated a 65-bit WValue array, boxed
# every element into it, then allocated and filled a second f64 array through
# w_array_to_f64. The ascription already fixes the final representation, so
# construct that representation once and store each coerced raw float in place.
-> lower_float_typed_array_literal(ctx, node, array_etype)
  wfn = ctx[:func]
  target_type = typed_array_etype_to_sym(array_etype)
  element_bits = array_etype == "f32" ? "-32" : "-64"
  store_bits = array_etype == "f32" ? 32 : 64
  arr = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: arr, name: "w_array_new_inline", args: [element_bits, node.elements.size().to_s()]})
  i = 0
  while i < node.elements.size()
    val = lower_expression(ctx, node.elements[i])
    val_bits = raw_float_bits_i64(wfn, val, target_type)
    scratch = []
    si = 0
    while si < 10
      scratch.push(next_temp(wfn))
      si += 1
    stored = next_temp(wfn)
    emit_instruction(wfn, {op: :typed_array_set_inline, temp: stored, arr: arr, idx: i.to_s(), idx_raw: true, value: val_bits, s: scratch, bits: store_bits, signed: true})
    i += 1
  typed_value(target_type, arr)

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

  # Escaped range value: one call into the runtime constructor, which
  # mints the immediate Location-mode-11 Range when the bounds fit its
  # sub-modes and falls back to the historical eager boxed-int Array
  # otherwise. Replaces the emitted per-element push loop — an escaped
  # `lo..hi` is now O(1) for every immediate-encodable range. Pipeline
  # fusion and range-elision still intercept non-escaping ranges before
  # this point.

  # Lower bounds and unbox to raw i64
  from_tv = lower_expression(ctx, node.from)
  from_reg = ensure_i64_value(wfn, from_tv)
  to_tv = lower_expression(ctx, node.to)
  to_reg = ensure_i64_value(wfn, to_tv)

  # Same guard as the range.each fast path: nanunbox_int is raw bit
  # extraction, correct only for genuinely inline-boxed ints. A bound
  # that is statically known non-int (e.g. a Decimal literal like 1e10)
  # routes through w_range_bound_i64 (type check + coercion, catchable
  # TypeError) instead of silently reinterpreting its bits.
  from_static_type = infer_type(node.from, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
  to_static_type = infer_type(node.to, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
  if from_static_type != nil && !is_integer_like_type(from_static_type)
    from_raw = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: from_raw, name: "w_range_bound_i64", args: [from_reg]})
  else
    from_raw = next_temp(wfn)
    emit_instruction(wfn, {op: :nanunbox_int, temp: from_raw, temp_shl: from_raw + ".shl", boxed: from_reg})
  if to_static_type != nil && !is_integer_like_type(to_static_type)
    to_raw = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: to_raw, name: "w_range_bound_i64", args: [to_reg]})
  else
    to_raw = next_temp(wfn)
    emit_instruction(wfn, {op: :nanunbox_int, temp: to_raw, temp_shl: to_raw + ".shl", boxed: to_reg})

  excl = "0"
  if node.exclusive == true
    excl = "1"
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_range_make", args: [from_raw, to_raw, excl]})
  typed_value(:i64, temp)



# -- Deep literal lowerings (domain types) --

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
  digits_txt = s
  if dot == nil
    scale = 0 + exp_adj
  else
    int_part = s.slice(0, dot)
    frac_part = s.slice(dot + 1, s.size())
    digits_txt = int_part + frac_part
    scale = 0 - frac_part.size() + exp_adj
  # A significand beyond i64 constructs a BigDecimal at runtime from the
  # digit TEXT (never through .to_i here — the stage-0 host stores compile-
  # time ints in int64_t, so a value-level decision or constant would
  # diverge between stages, and the value would wrap besides). The digit-
  # count test strips leading zeros textually.
  stripped = digits_txt
  lz = 0
  while lz < stripped.size() - 1 && stripped.slice(lz, 1) == "0"
    lz += 1
  if lz > 0
    stripped = stripped.slice(lz, stripped.size() - lz)
  if stripped.size() > 18
    str_tv = lower_string(ctx, Tungsten:AST:String.new(digits_txt))
    str_reg = ensure_i64_value(wfn, str_tv)
    sc_masked = scale & 281474976710655
    sc_bits = wvalue_literal_text(-1688849860263936 + sc_masked)
    neg_arg = neg ? "2" : "1"
    btemp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: btemp, name: "w_decimal_from_digits", args: [str_reg, sc_bits, neg_arg]})
    return typed_value(:i64, btemp)
  sig = digits_txt.to_i()
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
  # Map type name to element bits.
  # Extended bits carry signed/float-ish element identity in the runtime.
  # Bits == 65 is the w64 sentinel (64-bit WValue storage, no int coercion).
  bits = 0
  if etype == "bool" || etype == "u1" || etype == "i1"
    # 1-bit packed array. `bool[N]` follows the same fixed-size,
    # zero-filled T[N] contract as every other typed-array literal.
    # BoolArray.new(N) deliberately remains the capacity-N, size-zero
    # push-to-fill constructor.
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
  elsif etype == "u32"
    bits = 32
  elsif etype == "i32"
    bits = 33
  elsif etype == "u64"
    bits = 64
  elsif etype == "i64"
    bits = 66
  elsif etype == "f32"
    bits = -32
  elsif etype == "f16"
    bits = -16
  elsif etype == "bf16"
    bits = -116
  elsif etype == "w64"
    bits = 65
  elsif etype == "f64"
    bits = -64

  if bits != 0
    # Non-escaping, non-resized `i32[N]` (N<=255) → stack WSmallArray, matching
    # the SmallArray.new stack path. infer_type surfaces the small_array_* type
    # for the same node so element access uses the small_array inline ops.
    if typed_array_new_stack_promoted?(node)
      size_const = ast_get(node, :size).value
      payload_bytes = small_array_payload_bytes(bits, size_const)
      total_bytes = 2 + payload_bytes
      temp_ptr = next_temp(wfn)
      temp_int = next_temp(wfn)
      temp_box = next_temp(wfn)
      emit_instruction(wfn, {op: :small_array_alloca, temp_ptr: temp_ptr, total_bytes: total_bytes})
      emit_instruction(wfn, {op: :ptr_to_i64, temp: temp_int, value: temp_ptr})
      emit_instruction(wfn, {op: :call_direct_i64, temp: temp_box, name: "w_small_array_init", args: [temp_int, bits.to_s(), size_const.to_s()]})
      return typed_value(:i64, temp_box)
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

  # The lexer types more names than the runtime has storage for (fp8,
  # fp4, i128, …). The old fallback silently emitted an EMPTY untyped array
  # here — dropping both the size and the element type, and later writes
  # produced slots even w_value_compare couldn't order. Error until the
  # format is actually implemented.
  raise compile_error_for_node(:E_LOWER_TYPED_ARRAY_UNSUPPORTED, "typed array element type '" + etype + "' is not supported yet (supported: u1/i1/u4/i4/u8/i8/u16/i16/u32/i32/u64/i64/f16/f32/f64/bf16/w64/bool)", ctx[:source_path], node)

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
    "A/m²" => 656
    "AU tbsp" => 605
    "Ah" => 728
    "Apgar" => 801
    "B" => 89
    "B/flop" => 680
    "B/s" => 783
    "BOE" => 535
    "BPM" => 804
    "BTU" => 373
    "Ba" => 359
    "Beaufort" => 795
    "Bortle" => 794
    "Bps" => 396
    "Bq" => 23
    "Bq/kg" => 759
    "Bq/m³" => 760
    "C" => 12
    "C/m³" => 659
    "CFU" => 718
    "CFU/mL" => 722
    "CFUs" => 718
    "CWT" => 293
    "Ci" => 380
    "D" => 484
    "DMIPS" => 836
    "DU" => 767
    "DWORD" => 609
    "Da" => 296
    "E" => 772
    "EA" => 1030
    "EB" => 1060
    "EBps" => 1062
    "EBq" => 1050
    "EC" => 1042
    "EDa" => 1057
    "EF" => 798
    "EF-scale" => 798
    "EFLOPS" => 822
    "EGy" => 1051
    "EH" => 1044
    "EHz" => 1041
    "EJ" => 1038
    "EJy" => 1034
    "EK" => 1031
    "EL" => 1054
    "EN" => 1037
    "EOPS" => 833
    "EPa" => 1040
    "ES" => 1045
    "ESv" => 1052
    "ET" => 1047
    "EV" => 616
    "EVA" => 1036
    "EW" => 1039
    "EWb" => 1046
    "Eb" => 1059
    "Ebps" => 1061
    "Ecd" => 1033
    "Ecentury" => 1065
    "EeV" => 1056
    "Eflops" => 821
    "Efortnight" => 1064
    "Eg" => 1028
    "Eh" => 588
    "EiB" => 394
    "Eib" => 1887
    "Ekat" => 1053
    "El" => 1055
    "Elm" => 1048
    "Elx" => 1049
    "Em" => 1027
    "Emol" => 1032
    "Eotvos" => 772
    "Epc" => 1063
    "Eq" => 709
    "Eq/L" => 710
    "Es" => 1029
    "Et" => 1058
    "Evar" => 1035
    "Eötvös" => 772
    "EΩ" => 1043
    "F" => 14
    "F-scale" => 797
    "F/m" => 104
    "FLOPS" => 810
    "FPS" => 805
    "Fr_catheter" => 641
    "GA" => 1147
    "GB" => 92
    "GB/s" => 787
    "GBps" => 1175
    "GBq" => 1165
    "GC" => 1156
    "GDa" => 1172
    "GF" => 1158
    "GFLOPS" => 816
    "GGy" => 1166
    "GH" => 1159
    "GHz" => 43
    "GIPS" => 835
    "GJ" => 47
    "GJy" => 1151
    "GK" => 1148
    "GL" => 1169
    "GMAC/s" => 839
    "GN" => 1154
    "GOPS" => 830
    "GPa" => 59
    "GS" => 1160
    "GSv" => 1167
    "GT" => 1162
    "GT/s" => 847
    "GUPS" => 860
    "GV" => 1155
    "GVA" => 1153
    "GW" => 50
    "GWb" => 1161
    "Ga" => 379
    "Gal" => 389
    "Gb" => 483
    "Gb/s" => 785
    "Gbps" => 1174
    "Gcd" => 1150
    "Gcentury" => 1178
    "GeV" => 1171
    "Gflops" => 815
    "Gfortnight" => 1177
    "Gg" => 1145
    "GiB" => 97
    "GiB/s" => 789
    "Gib" => 1884
    "Gkat" => 1168
    "Gl" => 1170
    "Glm" => 1163
    "Glx" => 1164
    "Gm" => 1144
    "Gmol" => 1149
    "Gpc" => 1176
    "Gs" => 1146
    "Gt" => 1173
    "Gtok/s" => 844
    "Gvar" => 1152
    "Gy" => 24
    "Gy/s" => 757
    "GΩ" => 1157
    "H" => 19
    "HB" => 492
    "HRC" => 491
    "HU" => 803
    "HV" => 490
    "Hz" => 7
    "IOPS" => 858
    "ISO" => 618
    "ISO sensitivity" => 618
    "ISO_speed" => 618
    "IU" => 717
    "IU/mL" => 726
    "J" => 10
    "J/(kg·K)" => 652
    "J/(mol·K)" => 103
    "J/K" => 102
    "J/kg" => 664
    "J/kg/K" => 652
    "J/m²" => 750
    "J/m³" => 663
    "J/op" => 678
    "J/tok" => 679
    "Jy" => 470
    "J·s" => 99
    "K" => 4
    "KB" => 90
    "KOPS" => 828
    "KiB" => 95
    "Kib" => 1882
    "L" => 78
    "L per 100 km" => 529
    "L/100km" => 529
    "L/min" => 648
    "LT" => 295
    "L_sun_nominal" => 765
    "La" => 430
    "L☉_N" => 765
    "M" => 697
    "MA" => 1182
    "MAC/s" => 837
    "MB" => 91
    "MB/s" => 786
    "MBps" => 1210
    "MBq" => 1199
    "MC" => 1190
    "MDa" => 1206
    "MF" => 1192
    "MFLOPS" => 814
    "MGy" => 1200
    "MH" => 1193
    "MHz" => 42
    "MIPS" => 834
    "MJ" => 46
    "MJy" => 1186
    "MK" => 1183
    "ML" => 1203
    "MMAC/s" => 838
    "MN" => 1189
    "MOPS" => 829
    "MPG" => 527
    "MPGe" => 528
    "MPa" => 58
    "MS" => 1194
    "MSv" => 1201
    "MT" => 1196
    "MT/s" => 846
    "MV" => 56
    "MVA" => 1188
    "MW" => 49
    "MWb" => 1195
    "MWh" => 52
    "M_bol" => 473
    "Mach at 20 C" => 696
    "Mach in air at 20 C" => 696
    "Mag" => 472
    "Mb" => 1208
    "Mb/s" => 784
    "Mbol" => 473
    "Mbps" => 1209
    "Mcd" => 1185
    "Mcentury" => 1213
    "MeV" => 1205
    "Mflops" => 813
    "Mfortnight" => 1212
    "Mg" => 1180
    "MiB" => 96
    "MiB/s" => 788
    "Mib" => 1883
    "Mkat" => 1202
    "Ml" => 1204
    "Mlm" => 1197
    "Mlx" => 1198
    "Mm" => 1179
    "Mmol" => 1184
    "Mohs" => 489
    "Mpc" => 1211
    "Ms" => 1181
    "Mt" => 1207
    "Mtok/s" => 843
    "Mvar" => 1187
    "Mw" => 800
    "Mx" => 426
    "MΩ" => 1191
    "M⊕" => 403
    "M☉" => 402
    "M☽" => 405
    "M♃" => 404
    "N" => 8
    "N/A²" => 105
    "N/m" => 660
    "N·m" => 676
    "N·s" => 675
    "Oe" => 482
    "Osm/L" => 713
    "P" => 398
    "PA" => 1069
    "PB" => 94
    "PBps" => 1101
    "PBq" => 1090
    "PC" => 1082
    "PDa" => 1097
    "PF" => 1084
    "PFLOPS" => 820
    "PFU" => 719
    "PFU/mL" => 723
    "PFUs" => 719
    "PGy" => 1091
    "PH" => 1085
    "PHz" => 1080
    "PJ" => 1077
    "PJy" => 1073
    "PK" => 1070
    "PL" => 1094
    "PN" => 1076
    "POPS" => 832
    "PPFD" => 754
    "PPS" => 856
    "PPa" => 1079
    "PS" => 378
    "PSv" => 1092
    "PT" => 1087
    "PV" => 1081
    "PVA" => 1075
    "PVU" => 768
    "PW" => 1078
    "PWb" => 1086
    "Pa" => 9
    "Pb" => 1099
    "Pbps" => 1100
    "Pcd" => 1072
    "Pcentury" => 1104
    "PeV" => 1096
    "Pflops" => 819
    "Pfortnight" => 1103
    "Pg" => 1067
    "PiB" => 393
    "Pib" => 1886
    "Pkat" => 1093
    "Pl" => 1095
    "Planck length" => 287
    "Planck mass" => 299
    "Planck time" => 326
    "Plm" => 1088
    "Plx" => 1089
    "Pm" => 1066
    "Pmol" => 1071
    "Ppc" => 1102
    "Ps" => 1068
    "Pt" => 1098
    "Pvar" => 1074
    "PΩ" => 1083
    "QA" => 866
    "QALY" => 692
    "QALYs" => 692
    "QB" => 898
    "QBps" => 900
    "QBq" => 888
    "QC" => 879
    "QDa" => 895
    "QF" => 881
    "QGy" => 889
    "QH" => 882
    "QHz" => 877
    "QJ" => 874
    "QJy" => 870
    "QK" => 867
    "QL" => 892
    "QN" => 873
    "QPS" => 850
    "QPa" => 876
    "QS" => 883
    "QSv" => 890
    "QT" => 885
    "QV" => 878
    "QVA" => 872
    "QW" => 875
    "QWORD" => 610
    "QWb" => 884
    "Qb" => 897
    "Qbps" => 899
    "Qcd" => 869
    "Qcentury" => 903
    "QeV" => 894
    "Qfortnight" => 902
    "Qg" => 864
    "QiB" => 1895
    "Qib" => 1894
    "Qkat" => 891
    "Ql" => 893
    "Qlm" => 886
    "Qlx" => 887
    "Qm" => 863
    "Qmol" => 868
    "Qpc" => 901
    "Qs" => 865
    "Qt" => 896
    "Qvar" => 871
    "QΩ" => 880
    "RA" => 907
    "RB" => 939
    "RBE" => 802
    "RBps" => 941
    "RBq" => 929
    "RC" => 920
    "RDa" => 936
    "RF" => 922
    "RGy" => 930
    "RH" => 923
    "RHz" => 918
    "RJ" => 915
    "RJy" => 911
    "RK" => 908
    "RL" => 933
    "RN" => 914
    "RPS" => 852
    "RPa" => 917
    "RS" => 924
    "RSv" => 931
    "RT" => 926
    "RU" => 277
    "RV" => 919
    "RVA" => 913
    "RW" => 916
    "RWb" => 925
    "R_exposure" => 756
    "R_sun_nominal" => 764
    "Rb" => 938
    "Rbps" => 940
    "Rcd" => 910
    "Rcentury" => 944
    "ReV" => 935
    "Rfortnight" => 943
    "Rg" => 905
    "RiB" => 1893
    "Rib" => 1892
    "Richter" => 799
    "Rkat" => 932
    "Rl" => 934
    "Rlm" => 927
    "Rlx" => 928
    "Rm" => 904
    "Rmol" => 909
    "Rpc" => 942
    "Rs" => 906
    "Rt" => 937
    "Rvar" => 912
    "Ry" => 589
    "RΩ" => 921
    "R⊕" => 407
    "R☉" => 406
    "R☉_N" => 764
    "S" => 16
    "S/m" => 658
    "SS_category" => 796
    "Saffir-Simpson" => 796
    "St" => 400
    "Sv" => 25
    "Sv/h" => 758
    "Sv_ocean" => 769
    "Svedberg" => 727
    "T" => 18
    "T/s" => 845
    "TA" => 1108
    "TB" => 93
    "TBps" => 1140
    "TBq" => 1129
    "TC" => 1120
    "TCE" => 536
    "TDa" => 1136
    "TECU" => 773
    "TEPS" => 859
    "TF" => 1122
    "TFLOPS" => 818
    "TGy" => 1130
    "TH" => 1123
    "THz" => 44
    "TJ" => 1116
    "TJy" => 1112
    "TK" => 1109
    "TL" => 1133
    "TMAC/s" => 840
    "TN" => 1115
    "TOPS" => 831
    "TPS" => 854
    "TPa" => 1118
    "TS" => 1124
    "TSv" => 1131
    "TT" => 1126
    "TT/s" => 848
    "TV" => 1119
    "TVA" => 1114
    "TW" => 1117
    "TWb" => 1125
    "Tb" => 1138
    "Tbps" => 1139
    "Tcd" => 1111
    "Tcentury" => 1143
    "TeV" => 1135
    "Tflops" => 817
    "Tfortnight" => 1142
    "Tg" => 1106
    "TiB" => 98
    "Tib" => 1885
    "Tkat" => 1132
    "Tl" => 1134
    "Tlm" => 1127
    "Tlx" => 1128
    "Tm" => 1105
    "Tmol" => 1110
    "Torr" => 113
    "Tpc" => 1141
    "Ts" => 1107
    "Tt" => 1137
    "Tvar" => 1113
    "TΩ" => 1121
    "U/L" => 716
    "U_enzyme" => 715
    "V" => 13
    "V/m" => 655
    "VA" => 730
    "W" => 11
    "W/(m²·K⁴)" => 106
    "W/(m·K)" => 653
    "W/m/K" => 653
    "W/m²" => 654
    "W/m²/Hz" => 748
    "W/m³" => 749
    "W/sr" => 746
    "W/sr/m²" => 747
    "Wb" => 17
    "YA" => 948
    "YB" => 980
    "YBps" => 982
    "YBq" => 970
    "YC" => 961
    "YDa" => 977
    "YF" => 963
    "YFLOPS" => 826
    "YGy" => 971
    "YH" => 964
    "YHz" => 959
    "YJ" => 956
    "YJy" => 952
    "YK" => 949
    "YL" => 974
    "YN" => 955
    "YPa" => 958
    "YS" => 965
    "YSv" => 972
    "YT" => 967
    "YV" => 960
    "YVA" => 954
    "YW" => 957
    "YWb" => 966
    "Yb" => 979
    "Ybps" => 981
    "Ycd" => 951
    "Ycentury" => 985
    "YeV" => 976
    "Yflops" => 825
    "Yfortnight" => 984
    "Yg" => 946
    "YiB" => 1891
    "Yib" => 1890
    "Ykat" => 973
    "Yl" => 975
    "Ylm" => 968
    "Ylx" => 969
    "Ym" => 945
    "Ymol" => 950
    "Ypc" => 983
    "Ys" => 947
    "Yt" => 978
    "Yvar" => 953
    "YΩ" => 962
    "ZA" => 989
    "ZB" => 1021
    "ZBps" => 1023
    "ZBq" => 1011
    "ZC" => 1002
    "ZDa" => 1018
    "ZF" => 1004
    "ZFLOPS" => 824
    "ZGy" => 1012
    "ZH" => 1005
    "ZHz" => 1000
    "ZJ" => 997
    "ZJy" => 993
    "ZK" => 990
    "ZL" => 1015
    "ZN" => 996
    "ZPa" => 999
    "ZS" => 1006
    "ZSv" => 1013
    "ZT" => 1008
    "ZV" => 1001
    "ZVA" => 995
    "ZW" => 998
    "ZWb" => 1007
    "Zb" => 1020
    "Zbps" => 1022
    "Zcd" => 992
    "Zcentury" => 1026
    "ZeV" => 1017
    "Zflops" => 823
    "Zfortnight" => 1025
    "Zg" => 987
    "ZiB" => 1889
    "Zib" => 1888
    "Zkat" => 1014
    "Zl" => 1016
    "Zlm" => 1009
    "Zlx" => 1010
    "Zm" => 986
    "Zmol" => 991
    "Zpc" => 1024
    "Zs" => 988
    "Zt" => 1019
    "Zvar" => 994
    "ZΩ" => 1003
    "a0" => 590
    "aA" => 1682
    "aB" => 1713
    "aBps" => 1715
    "aBq" => 1704
    "aC" => 1695
    "aDa" => 1711
    "aF" => 1697
    "aGy" => 1705
    "aH" => 1698
    "aHz" => 1693
    "aJ" => 1690
    "aJy" => 1686
    "aK" => 1683
    "aL" => 1708
    "aN" => 1689
    "aPa" => 1692
    "aS" => 1699
    "aSv" => 1706
    "aT" => 1701
    "aV" => 1694
    "aVA" => 1688
    "aW" => 1691
    "aWb" => 1700
    "a_0" => 590
    "ab" => 1712
    "ab-1" => 479
    "abA" => 731
    "abC" => 733
    "abF" => 739
    "abH" => 741
    "abV" => 735
    "ab^-1" => 479
    "abampere" => 731
    "abarn" => 475
    "abcoulomb" => 733
    "abfarad" => 739
    "abhenry" => 741
    "abinv" => 479
    "abohm" => 737
    "abps" => 1714
    "absolute magnitude" => 472
    "absorbed-dose rad" => 755
    "abvolt" => 735
    "abΩ" => 737
    "ab⁻¹" => 479
    "ac" => 327
    "acd" => 1685
    "acentury" => 1718
    "acre" => 74
    "acres" => 327
    "aeV" => 1710
    "afortnight" => 1717
    "ag" => 1680
    "akat" => 1707
    "al" => 1709
    "alm" => 1702
    "alpha" => 594
    "altuve" => 413
    "altuves" => 413
    "alx" => 1703
    "am" => 1679
    "amah" => 500
    "amol" => 1684
    "amot" => 500
    "amp hours" => 728
    "ampere" => 3
    "ampere hour" => 728
    "ampere-hour" => 728
    "amperes" => 3
    "amperes per square meter" => 656
    "amphora" => 576
    "amphorae" => 576
    "amphoras" => 576
    "angstrom" => 278
    "angstroms" => 278
    "angular acceleration" => 672
    "angular velocity" => 671
    "apc" => 1716
    "apgar" => 801
    "apgar score" => 801
    "apostilb" => 432
    "apostilbs" => 432
    "apparent magnitude" => 471
    "arcmin" => 383
    "arcsec" => 384
    "areal density" => 662
    "aroura" => 581
    "arourae" => 581
    "arouras" => 581
    "arpent" => 568
    "arpents" => 568
    "arshin" => 559
    "arshins" => 559
    "as" => 1681
    "asb" => 432
    "astronomical unit" => 116
    "astronomical units" => 116
    "at" => 360
    "atm" => 110
    "atmosphere" => 110
    "atmospheres" => 110
    "attobarn" => 475
    "attobarns" => 475
    "au" => 116
    "australian tablespoon" => 605
    "australian tablespoons" => 605
    "australian tbsp" => 605
    "australian_tbsp" => 605
    "avar" => 1687
    "aΩ" => 1696
    "b" => 390
    "baker's dozen" => 497
    "bakers dozen" => 497
    "bakers_dozen" => 497
    "ban" => 462
    "banana" => 421
    "banana for scale" => 645
    "banana_for_scale" => 645
    "bananas" => 421
    "bananas for scale" => 645
    "bar" => 111
    "barleycorn" => 629
    "barleycorns" => 629
    "barn" => 328
    "barn megaparsec" => 420
    "barn-megaparsec" => 420
    "barn-megaparsecs" => 420
    "barns" => 328
    "barrel" => 416
    "barrel of oil equivalent" => 535
    "barrels" => 416
    "barye" => 359
    "basis point" => 623
    "basis points" => 623
    "basis_point" => 623
    "basis_points" => 623
    "bath" => 510
    "baths" => 510
    "baud" => 397
    "beard second" => 419
    "beard seconds" => 419
    "beard-second" => 419
    "beard-seconds" => 419
    "beat" => 439
    "beats" => 439
    "beats per minute" => 804
    "beaufort" => 795
    "becquerel" => 23
    "becquerels" => 23
    "beka" => 518
    "bekah" => 518
    "bekas" => 518
    "biblical talent" => 516
    "biblical_mil" => 504
    "biblical_mina" => 515
    "biblical_talent" => 516
    "billions and billions" => 643
    "biot" => 731
    "bit" => 88
    "bit/(s·Hz)" => 677
    "bit/s" => 782
    "bit/s/Hz" => 677
    "bit/symbol" => 790
    "bits" => 390
    "bits per second per hertz" => 677
    "bits per symbol" => 790
    "block" => 614
    "blocks" => 614
    "boe" => 535
    "bohr magneton" => 485
    "bohr_magneton" => 485
    "bohr_radius" => 590
    "boiler horsepower" => 599
    "boiler_horsepower" => 599
    "bolometric magnitude" => 473
    "bortle" => 794
    "bottle" => 353
    "bottles" => 353
    "bp_finance" => 623
    "bpm" => 804
    "bps" => 395
    "brad" => 388
    "brads" => 388
    "brinell" => 492
    "bu" => 335
    "bushel" => 335
    "bushels" => 335
    "butt" => 349
    "byte" => 89
    "bytes" => 89
    "bytes per flop" => 680
    "cA" => 1372
    "cB" => 1403
    "cBps" => 1405
    "cBq" => 1394
    "cC" => 1385
    "cDa" => 1401
    "cF" => 1387
    "cGy" => 1395
    "cH" => 1388
    "cHz" => 1383
    "cJ" => 1380
    "cJy" => 1376
    "cK" => 1373
    "cL" => 1398
    "cN" => 1379
    "cP" => 399
    "cPa" => 1382
    "cS" => 1389
    "cSt" => 401
    "cSv" => 1396
    "cT" => 1391
    "cV" => 1384
    "cVA" => 1378
    "cW" => 1381
    "cWb" => 1390
    "cable" => 280
    "cable length" => 633
    "cable lengths" => 633
    "cable_length" => 633
    "cables" => 280
    "cal" => 108
    "cal_IT" => 369
    "cal_th" => 370
    "calorie" => 108
    "calorie IT" => 369
    "calories" => 108
    "candela" => 6
    "candela per square meter" => 668
    "candelas" => 6
    "carat" => 306
    "carats" => 306
    "catalytic activity concentration" => 667
    "cb" => 1402
    "cbps" => 1404
    "ccd" => 1375
    "ccentury" => 1408
    "cd" => 6
    "cd/m²" => 668
    "ceV" => 1400
    "cell" => 720
    "cells" => 720
    "cells/mL" => 724
    "celsius" => 20
    "celsius difference" => 263
    "cent" => 619
    "cent_pitch" => 619
    "centipoise" => 399
    "centistokes" => 401
    "cents" => 619
    "centuries" => 317
    "century" => 317
    "cfortnight" => 1407
    "cg" => 1370
    "ch" => 273
    "chain" => 273
    "chains" => 273
    "charge density" => 659
    "chelakim" => 519
    "chelek" => 519
    "chetvert" => 564
    "chetverts" => 564
    "chi" => 549
    "chinese dan" => 557
    "chinese li" => 553
    "chinese_dan" => 557
    "chinese_li" => 553
    "chis" => 549
    "cicero" => 412
    "ckat" => 1397
    "cl" => 1399
    "clm" => 1392
    "clo" => 775
    "clo unit" => 775
    "cloth nail" => 632
    "cluster" => 615
    "clusters" => 615
    "clx" => 1393
    "cm" => 28
    "cm-1" => 488
    "cmH2O" => 365
    "cm^-1" => 488
    "cmol" => 1374
    "cm²" => 71
    "cm³" => 77
    "cm⁻¹" => 488
    "colony forming unit" => 718
    "colony-forming unit" => 718
    "compton wavelength" => 591
    "compton wavelength electron" => 591
    "compton wavelength neutron" => 593
    "compton wavelength proton" => 592
    "compton_e" => 591
    "compton_n" => 593
    "compton_p" => 592
    "compton_wavelength" => 591
    "conductivity" => 658
    "copies" => 721
    "copies/mL" => 725
    "copy" => 721
    "cord" => 418
    "cords" => 418
    "coulomb" => 12
    "coulombs" => 12
    "coulombs per cubic meter" => 659
    "count" => 761
    "counts per minute" => 808
    "counts per second" => 807
    "cpc" => 1406
    "cpm" => 808
    "cps" => 807
    "crumb" => 608
    "crumbs" => 608
    "cs" => 1371
    "css rem" => 688
    "ct" => 306
    "cubic meters per second" => 647
    "cubit" => 500
    "cubits" => 500
    "cun" => 550
    "cuns" => 550
    "cup" => 330
    "cups" => 330
    "curie" => 380
    "curies" => 380
    "current density" => 656
    "cvar" => 1377
    "cwt" => 292
    "cyc" => 440
    "cycle" => 440
    "cycles" => 440
    "cΩ" => 1386
    "d" => 310
    "dA" => 1332
    "dB" => 1364
    "dBps" => 1366
    "dBq" => 1354
    "dC" => 1345
    "dDa" => 1361
    "dF" => 1347
    "dGy" => 1355
    "dH" => 1348
    "dHz" => 1343
    "dJ" => 1340
    "dJy" => 1336
    "dK" => 1333
    "dL" => 1358
    "dN" => 1339
    "dPa" => 1342
    "dS" => 1349
    "dSv" => 1356
    "dT" => 1351
    "dV" => 1344
    "dVA" => 1338
    "dW" => 1341
    "dWb" => 1350
    "daA" => 1291
    "daB" => 1323
    "daBps" => 1325
    "daBq" => 1313
    "daC" => 1304
    "daDa" => 1320
    "daF" => 1306
    "daGy" => 1314
    "daH" => 1307
    "daHz" => 1302
    "daJ" => 1299
    "daJy" => 1295
    "daK" => 1292
    "daL" => 1317
    "daN" => 1298
    "daPa" => 1301
    "daS" => 1308
    "daSv" => 1315
    "daT" => 1310
    "daV" => 1303
    "daVA" => 1297
    "daW" => 1300
    "daWb" => 1309
    "dab" => 1322
    "dabps" => 1324
    "dacd" => 1294
    "dacentury" => 1328
    "daeV" => 1319
    "dafortnight" => 1327
    "dag" => 1289
    "dakat" => 1316
    "dal" => 1318
    "dalm" => 1311
    "dalton" => 296
    "daltons" => 296
    "dalx" => 1312
    "dam" => 1288
    "damol" => 1293
    "dan_cn" => 557
    "dapc" => 1326
    "darcies" => 770
    "darcy" => 770
    "das" => 1290
    "dash" => 340
    "dashes" => 340
    "dat" => 1321
    "davar" => 1296
    "day" => 310
    "days" => 310
    "daΩ" => 1305
    "db" => 1363
    "dbps" => 1365
    "dcd" => 1335
    "dcentury" => 1369
    "deV" => 1360
    "debye" => 484
    "debyes" => 484
    "decade" => 314
    "decades" => 314
    "decay" => 448
    "decays" => 448
    "decays per minute" => 806
    "deciban" => 463
    "decibans" => 463
    "decitex" => 640
    "deg" => 382
    "degree" => 382
    "degrees" => 382
    "delisle" => 257
    "delta celsius" => 263
    "delta fahrenheit" => 264
    "delta kelvin" => 262
    "delta rankine" => 265
    "denier" => 638
    "deniers" => 638
    "dfortnight" => 1368
    "dg" => 1330
    "didot" => 411
    "digit" => 579
    "digits" => 579
    "diopter" => 745
    "diopters" => 745
    "dioptre" => 745
    "dioptres" => 745
    "dit" => 462
    "dits" => 462
    "dkat" => 1357
    "dl" => 1359
    "dlm" => 1352
    "dlx" => 1353
    "dm" => 1329
    "dmol" => 1334
    "dobson unit" => 767
    "dobson units" => 767
    "dog year" => 325
    "dog years" => 325
    "dogyear" => 325
    "donkey power" => 602
    "donkey-power" => 602
    "donkeypower" => 602
    "dots per inch" => 686
    "dots per pixel" => 687
    "dozen" => 493
    "dozens" => 493
    "dpc" => 1367
    "dpi" => 686
    "dpm" => 806
    "dppx" => 687
    "dr" => 289
    "drachm" => 289
    "drams" => 289
    "drop" => 339
    "drops" => 339
    "ds" => 1331
    "dt" => 1362
    "dvar" => 1337
    "dword" => 609
    "dwords" => 609
    "dwt" => 305
    "dyn" => 376
    "dyne" => 376
    "dynes" => 376
    "dΩ" => 1346
    "eV" => 107
    "earth mass" => 403
    "earth radius" => 407
    "earthmass" => 403
    "earthradius" => 407
    "edge" => 780
    "edges" => 780
    "egypt_palm" => 578
    "egyptian palm" => 578
    "egyptian palms" => 578
    "einstein" => 752
    "einsteins" => 752
    "electric field" => 655
    "electric horsepower" => 600
    "electric_horsepower" => 600
    "electron mass" => 595
    "electron_mass" => 595
    "electronvolt" => 107
    "electronvolts" => 107
    "em" => 434
    "en" => 435
    "energy density" => 663
    "english cubit" => 631
    "english cubits" => 631
    "english_cubit" => 631
    "enhanced fujita" => 798
    "entropy" => 651
    "enzyme unit" => 715
    "enzyme units" => 715
    "eotvos" => 772
    "ephah" => 508
    "ephahs" => 508
    "ephas" => 508
    "equivalent" => 709
    "equivalents" => 709
    "erg" => 368
    "etzba" => 503
    "etzbaot" => 503
    "ev" => 616
    "e₀" => 118
    "f stop" => 617
    "f-stop" => 617
    "f-stops" => 617
    "fA" => 1643
    "fB" => 1673
    "fBps" => 1675
    "fBq" => 1665
    "fC" => 1656
    "fDa" => 1671
    "fF" => 1658
    "fGy" => 1666
    "fH" => 1659
    "fHz" => 1654
    "fJ" => 1651
    "fJy" => 1647
    "fK" => 1644
    "fL" => 431
    "fN" => 1650
    "fPa" => 1653
    "fS" => 1660
    "fSv" => 1667
    "fT" => 1662
    "fV" => 1655
    "fVA" => 1649
    "fW" => 1652
    "fWb" => 1661
    "f_stop" => 617
    "fahrenheit" => 87
    "fahrenheit difference" => 264
    "farad" => 14
    "farads" => 14
    "fathom" => 279
    "fathoms" => 279
    "fb" => 1672
    "fb-1" => 478
    "fb^-1" => 478
    "fbarn" => 474
    "fbinv" => 478
    "fbps" => 1674
    "fb⁻¹" => 478
    "fc" => 744
    "fcd" => 1646
    "fcentury" => 1678
    "feV" => 1670
    "feet" => 61
    "feet of water" => 636
    "femtobarn" => 474
    "femtobarns" => 474
    "fen" => 551
    "fens" => 551
    "ffortnight" => 1677
    "fg" => 1641
    "fine structure constant" => 594
    "fine_structure" => 594
    "fingerbreadth" => 503
    "firkin" => 344
    "firkins" => 344
    "fkat" => 1668
    "fl" => 1669
    "fl dr" => 333
    "fl oz" => 66
    "fldr" => 333
    "flm" => 1663
    "flop" => 450
    "flop/J" => 791
    "flops" => 809
    "flops per joule" => 791
    "flops_count" => 450
    "floz" => 332
    "fluid dram" => 333
    "fluid drams" => 333
    "fluid ounce" => 332
    "fluid ounces" => 332
    "flx" => 1664
    "fm" => 1640
    "fmol" => 1645
    "foe" => 766
    "foes" => 766
    "foot" => 61
    "foot candle" => 744
    "foot candles" => 744
    "foot of water" => 636
    "foot pound" => 375
    "foot pounds" => 375
    "foot-candle" => 744
    "foot-lambert" => 431
    "foot-pound" => 375
    "foot-pounds" => 375
    "fortnight" => 316
    "fortnights" => 316
    "fpc" => 1676
    "fps" => 805
    "frame" => 441
    "frames" => 441
    "frames per second" => 805
    "franklin" => 734
    "french gauge" => 641
    "french_gauge" => 641
    "fs" => 1642
    "fstop" => 617
    "ft" => 61
    "ft H2O" => 636
    "ft of water" => 636
    "ftH2O" => 636
    "ftlbf" => 375
    "ft²" => 75
    "fujita" => 797
    "fujita scale" => 797
    "funt" => 563
    "funt_ru" => 563
    "fur" => 271
    "furlong" => 271
    "furlongs" => 271
    "fvar" => 1648
    "fΩ" => 1657
    "g" => 33
    "g CO2e" => 682
    "g/L" => 703
    "g/dL" => 706
    "g0" => 524
    "gCO₂e" => 682
    "gCO₂e/kWh" => 683
    "gCO₂e/pkm" => 684
    "g_n" => 525
    "gal" => 67
    "gallon" => 67
    "gallons" => 67
    "gauss" => 379
    "gaz" => 583
    "gazes" => 583
    "gee" => 526
    "geopotential meter" => 774
    "geopotential metre" => 774
    "gerah" => 517
    "gerahs" => 517
    "giga-updates per second" => 860
    "gigaton" => 533
    "gigatons" => 533
    "gilbert" => 483
    "gilberts" => 483
    "gill" => 331
    "gills" => 331
    "gon" => 385
    "googol" => 498
    "googolplex" => 499
    "googolplexes" => 499
    "googols" => 498
    "gos" => 546
    "gpm" => 774
    "gr" => 288
    "grad" => 385
    "gradian" => 385
    "gradians" => 385
    "grain" => 288
    "grains" => 288
    "gram" => 33
    "grams" => 33
    "grams CO2e" => 682
    "grape jelly" => 438
    "grave" => 1
    "gray" => 24
    "grays" => 24
    "great gross" => 495
    "great_gross" => 495
    "grid carbon intensity" => 683
    "gross" => 494
    "gō" => 546
    "g₀" => 524
    "h" => 309
    "hA" => 1250
    "hB" => 1282
    "hBps" => 1284
    "hBq" => 1272
    "hC" => 1263
    "hDa" => 1279
    "hF" => 1265
    "hGy" => 1273
    "hH" => 1266
    "hHz" => 1261
    "hJ" => 1258
    "hJy" => 1254
    "hK" => 1251
    "hL" => 1276
    "hN" => 1257
    "hPa" => 1260
    "hS" => 1267
    "hSv" => 1274
    "hT" => 1269
    "hV" => 1262
    "hVA" => 1256
    "hW" => 1259
    "hWb" => 1268
    "ha" => 73
    "halakim" => 519
    "half step" => 620
    "halfstep" => 620
    "hand" => 275
    "handbreadth" => 502
    "handbreadths" => 502
    "hands" => 275
    "hartley" => 462
    "hartleys" => 462
    "hartree" => 588
    "hartrees" => 588
    "hath" => 582
    "haths" => 582
    "hb" => 1281
    "hbps" => 1283
    "hcd" => 1253
    "hcentury" => 1287
    "heV" => 1278
    "heap" => 537
    "heaps" => 537
    "heat capacity" => 650
    "heat flux" => 654
    "heat_capacity" => 650
    "hectare" => 73
    "hectares" => 73
    "helek" => 519
    "henries" => 19
    "henry" => 19
    "henrys" => 19
    "hertz" => 7
    "hfortnight" => 1286
    "hg" => 1248
    "hin" => 509
    "hins" => 509
    "hkat" => 1275
    "hl" => 1277
    "hlm" => 1270
    "hlx" => 1271
    "hm" => 1247
    "hmol" => 1252
    "hogshead" => 347
    "hogsheads" => 347
    "hole" => 538
    "holes" => 538
    "horsepower" => 377
    "hounsfield" => 803
    "hounsfield_unit" => 803
    "hour" => 309
    "hours" => 309
    "hp" => 377
    "hpc" => 1285
    "hs" => 1249
    "ht" => 1280
    "hvar" => 1255
    "hΩ" => 1264
    "imp gal" => 334
    "imperial bottle" => 356
    "imperial gallon" => 334
    "imperial gallons" => 334
    "imperial pint" => 607
    "imperial pints" => 607
    "imperial_pint" => 607
    "impgal" => 334
    "impulse" => 675
    "in" => 60
    "in H2O" => 635
    "in of water" => 635
    "inH2O" => 635
    "inHg" => 364
    "inch" => 60
    "inch of water" => 635
    "inches" => 60
    "inches of water" => 635
    "indian kos" => 584
    "instant" => 442
    "instants" => 442
    "instruction" => 453
    "instructions" => 453
    "international table calorie" => 369
    "international unit" => 717
    "international units" => 717
    "inv_ab" => 479
    "inv_fb" => 478
    "inv_nb" => 481
    "inv_pb" => 480
    "inverse attobarn" => 479
    "inverse femtobarn" => 478
    "inverse nanobarn" => 481
    "inverse picobarn" => 480
    "io" => 460
    "io_op" => 460
    "io_ops" => 460
    "iops" => 857
    "ios" => 460
    "isaron" => 507
    "iso" => 618
    "issaron" => 507
    "iugera" => 573
    "iugerum" => 573
    "j" => 438
    "jam" => 438
    "janskies" => 470
    "jansky" => 470
    "janskys" => 470
    "japanese cup" => 606
    "japanese cups" => 606
    "japanese_cup" => 606
    "jelly" => 438
    "jerk" => 673
    "jeroboam" => 355
    "jeroboams" => 355
    "jiffies" => 443
    "jiffy" => 443
    "jigger" => 343
    "jiggers" => 343
    "jin" => 555
    "jins" => 555
    "jo" => 542
    "jos" => 542
    "joule" => 10
    "joules" => 10
    "joules per kelvin" => 102
    "joules per operation" => 678
    "joules per token" => 679
    "jubilee" => 522
    "jubilees" => 522
    "jugerum" => 573
    "julian year" => 321
    "julian years" => 321
    "julianyear" => 321
    "jupiter mass" => 404
    "jupitermass" => 404
    "kA" => 1215
    "kB" => 1241
    "kBps" => 1243
    "kBq" => 1232
    "kC" => 1223
    "kDa" => 1239
    "kF" => 1225
    "kFLOPS" => 812
    "kGy" => 1233
    "kH" => 1226
    "kHz" => 41
    "kJ" => 45
    "kJy" => 1219
    "kK" => 1216
    "kL" => 1236
    "kN" => 1222
    "kPa" => 57
    "kS" => 1227
    "kSv" => 1234
    "kT" => 1229
    "kV" => 55
    "kVA" => 1221
    "kW" => 48
    "kWb" => 1228
    "kWh" => 51
    "kab" => 513
    "kabim" => 513
    "kabs" => 513
    "kanme" => 548
    "kanmes" => 548
    "kat" => 26
    "kat/m³" => 667
    "katal" => 26
    "katals" => 26
    "kayser" => 488
    "kaysers" => 488
    "kb" => 1240
    "kbps" => 1242
    "kcal" => 109
    "kcal_IT" => 371
    "kcal_th" => 372
    "kcd" => 1218
    "kcentury" => 1246
    "keV" => 1238
    "kelvin" => 4
    "kelvin difference" => 262
    "kflops" => 811
    "kfortnight" => 1245
    "kg" => 1
    "kg CO2e" => 681
    "kg/m" => 661
    "kg/m²" => 662
    "kg/m³" => 646
    "kg/s" => 649
    "kgCO₂e" => 681
    "kgf" => 367
    "kg·m/s" => 674
    "khet" => 580
    "khets" => 580
    "kikar" => 516
    "kilderkin" => 351
    "kilderkins" => 351
    "kilocalorie" => 109
    "kilocalories" => 109
    "kilogram" => 1
    "kilogram force" => 367
    "kilogram-force" => 367
    "kilograms" => 1
    "kilograms CO2e" => 681
    "kilograms per cubic meter" => 646
    "kilograms per second" => 649
    "kiloton" => 531
    "kilotons" => 531
    "kilowarhol" => 423
    "kilowarhols" => 423
    "kilowatt hour" => 51
    "kilowatt hours" => 51
    "kilowatt-hour" => 51
    "kilowatt-hours" => 51
    "kkat" => 1235
    "kl" => 1237
    "klm" => 1230
    "klx" => 1231
    "km" => 27
    "km/h" => 81
    "kmol" => 1217
    "km²" => 72
    "kn" => 281
    "knot" => 281
    "knots" => 281
    "koku" => 545
    "kokus" => 545
    "kor" => 512
    "korim" => 512
    "kors" => 512
    "kos" => 584
    "kos_indian" => 584
    "kpc" => 1244
    "kph" => 282
    "ks" => 1214
    "kt" => 281
    "ktok/s" => 842
    "kvar" => 1220
    "kΩ" => 1224
    "l" => 329
    "l/100km" => 529
    "lambert" => 430
    "lamberts" => 430
    "lb" => 65
    "lbf" => 366
    "lbs" => 119
    "league" => 276
    "leagues" => 276
    "li_cn" => 553
    "liang" => 556
    "liangs" => 556
    "libra romana" => 574
    "libra_roma" => 574
    "lieue de poste" => 569
    "lieue_de_poste" => 569
    "lieues de poste" => 569
    "light hour" => 286
    "light hours" => 286
    "light minute" => 285
    "light minutes" => 285
    "light nanosecond" => 644
    "light second" => 284
    "light seconds" => 284
    "light year" => 115
    "light years" => 115
    "light-nanosecond" => 644
    "light_nanosecond" => 644
    "lighthour" => 286
    "lighthours" => 286
    "lightminute" => 285
    "lightminutes" => 285
    "lightsecond" => 284
    "lightseconds" => 284
    "lightyear" => 115
    "lightyears" => 115
    "linear density" => 661
    "link" => 626
    "link_chain" => 626
    "links" => 626
    "liter" => 78
    "liters" => 78
    "liters per 100 km" => 529
    "liters per minute" => 648
    "litre" => 78
    "litres" => 78
    "litres per minute" => 648
    "lm" => 21
    "lm·s" => 670
    "long ton" => 295
    "long tons" => 295
    "lumen" => 21
    "lumens" => 21
    "luminous energy" => 670
    "luminous exposure" => 669
    "lunar month" => 323
    "lunar months" => 323
    "lunarmonth" => 323
    "lustra" => 324
    "lustrum" => 324
    "lustrums" => 324
    "lux" => 22
    "lx" => 22
    "lx·s" => 669
    "ly" => 115
    "m" => 0
    "m H2O" => 634
    "m of water" => 634
    "m/s" => 80
    "m/s²" => 83
    "m/s³" => 673
    "mA" => 53
    "mB" => 1439
    "mBps" => 1441
    "mBq" => 1430
    "mC" => 1421
    "mDa" => 1436
    "mEq/L" => 711
    "mF" => 1423
    "mGal" => 771
    "mGy" => 1431
    "mH" => 1424
    "mH2O" => 634
    "mHz" => 1419
    "mJ" => 1416
    "mJy" => 1412
    "mK" => 1409
    "mL" => 79
    "mM" => 699
    "mN" => 1415
    "mOsm/L" => 714
    "mPa" => 1418
    "mS" => 1425
    "mSv" => 1432
    "mT" => 1427
    "mV" => 1420
    "mVA" => 1414
    "mW" => 1417
    "mWb" => 1426
    "m_e" => 595
    "m_n" => 597
    "m_p" => 596
    "m_μ" => 598
    "mac" => 452
    "mach" => 283
    "mach_air_20C" => 696
    "macs" => 452
    "mag" => 471
    "magnitude" => 471
    "magnitudes" => 471
    "magnum" => 354
    "magnums" => 354
    "maneh" => 515
    "mas" => 762
    "mass density" => 646
    "mass flow" => 649
    "maund" => 587
    "maunds" => 587
    "maxwell" => 426
    "maxwells" => 426
    "mb" => 1438
    "mbar" => 112
    "mbps" => 1440
    "mcd" => 1411
    "mcentury" => 1444
    "meV" => 1435
    "megaton" => 532
    "megatons" => 532
    "melchizedek" => 358
    "melchizedeks" => 358
    "meter" => 0
    "meter of water" => 634
    "meters" => 0
    "meters of water" => 634
    "methuselah" => 356
    "methuselahs" => 356
    "metric cup" => 603
    "metric cups" => 603
    "metric tablespoon" => 604
    "metric tablespoons" => 604
    "metric tbsp" => 604
    "metric ton" => 36
    "metric tons" => 36
    "metric_cup" => 603
    "metric_tbsp" => 604
    "mfortnight" => 1443
    "mg" => 34
    "mg/L" => 704
    "mg/dL" => 705
    "mg/dL glucose" => 694
    "mg/dL_glucose" => 694
    "mho" => 16
    "mi" => 63
    "mi/h" => 122
    "mickey" => 642
    "mickeys" => 642
    "microarcsecond" => 763
    "microarcseconds" => 763
    "microlife" => 487
    "microlives" => 487
    "micromolar" => 700
    "micromort" => 486
    "micromorts" => 486
    "mil" => 387
    "mile" => 63
    "mile per hour" => 82
    "miles" => 63
    "miles per gallon" => 527
    "miles per gallon equivalent" => 528
    "miles per hour" => 82
    "mill_finance" => 624
    "mille passuum" => 572
    "mille_passuum" => 572
    "millennia" => 315
    "millennium" => 315
    "millenniums" => 315
    "milliarcsecond" => 762
    "milliarcseconds" => 762
    "milligal" => 771
    "milligals" => 771
    "millihelen" => 427
    "millihelens" => 427
    "millimolar" => 699
    "mils" => 387
    "min" => 308
    "mina" => 515
    "minas" => 515
    "minute" => 308
    "minutes" => 308
    "mkat" => 1433
    "ml" => 1434
    "mlm" => 1428
    "mlx" => 1429
    "mm" => 29
    "mmHg" => 363
    "mmol" => 1410
    "mmol/L" => 699
    "mmol/L glucose" => 695
    "mmol/L_glucose" => 695
    "mo" => 312
    "mohs" => 489
    "mol" => 5
    "mol/L" => 698
    "mol/mol" => 666
    "mol/m³" => 702
    "mol_photon/m²/s" => 753
    "molal" => 862
    "molar" => 861
    "molar concentration" => 697
    "molarity" => 697
    "mole" => 5
    "mole fraction" => 666
    "moles" => 5
    "moment" => 444
    "moment magnitude" => 800
    "moment_magnitude" => 800
    "moments" => 444
    "momentum" => 674
    "momme" => 547
    "mommes" => 547
    "month" => 312
    "months" => 312
    "moon mass" => 405
    "moonmass" => 405
    "mpc" => 1442
    "mpg" => 527
    "mpge" => 528
    "mph" => 82
    "ms" => 37
    "mt" => 1437
    "mu" => 554
    "muB" => 485
    "muon mass" => 598
    "muon_mass" => 598
    "mus" => 554
    "mvar" => 1413
    "m²" => 70
    "m³" => 76
    "m³/(kg·s²)" => 100
    "m³/s" => 647
    "mΩ" => 1422
    "mₚₗ" => 299
    "nA" => 1565
    "nB" => 1597
    "nBps" => 1599
    "nBq" => 1587
    "nC" => 1578
    "nDa" => 1594
    "nF" => 1580
    "nGy" => 1588
    "nH" => 1581
    "nHz" => 1576
    "nJ" => 1573
    "nJy" => 1569
    "nK" => 1566
    "nL" => 1591
    "nM" => 701
    "nN" => 1572
    "nPa" => 1575
    "nS" => 1582
    "nSv" => 1589
    "nT" => 1584
    "nV" => 1577
    "nVA" => 1571
    "nW" => 1574
    "nWb" => 1583
    "nail_cloth" => 632
    "nanobarn" => 477
    "nanobarns" => 477
    "nanomolar" => 701
    "nat" => 461
    "nats" => 461
    "nautical mile" => 114
    "nautical miles" => 114
    "nb" => 1596
    "nb-1" => 481
    "nb^-1" => 481
    "nbarn" => 477
    "nbps" => 1598
    "nb⁻¹" => 481
    "ncd" => 1568
    "ncentury" => 1602
    "neV" => 1593
    "nebuchadnezzar" => 357
    "nebuchadnezzars" => 357
    "neutron mass" => 597
    "neutron_mass" => 597
    "newton" => 8
    "newtons" => 8
    "newtons per meter" => 660
    "nfortnight" => 1601
    "ng" => 1564
    "ng/mL" => 708
    "nibble" => 391
    "nibbles" => 391
    "nit" => 428
    "nits" => 428
    "nkat" => 1590
    "nl" => 1592
    "nlm" => 1585
    "nlx" => 1586
    "nm" => 31
    "nmi" => 114
    "nmol" => 1567
    "nmol/L" => 701
    "nominal solar luminosity" => 765
    "nominal solar radius" => 764
    "normality" => 710
    "npc" => 1600
    "ns" => 39
    "nt" => 1595
    "nvar" => 1570
    "nΩ" => 1579
    "o" => 392
    "octave" => 622
    "octaves" => 622
    "octet" => 392
    "octets" => 392
    "oersted" => 482
    "oersteds" => 482
    "ohm" => 15
    "ohm meter" => 657
    "ohms" => 15
    "oil barrel" => 534
    "oil barrels" => 534
    "oil_barrel" => 534
    "omer" => 507
    "omers" => 507
    "onah" => 521
    "onot" => 521
    "op" => 451
    "op/J" => 792
    "operations per joule" => 792
    "ops" => 451
    "ops_per_s" => 827
    "osmol" => 712
    "osmolar" => 713
    "osmole" => 712
    "osmoles" => 712
    "ounce" => 64
    "ounces" => 64
    "outhouse" => 414
    "oz" => 64
    "ozt" => 304
    "pA" => 1604
    "pB" => 1634
    "pBps" => 1636
    "pBq" => 1626
    "pC" => 1617
    "pDa" => 1633
    "pF" => 1619
    "pGy" => 1627
    "pH" => 1620
    "pHz" => 1615
    "pJ" => 1612
    "pJy" => 1608
    "pK" => 1605
    "pL" => 1630
    "pN" => 1611
    "pPa" => 1614
    "pS" => 1621
    "pSv" => 1628
    "pT" => 1623
    "pV" => 1616
    "pVA" => 1610
    "pW" => 1613
    "pWb" => 1622
    "packet" => 459
    "packets" => 459
    "page" => 613
    "pages" => 613
    "paragraph" => 611
    "paragraphs" => 611
    "parsa" => 505
    "parsec" => 117
    "parsecs" => 117
    "parts per billion" => 465
    "parts per billion by volume" => 777
    "parts per hundred million" => 467
    "parts per million" => 464
    "parts per million by mass" => 778
    "parts per million by volume" => 776
    "parts per trillion" => 466
    "parts-per-billion" => 465
    "parts-per-million" => 464
    "parts-per-trillion" => 466
    "pascal" => 9
    "pascals" => 9
    "passus" => 571
    "passuses" => 571
    "pb" => 437
    "pb-1" => 480
    "pb^-1" => 480
    "pbarn" => 476
    "pbps" => 1635
    "pb⁻¹" => 480
    "pc" => 117
    "pcd" => 1607
    "pcentury" => 1639
    "peV" => 1632
    "peanut butter" => 437
    "peanutbutter" => 437
    "peck" => 336
    "pecks" => 336
    "pedes" => 570
    "pennyweight" => 305
    "pennyweights" => 305
    "perch" => 628
    "perches" => 628
    "person hour" => 691
    "person hours" => 691
    "person_hour" => 691
    "pes" => 570
    "petabyte" => 94
    "petabytes" => 94
    "petroleum barrel" => 534
    "petroleum_barrel" => 534
    "pfortnight" => 1638
    "pg" => 1603
    "phon" => 469
    "phons" => 469
    "phot" => 743
    "photon" => 751
    "photons" => 751
    "photosynthetic photon flux density" => 754
    "phots" => 743
    "pica" => 409
    "picas" => 409
    "piccolo" => 352
    "picobarn" => 476
    "picobarns" => 476
    "pied" => 565
    "pied du roi" => 565
    "pieds" => 565
    "pieds du roi" => 565
    "pieze" => 637
    "pinch" => 341
    "pinches" => 341
    "pint" => 69
    "pints" => 69
    "pip" => 625
    "pipe" => 349
    "pipes" => 349
    "pips" => 625
    "pixel" => 685
    "pixels" => 685
    "pk" => 336
    "pkat" => 1629
    "pl" => 1631
    "planck length" => 287
    "planck mass" => 299
    "planck time" => 326
    "plaque forming unit" => 719
    "plaque-forming unit" => 719
    "plm" => 1624
    "plx" => 1625
    "pm" => 32
    "pmol" => 1606
    "point" => 408
    "points" => 408
    "poise" => 398
    "potential vorticity unit" => 768
    "potential vorticity units" => 768
    "pouce" => 566
    "pouces" => 566
    "pound" => 65
    "pound force" => 366
    "pound-force" => 366
    "pounds" => 65
    "ppb" => 465
    "ppbv" => 777
    "ppc" => 1637
    "pphm" => 467
    "ppm" => 464
    "ppmv" => 776
    "ppmw" => 778
    "pps" => 855
    "ppt" => 466
    "proton mass" => 596
    "proton_mass" => 596
    "ps" => 40
    "psi" => 361
    "pt" => 69
    "pud" => 562
    "puds" => 562
    "puncheon" => 348
    "puncheons" => 348
    "pvar" => 1609
    "px" => 685
    "pΩ" => 1618
    "qA" => 1845
    "qB" => 1876
    "qBps" => 1878
    "qBq" => 1867
    "qC" => 1858
    "qDa" => 1874
    "qF" => 1860
    "qGy" => 1868
    "qH" => 1861
    "qHz" => 1856
    "qJ" => 1853
    "qJy" => 1849
    "qK" => 1846
    "qL" => 1871
    "qN" => 1852
    "qPa" => 1855
    "qS" => 1862
    "qSv" => 1869
    "qT" => 1864
    "qV" => 1857
    "qVA" => 1851
    "qW" => 1854
    "qWb" => 1863
    "qb" => 1875
    "qbps" => 1877
    "qcd" => 1848
    "qcentury" => 1881
    "qeV" => 1873
    "qfortnight" => 1880
    "qg" => 1843
    "qkat" => 1870
    "ql" => 1872
    "qlm" => 1865
    "qlx" => 1866
    "qm" => 1842
    "qmol" => 1847
    "qpc" => 1879
    "qps" => 849
    "qquad" => 436
    "qr" => 291
    "qs" => 1844
    "qt" => 68
    "quad" => 434
    "quality adjusted life year" => 692
    "quality-adjusted life year" => 692
    "quart" => 68
    "quarter" => 291
    "quarters" => 291
    "quarts" => 68
    "queries" => 456
    "query" => 456
    "quintal" => 307
    "quintals" => 307
    "qvar" => 1850
    "qword" => 610
    "qwords" => 610
    "qΩ" => 1859
    "rA" => 1804
    "rB" => 1836
    "rBps" => 1838
    "rBq" => 1826
    "rC" => 1817
    "rDa" => 1833
    "rF" => 1819
    "rGy" => 1827
    "rH" => 1820
    "rHz" => 1815
    "rJ" => 1812
    "rJy" => 1808
    "rK" => 1805
    "rL" => 1830
    "rN" => 1811
    "rPa" => 1814
    "rS" => 1821
    "rSv" => 1828
    "rT" => 1823
    "rV" => 1816
    "rVA" => 1810
    "rW" => 1813
    "rWb" => 1822
    "rack unit" => 277
    "rack units" => 277
    "rad" => 84
    "rad/s" => 671
    "rad/s²" => 672
    "rad_dose" => 755
    "radian" => 84
    "radiance" => 747
    "radians" => 84
    "radiant exposure" => 750
    "radiant intensity" => 746
    "radiation absorbed dose" => 755
    "rankine" => 256
    "rankine difference" => 265
    "rb" => 1835
    "rbe" => 802
    "rbps" => 1837
    "rcd" => 1807
    "rcentury" => 1841
    "rd" => 425
    "reV" => 1832
    "reactive power" => 729
    "reaumur" => 259
    "rega" => 520
    "regaim" => 520
    "rehoboam" => 355
    "relative biological effectiveness" => 802
    "rem" => 381
    "rem_css" => 688
    "rems" => 381
    "request" => 457
    "requests" => 457
    "resistivity" => 657
    "rev" => 447
    "revolution" => 447
    "revolutions" => 447
    "revolutions per minute" => 424
    "revs" => 447
    "rfortnight" => 1840
    "rg" => 1802
    "ri" => 541
    "richter" => 799
    "richter scale" => 799
    "rkat" => 1829
    "rl" => 1831
    "rlm" => 1824
    "rlx" => 1825
    "rm" => 1801
    "rmol" => 1806
    "rockwell" => 491
    "rod" => 272
    "rods" => 272
    "roentgen" => 756
    "roentgens" => 756
    "roman libra" => 574
    "roman mile" => 572
    "roman uncia" => 575
    "romer" => 260
    "rope" => 627
    "ropes" => 627
    "rot" => 449
    "rotation" => 449
    "rotations" => 449
    "rotations per minute" => 424
    "royal cubit" => 577
    "royal cubits" => 577
    "royal_cubit" => 577
    "rpc" => 1839
    "rpm" => 424
    "rps" => 851
    "rs" => 1803
    "rt" => 1834
    "rundlet" => 345
    "rundlets" => 345
    "russian funt" => 563
    "russian_funt" => 563
    "rutherford" => 425
    "rutherfords" => 425
    "rvar" => 1809
    "rydberg" => 589
    "rydberg_unit" => 589
    "rydbergs" => 589
    "réaumur" => 259
    "rømer" => 260
    "rΩ" => 1818
    "s" => 2
    "sabbath day's journey" => 506
    "sabbatical" => 523
    "saffir simpson" => 796
    "saffir_simpson" => 796
    "sagan" => 643
    "sagans" => 643
    "sample" => 445
    "samples" => 445
    "savart" => 621
    "savarts" => 621
    "sazhen" => 560
    "sazhens" => 560
    "sb" => 429
    "score" => 496
    "scores" => 496
    "scruple" => 300
    "scruples" => 300
    "seah" => 511
    "seahs" => 511
    "second" => 2
    "seconds" => 2
    "sector" => 612
    "sectors" => 612
    "seer" => 586
    "seers" => 586
    "seim" => 511
    "semitone" => 620
    "semitones" => 620
    "shaftment" => 630
    "shaftments" => 630
    "shake" => 318
    "shakes" => 318
    "shaku" => 539
    "shakus" => 539
    "shed" => 415
    "shekalim" => 514
    "shekel" => 514
    "shekels" => 514
    "shmita" => 523
    "shmitas" => 523
    "shmitta" => 523
    "short ton" => 294
    "short tons" => 294
    "sidereal day" => 322
    "sidereal days" => 322
    "sidereal year" => 319
    "sidereal years" => 319
    "siderealday" => 322
    "siderealyear" => 319
    "siemens" => 16
    "siemens per meter" => 658
    "sievert" => 25
    "sieverts" => 25
    "sk" => 433
    "skot" => 433
    "skots" => 433
    "slug" => 298
    "slugs" => 298
    "smidgen" => 342
    "smidgens" => 342
    "smoot" => 274
    "smoots" => 274
    "solar mass" => 402
    "solar radius" => 406
    "solarmass" => 402
    "solarradius" => 406
    "sone" => 468
    "sones" => 468
    "span" => 501
    "spans" => 501
    "specific energy" => 665
    "specific heat capacity" => 652
    "specific_energy" => 665
    "spectral efficiency" => 677
    "spectral flux density" => 748
    "split" => 352
    "splits" => 352
    "sq ft" => 120
    "sqft" => 120
    "sqm" => 121
    "square feet" => 120
    "square foot" => 120
    "sr" => 86
    "st" => 290
    "standard gravity" => 524
    "statA" => 732
    "statC" => 734
    "statF" => 740
    "statH" => 742
    "statV" => 736
    "statampere" => 732
    "statcoulomb" => 734
    "statfarad" => 740
    "stathenry" => 742
    "statohm" => 738
    "statvolt" => 736
    "statΩ" => 738
    "steradian" => 86
    "steradians" => 86
    "stere" => 417
    "stick" => 530
    "stick of butter" => 530
    "sticks" => 530
    "sticks of butter" => 530
    "stilb" => 429
    "stilbs" => 429
    "stokes" => 400
    "stone" => 290
    "stones" => 290
    "stop" => 616
    "stops" => 616
    "story point" => 693
    "story points" => 693
    "story_point" => 693
    "stère" => 417
    "stères" => 417
    "sun" => 540
    "suns" => 540
    "surface tension" => 660
    "svedberg" => 727
    "svedbergs" => 727
    "sverdrup" => 769
    "sverdrups" => 769
    "symbol" => 779
    "symbols" => 779
    "synodic month" => 323
    "synodic months" => 323
    "t" => 36
    "tablespoon" => 337
    "tablespoons" => 337
    "talent" => 516
    "talents" => 516
    "talmudic mil" => 504
    "talmudic_mil" => 504
    "tatami" => 544
    "tatamis" => 544
    "tbsp" => 337
    "tce" => 536
    "teaspoon" => 338
    "teaspoons" => 338
    "techum" => 506
    "techum shabbat" => 506
    "tefach" => 502
    "tefachim" => 502
    "tenth cent" => 624
    "tenth_cent" => 624
    "tertian" => 348
    "tesla" => 18
    "teslas" => 18
    "tex" => 639
    "texpt" => 410
    "therm" => 374
    "thermal conductivity" => 653
    "thermochemical calorie" => 370
    "thermochemical kilocalorie" => 372
    "therms" => 374
    "tick" => 446
    "ticks" => 446
    "tierce" => 346
    "tierces" => 346
    "tn" => 294
    "toise" => 567
    "toises" => 567
    "tok" => 454
    "tok/J" => 793
    "tok/s" => 841
    "token" => 454
    "tokens" => 454
    "tokens per joule" => 793
    "tola" => 585
    "tolas" => 585
    "ton" => 294
    "tonne" => 36
    "tonne of coal equivalent" => 536
    "tonnes" => 36
    "tons" => 294
    "torque" => 676
    "torr" => 362
    "torrs" => 362
    "total electron content unit" => 773
    "tps" => 853
    "transaction" => 458
    "transactions" => 458
    "transfer" => 455
    "transfers" => 455
    "transport carbon intensity" => 684
    "traversed edges per second" => 859
    "tropical year" => 320
    "tropical years" => 320
    "tropicalyear" => 320
    "troy ounce" => 304
    "troy ounces" => 304
    "troyounce" => 304
    "tsp" => 338
    "tsubo" => 543
    "tsubos" => 543
    "tun" => 350
    "tuns" => 350
    "turn" => 386
    "turns" => 386
    "txn" => 458
    "tₚ" => 326
    "u" => 297
    "uA" => 1448
    "uB" => 1480
    "uBps" => 1482
    "uBq" => 1470
    "uC" => 1461
    "uDa" => 1477
    "uF" => 1463
    "uGy" => 1471
    "uH" => 1464
    "uHz" => 1459
    "uJ" => 1456
    "uJy" => 1452
    "uK" => 1449
    "uL" => 1474
    "uM" => 700
    "uN" => 1455
    "uPa" => 1458
    "uS" => 1465
    "uSv" => 1472
    "uT" => 1467
    "uV" => 1460
    "uVA" => 1454
    "uW" => 1457
    "uWb" => 1466
    "uas" => 763
    "ub" => 1479
    "ubps" => 1481
    "ucd" => 1451
    "ucentury" => 1485
    "ueV" => 1476
    "ufortnight" => 1484
    "ug" => 1446
    "ukat" => 1473
    "ul" => 1475
    "ulm" => 1468
    "ulx" => 1469
    "um" => 1445
    "umol" => 1450
    "uncia_roma" => 575
    "upc" => 1483
    "update" => 781
    "updates" => 781
    "us" => 1447
    "ut" => 1478
    "uvar" => 1453
    "uΩ" => 1462
    "var" => 729
    "vershok" => 561
    "vershoks" => 561
    "verst" => 558
    "versts" => 558
    "vh" => 690
    "vickers" => 490
    "viewport height" => 690
    "viewport width" => 689
    "volt" => 13
    "volt ampere" => 730
    "volt-ampere" => 730
    "volts" => 13
    "volts per meter" => 655
    "volumetric flow" => 647
    "vw" => 689
    "warhol" => 422
    "warhols" => 422
    "water horsepower" => 601
    "water_horsepower" => 601
    "watt" => 11
    "watts" => 11
    "watts per square meter" => 654
    "wavenumber" => 488
    "weber" => 17
    "webers" => 17
    "wedgwood" => 261
    "week" => 311
    "weeks" => 311
    "wk" => 311
    "yA" => 1763
    "yB" => 1795
    "yBps" => 1797
    "yBq" => 1785
    "yC" => 1776
    "yDa" => 1792
    "yF" => 1778
    "yGy" => 1786
    "yH" => 1779
    "yHz" => 1774
    "yJ" => 1771
    "yJy" => 1767
    "yK" => 1764
    "yL" => 1789
    "yN" => 1770
    "yPa" => 1773
    "yS" => 1780
    "ySv" => 1787
    "yT" => 1782
    "yV" => 1775
    "yVA" => 1769
    "yW" => 1772
    "yWb" => 1781
    "yard" => 62
    "yards" => 62
    "yb" => 1794
    "ybps" => 1796
    "ycd" => 1766
    "ycentury" => 1800
    "yd" => 62
    "yeV" => 1791
    "year" => 313
    "years" => 313
    "yfortnight" => 1799
    "yg" => 1761
    "ykat" => 1788
    "yl" => 1790
    "ylm" => 1783
    "ylx" => 1784
    "ym" => 1760
    "ymol" => 1765
    "yovel" => 522
    "yovels" => 522
    "ypc" => 1798
    "yr" => 313
    "ys" => 1762
    "yt" => 1793
    "yvar" => 1768
    "yΩ" => 1777
    "zA" => 1722
    "zB" => 1754
    "zBps" => 1756
    "zBq" => 1744
    "zC" => 1735
    "zDa" => 1751
    "zF" => 1737
    "zGy" => 1745
    "zH" => 1738
    "zHz" => 1733
    "zJ" => 1730
    "zJy" => 1726
    "zK" => 1723
    "zL" => 1748
    "zN" => 1729
    "zPa" => 1732
    "zS" => 1739
    "zSv" => 1746
    "zT" => 1741
    "zV" => 1734
    "zVA" => 1728
    "zW" => 1731
    "zWb" => 1740
    "zb" => 1753
    "zbps" => 1755
    "zcd" => 1725
    "zcentury" => 1759
    "zeV" => 1750
    "zeret" => 501
    "zfortnight" => 1758
    "zg" => 1720
    "zhang" => 552
    "zhangs" => 552
    "zkat" => 1747
    "zl" => 1749
    "zlm" => 1742
    "zlx" => 1743
    "zm" => 1719
    "zmol" => 1724
    "zpc" => 1757
    "zs" => 1721
    "zt" => 1752
    "zvar" => 1727
    "zΩ" => 1736
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
    "µB" => 1558
    "µBps" => 1560
    "µBq" => 1548
    "µC" => 1539
    "µDa" => 1555
    "µF" => 1541
    "µGy" => 1549
    "µH" => 1542
    "µHz" => 1537
    "µJ" => 1534
    "µJy" => 1530
    "µK" => 1527
    "µL" => 1552
    "µM" => 700
    "µN" => 1533
    "µPa" => 1536
    "µS" => 1543
    "µSv" => 1550
    "µT" => 1545
    "µV" => 1538
    "µVA" => 1532
    "µW" => 1535
    "µWb" => 1544
    "µas" => 763
    "µb" => 1557
    "µbps" => 1559
    "µcd" => 1529
    "µcentury" => 1563
    "µeV" => 1554
    "µfortnight" => 1562
    "µg" => 35
    "µg/mL" => 707
    "µkat" => 1551
    "µl" => 1553
    "µlm" => 1546
    "µlx" => 1547
    "µm" => 30
    "µmol" => 1528
    "µmol/L" => 700
    "µmol_photon/m²/s" => 754
    "µpc" => 1561
    "µs" => 38
    "µt" => 1556
    "µvar" => 1531
    "µΩ" => 1540
    "Å" => 278
    "ångström" => 278
    "ɡ" => 524
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
    "Ω·m" => 657
    "α" => 594
    "μA" => 1489
    "μB" => 1521
    "μBps" => 1523
    "μBq" => 1511
    "μC" => 1502
    "μDa" => 1518
    "μF" => 1504
    "μGy" => 1512
    "μH" => 1505
    "μHz" => 1500
    "μJ" => 1497
    "μJy" => 1493
    "μK" => 1490
    "μL" => 1515
    "μM" => 700
    "μN" => 1496
    "μPa" => 1499
    "μS" => 1506
    "μSv" => 1513
    "μT" => 1508
    "μV" => 1501
    "μVA" => 1495
    "μW" => 1498
    "μWb" => 1507
    "μ_B" => 485
    "μas" => 763
    "μb" => 1520
    "μbps" => 1522
    "μcd" => 1492
    "μcentury" => 1526
    "μeV" => 1517
    "μfortnight" => 1525
    "μg" => 1487
    "μkat" => 1514
    "μl" => 1516
    "μlife" => 487
    "μlm" => 1509
    "μlx" => 1510
    "μm" => 1486
    "μmol" => 1491
    "μmort" => 486
    "μpc" => 1524
    "μs" => 1488
    "μt" => 1519
    "μvar" => 1494
    "μΩ" => 1503
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
    "Ah" => "0,0,1,1,0,0,0,0,"
    "Apgar" => "0,0,0,0,0,0,0,0,apgar:1"
    "B" => "0,0,0,0,0,0,0,1,"
    "B/flop" => "0,0,0,0,0,0,0,1,flop:-1"
    "B/s" => "0,0,-1,0,0,0,0,1,"
    "BOE" => "2,1,-2,0,0,0,0,0,"
    "BPM" => "0,0,-1,0,0,0,0,0,beat:1"
    "BTU" => "2,1,-2,0,0,0,0,0,"
    "Ba" => "-1,1,-2,0,0,0,0,0,"
    "Beaufort" => "0,0,0,0,0,0,0,0,beaufort:1"
    "Bortle" => "0,0,0,0,0,0,0,0,bortle:1"
    "Bps" => "0,0,-1,0,0,0,0,1,"
    "Bq" => "0,0,-1,0,0,0,0,0,decay:1"
    "Bq/kg" => "0,-1,-1,0,0,0,0,0,decay:1"
    "Bq/m³" => "-3,0,-1,0,0,0,0,0,decay:1"
    "C" => "0,0,1,1,0,0,0,0,"
    "C/m³" => "-3,0,1,1,0,0,0,0,"
    "CFU" => "0,0,0,0,0,0,0,0,colony_forming_unit:1"
    "CFU/mL" => "-3,0,0,0,0,0,0,0,colony_forming_unit:1"
    "CFUs" => "0,0,0,0,0,0,0,0,colony_forming_unit:1"
    "CWT" => "0,1,0,0,0,0,0,0,"
    "Ci" => "0,0,-1,0,0,0,0,0,decay:1"
    "D" => "1,0,1,1,0,0,0,0,"
    "DMIPS" => "0,0,-1,0,0,0,0,0,instruction:1"
    "DU" => "-2,0,0,0,0,1,0,0,"
    "DWORD" => "0,0,0,0,0,0,0,1,"
    "Da" => "0,1,0,0,0,0,0,0,"
    "E" => "0,0,-2,0,0,0,0,0,"
    "EA" => "0,0,0,1,0,0,0,0,"
    "EB" => "0,0,0,0,0,0,0,1,"
    "EBps" => "0,0,-1,0,0,0,0,1,"
    "EBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "EC" => "0,0,1,1,0,0,0,0,"
    "EDa" => "0,1,0,0,0,0,0,0,"
    "EF" => "0,0,0,0,0,0,0,0,ef:1"
    "EF-scale" => "0,0,0,0,0,0,0,0,ef:1"
    "EFLOPS" => "0,0,-1,0,0,0,0,0,flop:1"
    "EGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "EH" => "2,1,-2,-2,0,0,0,0,"
    "EHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "EJ" => "2,1,-2,0,0,0,0,0,"
    "EJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "EK" => "0,0,0,0,1,0,0,0,"
    "EL" => "3,0,0,0,0,0,0,0,"
    "EN" => "1,1,-2,0,0,0,0,0,"
    "EOPS" => "0,0,-1,0,0,0,0,0,op:1"
    "EPa" => "-1,1,-2,0,0,0,0,0,"
    "ES" => "-2,-1,3,2,0,0,0,0,"
    "ESv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "ET" => "0,1,-2,-1,0,0,0,0,"
    "EV" => "0,0,0,0,0,0,0,0,exposure_value:1"
    "EVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "EW" => "2,1,-3,0,0,0,0,0,"
    "EWb" => "2,1,-2,-1,0,0,0,0,"
    "Eb" => "0,0,0,0,0,0,0,1,"
    "Ebps" => "0,0,-1,0,0,0,0,1,"
    "Ecd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "Ecentury" => "0,0,1,0,0,0,0,0,"
    "EeV" => "2,1,-2,0,0,0,0,0,"
    "Eflops" => "0,0,-1,0,0,0,0,0,flop:1"
    "Efortnight" => "0,0,1,0,0,0,0,0,"
    "Eg" => "0,1,0,0,0,0,0,0,"
    "Eh" => "2,1,-2,0,0,0,0,0,"
    "EiB" => "0,0,0,0,0,0,0,1,"
    "Eib" => "0,0,0,0,0,0,0,1,"
    "Ekat" => "0,0,-1,0,0,1,0,0,"
    "El" => "3,0,0,0,0,0,0,0,"
    "Elm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "Elx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "Em" => "1,0,0,0,0,0,0,0,"
    "Emol" => "0,0,0,0,0,1,0,0,"
    "Eotvos" => "0,0,-2,0,0,0,0,0,"
    "Epc" => "1,0,0,0,0,0,0,0,"
    "Eq" => "0,0,0,0,0,1,0,0,chemical_equivalent:1"
    "Eq/L" => "-3,0,0,0,0,1,0,0,chemical_equivalent:1"
    "Es" => "0,0,1,0,0,0,0,0,"
    "Et" => "0,1,0,0,0,0,0,0,"
    "Evar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "Eötvös" => "0,0,-2,0,0,0,0,0,"
    "EΩ" => "2,1,-3,-2,0,0,0,0,"
    "F" => "-2,-1,4,2,0,0,0,0,"
    "F-scale" => "0,0,0,0,0,0,0,0,fujita:1"
    "F/m" => "-3,-1,4,2,0,0,0,0,"
    "FLOPS" => "0,0,-1,0,0,0,0,0,flop:1"
    "FPS" => "0,0,-1,0,0,0,0,0,frame:1"
    "Fr_catheter" => "1,0,0,0,0,0,0,0,"
    "GA" => "0,0,0,1,0,0,0,0,"
    "GB" => "0,0,0,0,0,0,0,1,"
    "GB/s" => "0,0,-1,0,0,0,0,1,"
    "GBps" => "0,0,-1,0,0,0,0,1,"
    "GBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "GC" => "0,0,1,1,0,0,0,0,"
    "GDa" => "0,1,0,0,0,0,0,0,"
    "GF" => "-2,-1,4,2,0,0,0,0,"
    "GFLOPS" => "0,0,-1,0,0,0,0,0,flop:1"
    "GGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "GH" => "2,1,-2,-2,0,0,0,0,"
    "GHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "GIPS" => "0,0,-1,0,0,0,0,0,instruction:1"
    "GJ" => "2,1,-2,0,0,0,0,0,"
    "GJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "GK" => "0,0,0,0,1,0,0,0,"
    "GL" => "3,0,0,0,0,0,0,0,"
    "GMAC/s" => "0,0,-1,0,0,0,0,0,mac:1"
    "GN" => "1,1,-2,0,0,0,0,0,"
    "GOPS" => "0,0,-1,0,0,0,0,0,op:1"
    "GPa" => "-1,1,-2,0,0,0,0,0,"
    "GS" => "-2,-1,3,2,0,0,0,0,"
    "GSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "GT" => "0,1,-2,-1,0,0,0,0,"
    "GT/s" => "0,0,-1,0,0,0,0,0,transfer:1"
    "GUPS" => "0,0,-1,0,0,0,0,0,cell_update:1"
    "GV" => "2,1,-3,-1,0,0,0,0,"
    "GVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "GW" => "2,1,-3,0,0,0,0,0,"
    "GWb" => "2,1,-2,-1,0,0,0,0,"
    "Ga" => "0,1,-2,-1,0,0,0,0,"
    "Gal" => "1,0,-2,0,0,0,0,0,"
    "Gb" => "0,0,0,1,0,0,0,0,"
    "Gb/s" => "0,0,-1,0,0,0,0,1,"
    "Gbps" => "0,0,-1,0,0,0,0,1,"
    "Gcd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "Gcentury" => "0,0,1,0,0,0,0,0,"
    "GeV" => "2,1,-2,0,0,0,0,0,"
    "Gflops" => "0,0,-1,0,0,0,0,0,flop:1"
    "Gfortnight" => "0,0,1,0,0,0,0,0,"
    "Gg" => "0,1,0,0,0,0,0,0,"
    "GiB" => "0,0,0,0,0,0,0,1,"
    "GiB/s" => "0,0,-1,0,0,0,0,1,"
    "Gib" => "0,0,0,0,0,0,0,1,"
    "Gkat" => "0,0,-1,0,0,1,0,0,"
    "Gl" => "3,0,0,0,0,0,0,0,"
    "Glm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "Glx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "Gm" => "1,0,0,0,0,0,0,0,"
    "Gmol" => "0,0,0,0,0,1,0,0,"
    "Gpc" => "1,0,0,0,0,0,0,0,"
    "Gs" => "0,0,1,0,0,0,0,0,"
    "Gt" => "0,1,0,0,0,0,0,0,"
    "Gtok/s" => "0,0,-1,0,0,0,0,0,token:1"
    "Gvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "Gy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "Gy/s" => "2,0,-3,0,0,0,0,0,absorbed_dose:1"
    "GΩ" => "2,1,-3,-2,0,0,0,0,"
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
    "IU" => "0,0,0,0,0,0,0,0,international_unit:1"
    "IU/mL" => "-3,0,0,0,0,0,0,0,international_unit:1"
    "J" => "2,1,-2,0,0,0,0,0,"
    "J/(kg·K)" => "2,0,-2,0,-1,0,0,0,"
    "J/(mol·K)" => "2,1,-2,0,-1,-1,0,0,"
    "J/K" => "2,1,-2,0,-1,0,0,0,"
    "J/kg" => "2,0,-2,0,0,0,0,0,"
    "J/kg/K" => "2,0,-2,0,-1,0,0,0,"
    "J/m²" => "0,1,-2,0,0,0,0,0,"
    "J/m³" => "-1,1,-2,0,0,0,0,0,"
    "J/op" => "2,1,-2,0,0,0,0,0,op:-1"
    "J/tok" => "2,1,-2,0,0,0,0,0,token:-1"
    "Jy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "J·s" => "2,1,-1,0,0,0,0,0,"
    "K" => "0,0,0,0,1,0,0,0,"
    "KB" => "0,0,0,0,0,0,0,1,"
    "KOPS" => "0,0,-1,0,0,0,0,0,op:1"
    "KiB" => "0,0,0,0,0,0,0,1,"
    "Kib" => "0,0,0,0,0,0,0,1,"
    "L" => "3,0,0,0,0,0,0,0,"
    "L per 100 km" => "2,0,0,0,0,0,0,0,"
    "L/100km" => "2,0,0,0,0,0,0,0,"
    "L/min" => "3,0,-1,0,0,0,0,0,"
    "LT" => "0,1,0,0,0,0,0,0,"
    "L_sun_nominal" => "2,1,-3,0,0,0,0,0,"
    "La" => "-2,0,0,0,0,0,1,0,luminance:1"
    "L☉_N" => "2,1,-3,0,0,0,0,0,"
    "M" => "-3,0,0,0,0,1,0,0,"
    "MA" => "0,0,0,1,0,0,0,0,"
    "MAC/s" => "0,0,-1,0,0,0,0,0,mac:1"
    "MB" => "0,0,0,0,0,0,0,1,"
    "MB/s" => "0,0,-1,0,0,0,0,1,"
    "MBps" => "0,0,-1,0,0,0,0,1,"
    "MBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "MC" => "0,0,1,1,0,0,0,0,"
    "MDa" => "0,1,0,0,0,0,0,0,"
    "MF" => "-2,-1,4,2,0,0,0,0,"
    "MFLOPS" => "0,0,-1,0,0,0,0,0,flop:1"
    "MGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "MH" => "2,1,-2,-2,0,0,0,0,"
    "MHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "MIPS" => "0,0,-1,0,0,0,0,0,instruction:1"
    "MJ" => "2,1,-2,0,0,0,0,0,"
    "MJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "MK" => "0,0,0,0,1,0,0,0,"
    "ML" => "3,0,0,0,0,0,0,0,"
    "MMAC/s" => "0,0,-1,0,0,0,0,0,mac:1"
    "MN" => "1,1,-2,0,0,0,0,0,"
    "MOPS" => "0,0,-1,0,0,0,0,0,op:1"
    "MPG" => "-2,0,0,0,0,0,0,0,"
    "MPGe" => "-2,0,0,0,0,0,0,0,"
    "MPa" => "-1,1,-2,0,0,0,0,0,"
    "MS" => "-2,-1,3,2,0,0,0,0,"
    "MSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "MT" => "0,1,-2,-1,0,0,0,0,"
    "MT/s" => "0,0,-1,0,0,0,0,0,transfer:1"
    "MV" => "2,1,-3,-1,0,0,0,0,"
    "MVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "MW" => "2,1,-3,0,0,0,0,0,"
    "MWb" => "2,1,-2,-1,0,0,0,0,"
    "MWh" => "2,1,-2,0,0,0,0,0,"
    "M_bol" => "0,0,0,0,0,0,0,0,magnitude_bolometric:1"
    "Mach at 20 C" => "1,0,-1,0,0,0,0,0,"
    "Mach in air at 20 C" => "1,0,-1,0,0,0,0,0,"
    "Mag" => "0,0,0,0,0,0,0,0,magnitude_absolute:1"
    "Mb" => "0,0,0,0,0,0,0,1,"
    "Mb/s" => "0,0,-1,0,0,0,0,1,"
    "Mbol" => "0,0,0,0,0,0,0,0,magnitude_bolometric:1"
    "Mbps" => "0,0,-1,0,0,0,0,1,"
    "Mcd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "Mcentury" => "0,0,1,0,0,0,0,0,"
    "MeV" => "2,1,-2,0,0,0,0,0,"
    "Mflops" => "0,0,-1,0,0,0,0,0,flop:1"
    "Mfortnight" => "0,0,1,0,0,0,0,0,"
    "Mg" => "0,1,0,0,0,0,0,0,"
    "MiB" => "0,0,0,0,0,0,0,1,"
    "MiB/s" => "0,0,-1,0,0,0,0,1,"
    "Mib" => "0,0,0,0,0,0,0,1,"
    "Mkat" => "0,0,-1,0,0,1,0,0,"
    "Ml" => "3,0,0,0,0,0,0,0,"
    "Mlm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "Mlx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "Mm" => "1,0,0,0,0,0,0,0,"
    "Mmol" => "0,0,0,0,0,1,0,0,"
    "Mohs" => "0,0,0,0,0,0,0,0,hardness_mohs:1"
    "Mpc" => "1,0,0,0,0,0,0,0,"
    "Ms" => "0,0,1,0,0,0,0,0,"
    "Mt" => "0,1,0,0,0,0,0,0,"
    "Mtok/s" => "0,0,-1,0,0,0,0,0,token:1"
    "Mvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "Mw" => "0,0,0,0,0,0,0,0,magnitude:1"
    "Mx" => "2,1,-2,-1,0,0,0,0,"
    "MΩ" => "2,1,-3,-2,0,0,0,0,"
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
    "Osm/L" => "-3,0,0,0,0,1,0,0,osmotic_entity:1"
    "P" => "-1,1,-1,0,0,0,0,0,"
    "PA" => "0,0,0,1,0,0,0,0,"
    "PB" => "0,0,0,0,0,0,0,1,"
    "PBps" => "0,0,-1,0,0,0,0,1,"
    "PBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "PC" => "0,0,1,1,0,0,0,0,"
    "PDa" => "0,1,0,0,0,0,0,0,"
    "PF" => "-2,-1,4,2,0,0,0,0,"
    "PFLOPS" => "0,0,-1,0,0,0,0,0,flop:1"
    "PFU" => "0,0,0,0,0,0,0,0,plaque_forming_unit:1"
    "PFU/mL" => "-3,0,0,0,0,0,0,0,plaque_forming_unit:1"
    "PFUs" => "0,0,0,0,0,0,0,0,plaque_forming_unit:1"
    "PGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "PH" => "2,1,-2,-2,0,0,0,0,"
    "PHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "PJ" => "2,1,-2,0,0,0,0,0,"
    "PJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "PK" => "0,0,0,0,1,0,0,0,"
    "PL" => "3,0,0,0,0,0,0,0,"
    "PN" => "1,1,-2,0,0,0,0,0,"
    "POPS" => "0,0,-1,0,0,0,0,0,op:1"
    "PPFD" => "-2,0,-1,0,0,1,0,0,photon:1"
    "PPS" => "0,0,-1,0,0,0,0,0,packet:1"
    "PPa" => "-1,1,-2,0,0,0,0,0,"
    "PS" => "2,1,-3,0,0,0,0,0,"
    "PSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "PT" => "0,1,-2,-1,0,0,0,0,"
    "PV" => "2,1,-3,-1,0,0,0,0,"
    "PVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "PVU" => "2,-1,-1,0,1,0,0,0,"
    "PW" => "2,1,-3,0,0,0,0,0,"
    "PWb" => "2,1,-2,-1,0,0,0,0,"
    "Pa" => "-1,1,-2,0,0,0,0,0,"
    "Pb" => "0,0,0,0,0,0,0,1,"
    "Pbps" => "0,0,-1,0,0,0,0,1,"
    "Pcd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "Pcentury" => "0,0,1,0,0,0,0,0,"
    "PeV" => "2,1,-2,0,0,0,0,0,"
    "Pflops" => "0,0,-1,0,0,0,0,0,flop:1"
    "Pfortnight" => "0,0,1,0,0,0,0,0,"
    "Pg" => "0,1,0,0,0,0,0,0,"
    "PiB" => "0,0,0,0,0,0,0,1,"
    "Pib" => "0,0,0,0,0,0,0,1,"
    "Pkat" => "0,0,-1,0,0,1,0,0,"
    "Pl" => "3,0,0,0,0,0,0,0,"
    "Planck length" => "1,0,0,0,0,0,0,0,"
    "Planck mass" => "0,1,0,0,0,0,0,0,"
    "Planck time" => "0,0,1,0,0,0,0,0,"
    "Plm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "Plx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "Pm" => "1,0,0,0,0,0,0,0,"
    "Pmol" => "0,0,0,0,0,1,0,0,"
    "Ppc" => "1,0,0,0,0,0,0,0,"
    "Ps" => "0,0,1,0,0,0,0,0,"
    "Pt" => "0,1,0,0,0,0,0,0,"
    "Pvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "PΩ" => "2,1,-3,-2,0,0,0,0,"
    "QA" => "0,0,0,1,0,0,0,0,"
    "QALY" => "0,0,1,0,0,0,0,0,quality_adjusted_life:1"
    "QALYs" => "0,0,1,0,0,0,0,0,quality_adjusted_life:1"
    "QB" => "0,0,0,0,0,0,0,1,"
    "QBps" => "0,0,-1,0,0,0,0,1,"
    "QBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "QC" => "0,0,1,1,0,0,0,0,"
    "QDa" => "0,1,0,0,0,0,0,0,"
    "QF" => "-2,-1,4,2,0,0,0,0,"
    "QGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "QH" => "2,1,-2,-2,0,0,0,0,"
    "QHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "QJ" => "2,1,-2,0,0,0,0,0,"
    "QJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "QK" => "0,0,0,0,1,0,0,0,"
    "QL" => "3,0,0,0,0,0,0,0,"
    "QN" => "1,1,-2,0,0,0,0,0,"
    "QPS" => "0,0,-1,0,0,0,0,0,query:1"
    "QPa" => "-1,1,-2,0,0,0,0,0,"
    "QS" => "-2,-1,3,2,0,0,0,0,"
    "QSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "QT" => "0,1,-2,-1,0,0,0,0,"
    "QV" => "2,1,-3,-1,0,0,0,0,"
    "QVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "QW" => "2,1,-3,0,0,0,0,0,"
    "QWORD" => "0,0,0,0,0,0,0,1,"
    "QWb" => "2,1,-2,-1,0,0,0,0,"
    "Qb" => "0,0,0,0,0,0,0,1,"
    "Qbps" => "0,0,-1,0,0,0,0,1,"
    "Qcd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "Qcentury" => "0,0,1,0,0,0,0,0,"
    "QeV" => "2,1,-2,0,0,0,0,0,"
    "Qfortnight" => "0,0,1,0,0,0,0,0,"
    "Qg" => "0,1,0,0,0,0,0,0,"
    "QiB" => "0,0,0,0,0,0,0,1,"
    "Qib" => "0,0,0,0,0,0,0,1,"
    "Qkat" => "0,0,-1,0,0,1,0,0,"
    "Ql" => "3,0,0,0,0,0,0,0,"
    "Qlm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "Qlx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "Qm" => "1,0,0,0,0,0,0,0,"
    "Qmol" => "0,0,0,0,0,1,0,0,"
    "Qpc" => "1,0,0,0,0,0,0,0,"
    "Qs" => "0,0,1,0,0,0,0,0,"
    "Qt" => "0,1,0,0,0,0,0,0,"
    "Qvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "QΩ" => "2,1,-3,-2,0,0,0,0,"
    "RA" => "0,0,0,1,0,0,0,0,"
    "RB" => "0,0,0,0,0,0,0,1,"
    "RBE" => "0,0,0,0,0,0,0,0,rbe:1"
    "RBps" => "0,0,-1,0,0,0,0,1,"
    "RBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "RC" => "0,0,1,1,0,0,0,0,"
    "RDa" => "0,1,0,0,0,0,0,0,"
    "RF" => "-2,-1,4,2,0,0,0,0,"
    "RGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "RH" => "2,1,-2,-2,0,0,0,0,"
    "RHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "RJ" => "2,1,-2,0,0,0,0,0,"
    "RJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "RK" => "0,0,0,0,1,0,0,0,"
    "RL" => "3,0,0,0,0,0,0,0,"
    "RN" => "1,1,-2,0,0,0,0,0,"
    "RPS" => "0,0,-1,0,0,0,0,0,request:1"
    "RPa" => "-1,1,-2,0,0,0,0,0,"
    "RS" => "-2,-1,3,2,0,0,0,0,"
    "RSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "RT" => "0,1,-2,-1,0,0,0,0,"
    "RU" => "1,0,0,0,0,0,0,0,"
    "RV" => "2,1,-3,-1,0,0,0,0,"
    "RVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "RW" => "2,1,-3,0,0,0,0,0,"
    "RWb" => "2,1,-2,-1,0,0,0,0,"
    "R_exposure" => "0,-1,1,1,0,0,0,0,ionizing_radiation_exposure:1"
    "R_sun_nominal" => "1,0,0,0,0,0,0,0,"
    "Rb" => "0,0,0,0,0,0,0,1,"
    "Rbps" => "0,0,-1,0,0,0,0,1,"
    "Rcd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "Rcentury" => "0,0,1,0,0,0,0,0,"
    "ReV" => "2,1,-2,0,0,0,0,0,"
    "Rfortnight" => "0,0,1,0,0,0,0,0,"
    "Rg" => "0,1,0,0,0,0,0,0,"
    "RiB" => "0,0,0,0,0,0,0,1,"
    "Rib" => "0,0,0,0,0,0,0,1,"
    "Richter" => "0,0,0,0,0,0,0,0,magnitude:1"
    "Rkat" => "0,0,-1,0,0,1,0,0,"
    "Rl" => "3,0,0,0,0,0,0,0,"
    "Rlm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "Rlx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "Rm" => "1,0,0,0,0,0,0,0,"
    "Rmol" => "0,0,0,0,0,1,0,0,"
    "Rpc" => "1,0,0,0,0,0,0,0,"
    "Rs" => "0,0,1,0,0,0,0,0,"
    "Rt" => "0,1,0,0,0,0,0,0,"
    "Rvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "Ry" => "2,1,-2,0,0,0,0,0,"
    "RΩ" => "2,1,-3,-2,0,0,0,0,"
    "R⊕" => "1,0,0,0,0,0,0,0,"
    "R☉" => "1,0,0,0,0,0,0,0,"
    "R☉_N" => "1,0,0,0,0,0,0,0,"
    "S" => "-2,-1,3,2,0,0,0,0,"
    "S/m" => "-3,-1,3,2,0,0,0,0,"
    "SS_category" => "0,0,0,0,0,0,0,0,saffir_simpson:1"
    "Saffir-Simpson" => "0,0,0,0,0,0,0,0,saffir_simpson:1"
    "St" => "2,0,-1,0,0,0,0,0,"
    "Sv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "Sv/h" => "2,0,-3,0,0,0,0,0,equivalent_dose:1"
    "Sv_ocean" => "3,0,-1,0,0,0,0,0,"
    "Svedberg" => "0,0,1,0,0,0,0,0,"
    "T" => "0,1,-2,-1,0,0,0,0,"
    "T/s" => "0,0,-1,0,0,0,0,0,transfer:1"
    "TA" => "0,0,0,1,0,0,0,0,"
    "TB" => "0,0,0,0,0,0,0,1,"
    "TBps" => "0,0,-1,0,0,0,0,1,"
    "TBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "TC" => "0,0,1,1,0,0,0,0,"
    "TCE" => "2,1,-2,0,0,0,0,0,"
    "TDa" => "0,1,0,0,0,0,0,0,"
    "TECU" => "-2,0,0,0,0,0,0,0,electron_column_density:1"
    "TEPS" => "0,0,-1,0,0,0,0,0,graph_edge:1"
    "TF" => "-2,-1,4,2,0,0,0,0,"
    "TFLOPS" => "0,0,-1,0,0,0,0,0,flop:1"
    "TGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "TH" => "2,1,-2,-2,0,0,0,0,"
    "THz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "TJ" => "2,1,-2,0,0,0,0,0,"
    "TJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "TK" => "0,0,0,0,1,0,0,0,"
    "TL" => "3,0,0,0,0,0,0,0,"
    "TMAC/s" => "0,0,-1,0,0,0,0,0,mac:1"
    "TN" => "1,1,-2,0,0,0,0,0,"
    "TOPS" => "0,0,-1,0,0,0,0,0,op:1"
    "TPS" => "0,0,-1,0,0,0,0,0,transaction:1"
    "TPa" => "-1,1,-2,0,0,0,0,0,"
    "TS" => "-2,-1,3,2,0,0,0,0,"
    "TSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "TT" => "0,1,-2,-1,0,0,0,0,"
    "TT/s" => "0,0,-1,0,0,0,0,0,transfer:1"
    "TV" => "2,1,-3,-1,0,0,0,0,"
    "TVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "TW" => "2,1,-3,0,0,0,0,0,"
    "TWb" => "2,1,-2,-1,0,0,0,0,"
    "Tb" => "0,0,0,0,0,0,0,1,"
    "Tbps" => "0,0,-1,0,0,0,0,1,"
    "Tcd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "Tcentury" => "0,0,1,0,0,0,0,0,"
    "TeV" => "2,1,-2,0,0,0,0,0,"
    "Tflops" => "0,0,-1,0,0,0,0,0,flop:1"
    "Tfortnight" => "0,0,1,0,0,0,0,0,"
    "Tg" => "0,1,0,0,0,0,0,0,"
    "TiB" => "0,0,0,0,0,0,0,1,"
    "Tib" => "0,0,0,0,0,0,0,1,"
    "Tkat" => "0,0,-1,0,0,1,0,0,"
    "Tl" => "3,0,0,0,0,0,0,0,"
    "Tlm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "Tlx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "Tm" => "1,0,0,0,0,0,0,0,"
    "Tmol" => "0,0,0,0,0,1,0,0,"
    "Torr" => "-1,1,-2,0,0,0,0,0,"
    "Tpc" => "1,0,0,0,0,0,0,0,"
    "Ts" => "0,0,1,0,0,0,0,0,"
    "Tt" => "0,1,0,0,0,0,0,0,"
    "Tvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "TΩ" => "2,1,-3,-2,0,0,0,0,"
    "U/L" => "-3,0,-1,0,0,1,0,0,"
    "U_enzyme" => "0,0,-1,0,0,1,0,0,"
    "V" => "2,1,-3,-1,0,0,0,0,"
    "V/m" => "1,1,-3,-1,0,0,0,0,"
    "VA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "W" => "2,1,-3,0,0,0,0,0,"
    "W/(m²·K⁴)" => "0,1,-3,0,-4,0,0,0,"
    "W/(m·K)" => "1,1,-3,0,-1,0,0,0,"
    "W/m/K" => "1,1,-3,0,-1,0,0,0,"
    "W/m²" => "0,1,-3,0,0,0,0,0,"
    "W/m²/Hz" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "W/m³" => "-1,1,-3,0,0,0,0,0,"
    "W/sr" => "2,1,-3,0,0,0,0,0,solid_angle:-1"
    "W/sr/m²" => "0,1,-3,0,0,0,0,0,solid_angle:-1"
    "Wb" => "2,1,-2,-1,0,0,0,0,"
    "YA" => "0,0,0,1,0,0,0,0,"
    "YB" => "0,0,0,0,0,0,0,1,"
    "YBps" => "0,0,-1,0,0,0,0,1,"
    "YBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "YC" => "0,0,1,1,0,0,0,0,"
    "YDa" => "0,1,0,0,0,0,0,0,"
    "YF" => "-2,-1,4,2,0,0,0,0,"
    "YFLOPS" => "0,0,-1,0,0,0,0,0,flop:1"
    "YGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "YH" => "2,1,-2,-2,0,0,0,0,"
    "YHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "YJ" => "2,1,-2,0,0,0,0,0,"
    "YJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "YK" => "0,0,0,0,1,0,0,0,"
    "YL" => "3,0,0,0,0,0,0,0,"
    "YN" => "1,1,-2,0,0,0,0,0,"
    "YPa" => "-1,1,-2,0,0,0,0,0,"
    "YS" => "-2,-1,3,2,0,0,0,0,"
    "YSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "YT" => "0,1,-2,-1,0,0,0,0,"
    "YV" => "2,1,-3,-1,0,0,0,0,"
    "YVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "YW" => "2,1,-3,0,0,0,0,0,"
    "YWb" => "2,1,-2,-1,0,0,0,0,"
    "Yb" => "0,0,0,0,0,0,0,1,"
    "Ybps" => "0,0,-1,0,0,0,0,1,"
    "Ycd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "Ycentury" => "0,0,1,0,0,0,0,0,"
    "YeV" => "2,1,-2,0,0,0,0,0,"
    "Yflops" => "0,0,-1,0,0,0,0,0,flop:1"
    "Yfortnight" => "0,0,1,0,0,0,0,0,"
    "Yg" => "0,1,0,0,0,0,0,0,"
    "YiB" => "0,0,0,0,0,0,0,1,"
    "Yib" => "0,0,0,0,0,0,0,1,"
    "Ykat" => "0,0,-1,0,0,1,0,0,"
    "Yl" => "3,0,0,0,0,0,0,0,"
    "Ylm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "Ylx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "Ym" => "1,0,0,0,0,0,0,0,"
    "Ymol" => "0,0,0,0,0,1,0,0,"
    "Ypc" => "1,0,0,0,0,0,0,0,"
    "Ys" => "0,0,1,0,0,0,0,0,"
    "Yt" => "0,1,0,0,0,0,0,0,"
    "Yvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "YΩ" => "2,1,-3,-2,0,0,0,0,"
    "ZA" => "0,0,0,1,0,0,0,0,"
    "ZB" => "0,0,0,0,0,0,0,1,"
    "ZBps" => "0,0,-1,0,0,0,0,1,"
    "ZBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "ZC" => "0,0,1,1,0,0,0,0,"
    "ZDa" => "0,1,0,0,0,0,0,0,"
    "ZF" => "-2,-1,4,2,0,0,0,0,"
    "ZFLOPS" => "0,0,-1,0,0,0,0,0,flop:1"
    "ZGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "ZH" => "2,1,-2,-2,0,0,0,0,"
    "ZHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "ZJ" => "2,1,-2,0,0,0,0,0,"
    "ZJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "ZK" => "0,0,0,0,1,0,0,0,"
    "ZL" => "3,0,0,0,0,0,0,0,"
    "ZN" => "1,1,-2,0,0,0,0,0,"
    "ZPa" => "-1,1,-2,0,0,0,0,0,"
    "ZS" => "-2,-1,3,2,0,0,0,0,"
    "ZSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "ZT" => "0,1,-2,-1,0,0,0,0,"
    "ZV" => "2,1,-3,-1,0,0,0,0,"
    "ZVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "ZW" => "2,1,-3,0,0,0,0,0,"
    "ZWb" => "2,1,-2,-1,0,0,0,0,"
    "Zb" => "0,0,0,0,0,0,0,1,"
    "Zbps" => "0,0,-1,0,0,0,0,1,"
    "Zcd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "Zcentury" => "0,0,1,0,0,0,0,0,"
    "ZeV" => "2,1,-2,0,0,0,0,0,"
    "Zflops" => "0,0,-1,0,0,0,0,0,flop:1"
    "Zfortnight" => "0,0,1,0,0,0,0,0,"
    "Zg" => "0,1,0,0,0,0,0,0,"
    "ZiB" => "0,0,0,0,0,0,0,1,"
    "Zib" => "0,0,0,0,0,0,0,1,"
    "Zkat" => "0,0,-1,0,0,1,0,0,"
    "Zl" => "3,0,0,0,0,0,0,0,"
    "Zlm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "Zlx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "Zm" => "1,0,0,0,0,0,0,0,"
    "Zmol" => "0,0,0,0,0,1,0,0,"
    "Zpc" => "1,0,0,0,0,0,0,0,"
    "Zs" => "0,0,1,0,0,0,0,0,"
    "Zt" => "0,1,0,0,0,0,0,0,"
    "Zvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "ZΩ" => "2,1,-3,-2,0,0,0,0,"
    "a0" => "1,0,0,0,0,0,0,0,"
    "aA" => "0,0,0,1,0,0,0,0,"
    "aB" => "0,0,0,0,0,0,0,1,"
    "aBps" => "0,0,-1,0,0,0,0,1,"
    "aBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "aC" => "0,0,1,1,0,0,0,0,"
    "aDa" => "0,1,0,0,0,0,0,0,"
    "aF" => "-2,-1,4,2,0,0,0,0,"
    "aGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "aH" => "2,1,-2,-2,0,0,0,0,"
    "aHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "aJ" => "2,1,-2,0,0,0,0,0,"
    "aJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "aK" => "0,0,0,0,1,0,0,0,"
    "aL" => "3,0,0,0,0,0,0,0,"
    "aN" => "1,1,-2,0,0,0,0,0,"
    "aPa" => "-1,1,-2,0,0,0,0,0,"
    "aS" => "-2,-1,3,2,0,0,0,0,"
    "aSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "aT" => "0,1,-2,-1,0,0,0,0,"
    "aV" => "2,1,-3,-1,0,0,0,0,"
    "aVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "aW" => "2,1,-3,0,0,0,0,0,"
    "aWb" => "2,1,-2,-1,0,0,0,0,"
    "a_0" => "1,0,0,0,0,0,0,0,"
    "ab" => "0,0,0,0,0,0,0,1,"
    "ab-1" => "-2,0,0,0,0,0,0,0,"
    "abA" => "0,0,0,1,0,0,0,0,"
    "abC" => "0,0,1,1,0,0,0,0,"
    "abF" => "-2,-1,4,2,0,0,0,0,"
    "abH" => "2,1,-2,-2,0,0,0,0,"
    "abV" => "2,1,-3,-1,0,0,0,0,"
    "ab^-1" => "-2,0,0,0,0,0,0,0,"
    "abampere" => "0,0,0,1,0,0,0,0,"
    "abarn" => "2,0,0,0,0,0,0,0,"
    "abcoulomb" => "0,0,1,1,0,0,0,0,"
    "abfarad" => "-2,-1,4,2,0,0,0,0,"
    "abhenry" => "2,1,-2,-2,0,0,0,0,"
    "abinv" => "-2,0,0,0,0,0,0,0,"
    "abohm" => "2,1,-3,-2,0,0,0,0,"
    "abps" => "0,0,-1,0,0,0,0,1,"
    "absolute magnitude" => "0,0,0,0,0,0,0,0,magnitude_absolute:1"
    "absorbed-dose rad" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "abvolt" => "2,1,-3,-1,0,0,0,0,"
    "abΩ" => "2,1,-3,-2,0,0,0,0,"
    "ab⁻¹" => "-2,0,0,0,0,0,0,0,"
    "ac" => "2,0,0,0,0,0,0,0,"
    "acd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "acentury" => "0,0,1,0,0,0,0,0,"
    "acre" => "2,0,0,0,0,0,0,0,"
    "acres" => "2,0,0,0,0,0,0,0,"
    "aeV" => "2,1,-2,0,0,0,0,0,"
    "afortnight" => "0,0,1,0,0,0,0,0,"
    "ag" => "0,1,0,0,0,0,0,0,"
    "akat" => "0,0,-1,0,0,1,0,0,"
    "al" => "3,0,0,0,0,0,0,0,"
    "alm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "alpha" => "0,0,0,0,0,0,0,0,"
    "altuve" => "1,0,0,0,0,0,0,0,"
    "altuves" => "1,0,0,0,0,0,0,0,"
    "alx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "am" => "1,0,0,0,0,0,0,0,"
    "amah" => "1,0,0,0,0,0,0,0,"
    "amol" => "0,0,0,0,0,1,0,0,"
    "amot" => "1,0,0,0,0,0,0,0,"
    "amp hours" => "0,0,1,1,0,0,0,0,"
    "ampere" => "0,0,0,1,0,0,0,0,"
    "ampere hour" => "0,0,1,1,0,0,0,0,"
    "ampere-hour" => "0,0,1,1,0,0,0,0,"
    "amperes" => "0,0,0,1,0,0,0,0,"
    "amperes per square meter" => "-2,0,0,1,0,0,0,0,"
    "amphora" => "3,0,0,0,0,0,0,0,"
    "amphorae" => "3,0,0,0,0,0,0,0,"
    "amphoras" => "3,0,0,0,0,0,0,0,"
    "angstrom" => "1,0,0,0,0,0,0,0,"
    "angstroms" => "1,0,0,0,0,0,0,0,"
    "angular acceleration" => "0,0,-2,0,0,0,0,0,angle:1"
    "angular velocity" => "0,0,-1,0,0,0,0,0,angle:1"
    "apc" => "1,0,0,0,0,0,0,0,"
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
    "as" => "0,0,1,0,0,0,0,0,"
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
    "avar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "aΩ" => "2,1,-3,-2,0,0,0,0,"
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
    "baud" => "0,0,-1,0,0,0,0,0,symbol:1"
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
    "biot" => "0,0,0,1,0,0,0,0,"
    "bit" => "0,0,0,0,0,0,0,1,"
    "bit/(s·Hz)" => "0,0,0,0,0,0,0,1,spectral_efficiency:1"
    "bit/s" => "0,0,-1,0,0,0,0,1,"
    "bit/s/Hz" => "0,0,0,0,0,0,0,1,spectral_efficiency:1"
    "bit/symbol" => "0,0,0,0,0,0,0,1,symbol:-1"
    "bits" => "0,0,0,0,0,0,0,1,"
    "bits per second per hertz" => "0,0,0,0,0,0,0,1,spectral_efficiency:1"
    "bits per symbol" => "0,0,0,0,0,0,0,1,symbol:-1"
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
    "cA" => "0,0,0,1,0,0,0,0,"
    "cB" => "0,0,0,0,0,0,0,1,"
    "cBps" => "0,0,-1,0,0,0,0,1,"
    "cBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "cC" => "0,0,1,1,0,0,0,0,"
    "cDa" => "0,1,0,0,0,0,0,0,"
    "cF" => "-2,-1,4,2,0,0,0,0,"
    "cGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "cH" => "2,1,-2,-2,0,0,0,0,"
    "cHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "cJ" => "2,1,-2,0,0,0,0,0,"
    "cJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "cK" => "0,0,0,0,1,0,0,0,"
    "cL" => "3,0,0,0,0,0,0,0,"
    "cN" => "1,1,-2,0,0,0,0,0,"
    "cP" => "-1,1,-1,0,0,0,0,0,"
    "cPa" => "-1,1,-2,0,0,0,0,0,"
    "cS" => "-2,-1,3,2,0,0,0,0,"
    "cSt" => "2,0,-1,0,0,0,0,0,"
    "cSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "cT" => "0,1,-2,-1,0,0,0,0,"
    "cV" => "2,1,-3,-1,0,0,0,0,"
    "cVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "cW" => "2,1,-3,0,0,0,0,0,"
    "cWb" => "2,1,-2,-1,0,0,0,0,"
    "cable" => "1,0,0,0,0,0,0,0,"
    "cable length" => "1,0,0,0,0,0,0,0,"
    "cable lengths" => "1,0,0,0,0,0,0,0,"
    "cable_length" => "1,0,0,0,0,0,0,0,"
    "cables" => "1,0,0,0,0,0,0,0,"
    "cal" => "2,1,-2,0,0,0,0,0,"
    "cal_IT" => "2,1,-2,0,0,0,0,0,"
    "cal_th" => "2,1,-2,0,0,0,0,0,"
    "calorie" => "2,1,-2,0,0,0,0,0,"
    "calorie IT" => "2,1,-2,0,0,0,0,0,"
    "calories" => "2,1,-2,0,0,0,0,0,"
    "candela" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "candela per square meter" => "-2,0,0,0,0,0,1,0,luminance:1"
    "candelas" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "carat" => "0,1,0,0,0,0,0,0,"
    "carats" => "0,1,0,0,0,0,0,0,"
    "catalytic activity concentration" => "-3,0,-1,0,0,1,0,0,"
    "cb" => "0,0,0,0,0,0,0,1,"
    "cbps" => "0,0,-1,0,0,0,0,1,"
    "ccd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "ccentury" => "0,0,1,0,0,0,0,0,"
    "cd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "cd/m²" => "-2,0,0,0,0,0,1,0,luminance:1"
    "ceV" => "2,1,-2,0,0,0,0,0,"
    "cell" => "0,0,0,0,0,0,0,0,cell_count:1"
    "cells" => "0,0,0,0,0,0,0,0,cell_count:1"
    "cells/mL" => "-3,0,0,0,0,0,0,0,cell_count:1"
    "celsius" => "0,0,0,0,1,0,0,0,"
    "celsius difference" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "cent" => "0,0,0,0,0,0,0,0,pitch:1"
    "cent_pitch" => "0,0,0,0,0,0,0,0,pitch:1"
    "centipoise" => "-1,1,-1,0,0,0,0,0,"
    "centistokes" => "2,0,-1,0,0,0,0,0,"
    "cents" => "0,0,0,0,0,0,0,0,pitch:1"
    "centuries" => "0,0,1,0,0,0,0,0,"
    "century" => "0,0,1,0,0,0,0,0,"
    "cfortnight" => "0,0,1,0,0,0,0,0,"
    "cg" => "0,1,0,0,0,0,0,0,"
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
    "ckat" => "0,0,-1,0,0,1,0,0,"
    "cl" => "3,0,0,0,0,0,0,0,"
    "clm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "clo" => "0,-1,3,0,1,0,0,0,"
    "clo unit" => "0,-1,3,0,1,0,0,0,"
    "cloth nail" => "1,0,0,0,0,0,0,0,"
    "cluster" => "0,0,0,0,0,0,0,1,"
    "clusters" => "0,0,0,0,0,0,0,1,"
    "clx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "cm" => "1,0,0,0,0,0,0,0,"
    "cm-1" => "-1,0,0,0,0,0,0,0,"
    "cmH2O" => "-1,1,-2,0,0,0,0,0,"
    "cm^-1" => "-1,0,0,0,0,0,0,0,"
    "cmol" => "0,0,0,0,0,1,0,0,"
    "cm²" => "2,0,0,0,0,0,0,0,"
    "cm³" => "3,0,0,0,0,0,0,0,"
    "cm⁻¹" => "-1,0,0,0,0,0,0,0,"
    "colony forming unit" => "0,0,0,0,0,0,0,0,colony_forming_unit:1"
    "colony-forming unit" => "0,0,0,0,0,0,0,0,colony_forming_unit:1"
    "compton wavelength" => "1,0,0,0,0,0,0,0,"
    "compton wavelength electron" => "1,0,0,0,0,0,0,0,"
    "compton wavelength neutron" => "1,0,0,0,0,0,0,0,"
    "compton wavelength proton" => "1,0,0,0,0,0,0,0,"
    "compton_e" => "1,0,0,0,0,0,0,0,"
    "compton_n" => "1,0,0,0,0,0,0,0,"
    "compton_p" => "1,0,0,0,0,0,0,0,"
    "compton_wavelength" => "1,0,0,0,0,0,0,0,"
    "conductivity" => "-3,-1,3,2,0,0,0,0,"
    "copies" => "0,0,0,0,0,0,0,0,molecular_copy:1"
    "copies/mL" => "-3,0,0,0,0,0,0,0,molecular_copy:1"
    "copy" => "0,0,0,0,0,0,0,0,molecular_copy:1"
    "cord" => "3,0,0,0,0,0,0,0,"
    "cords" => "3,0,0,0,0,0,0,0,"
    "coulomb" => "0,0,1,1,0,0,0,0,"
    "coulombs" => "0,0,1,1,0,0,0,0,"
    "coulombs per cubic meter" => "-3,0,1,1,0,0,0,0,"
    "count" => "0,0,0,0,0,0,0,0,detector_count:1"
    "counts per minute" => "0,0,-1,0,0,0,0,0,detector_count:1"
    "counts per second" => "0,0,-1,0,0,0,0,0,detector_count:1"
    "cpc" => "1,0,0,0,0,0,0,0,"
    "cpm" => "0,0,-1,0,0,0,0,0,detector_count:1"
    "cps" => "0,0,-1,0,0,0,0,0,detector_count:1"
    "crumb" => "0,0,0,0,0,0,0,1,"
    "crumbs" => "0,0,0,0,0,0,0,1,"
    "cs" => "0,0,1,0,0,0,0,0,"
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
    "cvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "cwt" => "0,1,0,0,0,0,0,0,"
    "cyc" => "0,0,0,0,0,0,0,0,cycle:1"
    "cycle" => "0,0,0,0,0,0,0,0,cycle:1"
    "cycles" => "0,0,0,0,0,0,0,0,cycle:1"
    "cΩ" => "2,1,-3,-2,0,0,0,0,"
    "d" => "0,0,1,0,0,0,0,0,"
    "dA" => "0,0,0,1,0,0,0,0,"
    "dB" => "0,0,0,0,0,0,0,1,"
    "dBps" => "0,0,-1,0,0,0,0,1,"
    "dBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "dC" => "0,0,1,1,0,0,0,0,"
    "dDa" => "0,1,0,0,0,0,0,0,"
    "dF" => "-2,-1,4,2,0,0,0,0,"
    "dGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "dH" => "2,1,-2,-2,0,0,0,0,"
    "dHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "dJ" => "2,1,-2,0,0,0,0,0,"
    "dJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "dK" => "0,0,0,0,1,0,0,0,"
    "dL" => "3,0,0,0,0,0,0,0,"
    "dN" => "1,1,-2,0,0,0,0,0,"
    "dPa" => "-1,1,-2,0,0,0,0,0,"
    "dS" => "-2,-1,3,2,0,0,0,0,"
    "dSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "dT" => "0,1,-2,-1,0,0,0,0,"
    "dV" => "2,1,-3,-1,0,0,0,0,"
    "dVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "dW" => "2,1,-3,0,0,0,0,0,"
    "dWb" => "2,1,-2,-1,0,0,0,0,"
    "daA" => "0,0,0,1,0,0,0,0,"
    "daB" => "0,0,0,0,0,0,0,1,"
    "daBps" => "0,0,-1,0,0,0,0,1,"
    "daBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "daC" => "0,0,1,1,0,0,0,0,"
    "daDa" => "0,1,0,0,0,0,0,0,"
    "daF" => "-2,-1,4,2,0,0,0,0,"
    "daGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "daH" => "2,1,-2,-2,0,0,0,0,"
    "daHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "daJ" => "2,1,-2,0,0,0,0,0,"
    "daJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "daK" => "0,0,0,0,1,0,0,0,"
    "daL" => "3,0,0,0,0,0,0,0,"
    "daN" => "1,1,-2,0,0,0,0,0,"
    "daPa" => "-1,1,-2,0,0,0,0,0,"
    "daS" => "-2,-1,3,2,0,0,0,0,"
    "daSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "daT" => "0,1,-2,-1,0,0,0,0,"
    "daV" => "2,1,-3,-1,0,0,0,0,"
    "daVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "daW" => "2,1,-3,0,0,0,0,0,"
    "daWb" => "2,1,-2,-1,0,0,0,0,"
    "dab" => "0,0,0,0,0,0,0,1,"
    "dabps" => "0,0,-1,0,0,0,0,1,"
    "dacd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "dacentury" => "0,0,1,0,0,0,0,0,"
    "daeV" => "2,1,-2,0,0,0,0,0,"
    "dafortnight" => "0,0,1,0,0,0,0,0,"
    "dag" => "0,1,0,0,0,0,0,0,"
    "dakat" => "0,0,-1,0,0,1,0,0,"
    "dal" => "3,0,0,0,0,0,0,0,"
    "dalm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "dalton" => "0,1,0,0,0,0,0,0,"
    "daltons" => "0,1,0,0,0,0,0,0,"
    "dalx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "dam" => "1,0,0,0,0,0,0,0,"
    "damol" => "0,0,0,0,0,1,0,0,"
    "dan_cn" => "0,1,0,0,0,0,0,0,"
    "dapc" => "1,0,0,0,0,0,0,0,"
    "darcies" => "2,0,0,0,0,0,0,0,"
    "darcy" => "2,0,0,0,0,0,0,0,"
    "das" => "0,0,1,0,0,0,0,0,"
    "dash" => "3,0,0,0,0,0,0,0,"
    "dashes" => "3,0,0,0,0,0,0,0,"
    "dat" => "0,1,0,0,0,0,0,0,"
    "davar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "day" => "0,0,1,0,0,0,0,0,"
    "days" => "0,0,1,0,0,0,0,0,"
    "daΩ" => "2,1,-3,-2,0,0,0,0,"
    "db" => "0,0,0,0,0,0,0,1,"
    "dbps" => "0,0,-1,0,0,0,0,1,"
    "dcd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "dcentury" => "0,0,1,0,0,0,0,0,"
    "deV" => "2,1,-2,0,0,0,0,0,"
    "debye" => "1,0,1,1,0,0,0,0,"
    "debyes" => "1,0,1,1,0,0,0,0,"
    "decade" => "0,0,1,0,0,0,0,0,"
    "decades" => "0,0,1,0,0,0,0,0,"
    "decay" => "0,0,0,0,0,0,0,0,decay:1"
    "decays" => "0,0,0,0,0,0,0,0,decay:1"
    "decays per minute" => "0,0,-1,0,0,0,0,0,decay:1"
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
    "dfortnight" => "0,0,1,0,0,0,0,0,"
    "dg" => "0,1,0,0,0,0,0,0,"
    "didot" => "1,0,0,0,0,0,0,0,"
    "digit" => "1,0,0,0,0,0,0,0,"
    "digits" => "1,0,0,0,0,0,0,0,"
    "diopter" => "-1,0,0,0,0,0,0,0,"
    "diopters" => "-1,0,0,0,0,0,0,0,"
    "dioptre" => "-1,0,0,0,0,0,0,0,"
    "dioptres" => "-1,0,0,0,0,0,0,0,"
    "dit" => "0,0,0,0,0,0,0,1,"
    "dits" => "0,0,0,0,0,0,0,1,"
    "dkat" => "0,0,-1,0,0,1,0,0,"
    "dl" => "3,0,0,0,0,0,0,0,"
    "dlm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "dlx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "dm" => "1,0,0,0,0,0,0,0,"
    "dmol" => "0,0,0,0,0,1,0,0,"
    "dobson unit" => "-2,0,0,0,0,1,0,0,"
    "dobson units" => "-2,0,0,0,0,1,0,0,"
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
    "dpc" => "1,0,0,0,0,0,0,0,"
    "dpi" => "-1,0,0,0,0,0,0,0,"
    "dpm" => "0,0,-1,0,0,0,0,0,decay:1"
    "dppx" => "-1,0,0,0,0,0,0,0,"
    "dr" => "0,1,0,0,0,0,0,0,"
    "drachm" => "0,1,0,0,0,0,0,0,"
    "drams" => "0,1,0,0,0,0,0,0,"
    "drop" => "3,0,0,0,0,0,0,0,"
    "drops" => "3,0,0,0,0,0,0,0,"
    "ds" => "0,0,1,0,0,0,0,0,"
    "dt" => "0,1,0,0,0,0,0,0,"
    "dvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "dword" => "0,0,0,0,0,0,0,1,"
    "dwords" => "0,0,0,0,0,0,0,1,"
    "dwt" => "0,1,0,0,0,0,0,0,"
    "dyn" => "1,1,-2,0,0,0,0,0,"
    "dyne" => "1,1,-2,0,0,0,0,0,"
    "dynes" => "1,1,-2,0,0,0,0,0,"
    "dΩ" => "2,1,-3,-2,0,0,0,0,"
    "eV" => "2,1,-2,0,0,0,0,0,"
    "earth mass" => "0,1,0,0,0,0,0,0,"
    "earth radius" => "1,0,0,0,0,0,0,0,"
    "earthmass" => "0,1,0,0,0,0,0,0,"
    "earthradius" => "1,0,0,0,0,0,0,0,"
    "edge" => "0,0,0,0,0,0,0,0,graph_edge:1"
    "edges" => "0,0,0,0,0,0,0,0,graph_edge:1"
    "egypt_palm" => "1,0,0,0,0,0,0,0,"
    "egyptian palm" => "1,0,0,0,0,0,0,0,"
    "egyptian palms" => "1,0,0,0,0,0,0,0,"
    "einstein" => "0,0,0,0,0,1,0,0,photon:1"
    "einsteins" => "0,0,0,0,0,1,0,0,photon:1"
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
    "enzyme unit" => "0,0,-1,0,0,1,0,0,"
    "enzyme units" => "0,0,-1,0,0,1,0,0,"
    "eotvos" => "0,0,-2,0,0,0,0,0,"
    "ephah" => "3,0,0,0,0,0,0,0,"
    "ephahs" => "3,0,0,0,0,0,0,0,"
    "ephas" => "3,0,0,0,0,0,0,0,"
    "equivalent" => "0,0,0,0,0,1,0,0,chemical_equivalent:1"
    "equivalents" => "0,0,0,0,0,1,0,0,chemical_equivalent:1"
    "erg" => "2,1,-2,0,0,0,0,0,"
    "etzba" => "1,0,0,0,0,0,0,0,"
    "etzbaot" => "1,0,0,0,0,0,0,0,"
    "ev" => "0,0,0,0,0,0,0,0,exposure_value:1"
    "e₀" => "0,0,0,0,0,0,0,0,e₀:1"
    "f stop" => "0,0,0,0,0,0,0,0,f_stop:1"
    "f-stop" => "0,0,0,0,0,0,0,0,f_stop:1"
    "f-stops" => "0,0,0,0,0,0,0,0,f_stop:1"
    "fA" => "0,0,0,1,0,0,0,0,"
    "fB" => "0,0,0,0,0,0,0,1,"
    "fBps" => "0,0,-1,0,0,0,0,1,"
    "fBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "fC" => "0,0,1,1,0,0,0,0,"
    "fDa" => "0,1,0,0,0,0,0,0,"
    "fF" => "-2,-1,4,2,0,0,0,0,"
    "fGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "fH" => "2,1,-2,-2,0,0,0,0,"
    "fHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "fJ" => "2,1,-2,0,0,0,0,0,"
    "fJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "fK" => "0,0,0,0,1,0,0,0,"
    "fL" => "-2,0,0,0,0,0,1,0,luminance:1"
    "fN" => "1,1,-2,0,0,0,0,0,"
    "fPa" => "-1,1,-2,0,0,0,0,0,"
    "fS" => "-2,-1,3,2,0,0,0,0,"
    "fSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "fT" => "0,1,-2,-1,0,0,0,0,"
    "fV" => "2,1,-3,-1,0,0,0,0,"
    "fVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "fW" => "2,1,-3,0,0,0,0,0,"
    "fWb" => "2,1,-2,-1,0,0,0,0,"
    "f_stop" => "0,0,0,0,0,0,0,0,f_stop:1"
    "fahrenheit" => "0,0,0,0,1,0,0,0,"
    "fahrenheit difference" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "farad" => "-2,-1,4,2,0,0,0,0,"
    "farads" => "-2,-1,4,2,0,0,0,0,"
    "fathom" => "1,0,0,0,0,0,0,0,"
    "fathoms" => "1,0,0,0,0,0,0,0,"
    "fb" => "0,0,0,0,0,0,0,1,"
    "fb-1" => "-2,0,0,0,0,0,0,0,"
    "fb^-1" => "-2,0,0,0,0,0,0,0,"
    "fbarn" => "2,0,0,0,0,0,0,0,"
    "fbinv" => "-2,0,0,0,0,0,0,0,"
    "fbps" => "0,0,-1,0,0,0,0,1,"
    "fb⁻¹" => "-2,0,0,0,0,0,0,0,"
    "fc" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "fcd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "fcentury" => "0,0,1,0,0,0,0,0,"
    "feV" => "2,1,-2,0,0,0,0,0,"
    "feet" => "1,0,0,0,0,0,0,0,"
    "feet of water" => "-1,1,-2,0,0,0,0,0,"
    "femtobarn" => "2,0,0,0,0,0,0,0,"
    "femtobarns" => "2,0,0,0,0,0,0,0,"
    "fen" => "1,0,0,0,0,0,0,0,"
    "fens" => "1,0,0,0,0,0,0,0,"
    "ffortnight" => "0,0,1,0,0,0,0,0,"
    "fg" => "0,1,0,0,0,0,0,0,"
    "fine structure constant" => "0,0,0,0,0,0,0,0,"
    "fine_structure" => "0,0,0,0,0,0,0,0,"
    "fingerbreadth" => "1,0,0,0,0,0,0,0,"
    "firkin" => "3,0,0,0,0,0,0,0,"
    "firkins" => "3,0,0,0,0,0,0,0,"
    "fkat" => "0,0,-1,0,0,1,0,0,"
    "fl" => "3,0,0,0,0,0,0,0,"
    "fl dr" => "3,0,0,0,0,0,0,0,"
    "fl oz" => "3,0,0,0,0,0,0,0,"
    "fldr" => "3,0,0,0,0,0,0,0,"
    "flm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "flop" => "0,0,0,0,0,0,0,0,flop:1"
    "flop/J" => "-2,-1,2,0,0,0,0,0,flop:1"
    "flops" => "0,0,-1,0,0,0,0,0,flop:1"
    "flops per joule" => "-2,-1,2,0,0,0,0,0,flop:1"
    "flops_count" => "0,0,0,0,0,0,0,0,flop:1"
    "floz" => "3,0,0,0,0,0,0,0,"
    "fluid dram" => "3,0,0,0,0,0,0,0,"
    "fluid drams" => "3,0,0,0,0,0,0,0,"
    "fluid ounce" => "3,0,0,0,0,0,0,0,"
    "fluid ounces" => "3,0,0,0,0,0,0,0,"
    "flx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "fm" => "1,0,0,0,0,0,0,0,"
    "fmol" => "0,0,0,0,0,1,0,0,"
    "foe" => "2,1,-2,0,0,0,0,0,"
    "foes" => "2,1,-2,0,0,0,0,0,"
    "foot" => "1,0,0,0,0,0,0,0,"
    "foot candle" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "foot candles" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "foot of water" => "-1,1,-2,0,0,0,0,0,"
    "foot pound" => "2,1,-2,0,0,0,0,0,"
    "foot pounds" => "2,1,-2,0,0,0,0,0,"
    "foot-candle" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "foot-lambert" => "-2,0,0,0,0,0,1,0,luminance:1"
    "foot-pound" => "2,1,-2,0,0,0,0,0,"
    "foot-pounds" => "2,1,-2,0,0,0,0,0,"
    "fortnight" => "0,0,1,0,0,0,0,0,"
    "fortnights" => "0,0,1,0,0,0,0,0,"
    "fpc" => "1,0,0,0,0,0,0,0,"
    "fps" => "0,0,-1,0,0,0,0,0,frame:1"
    "frame" => "0,0,0,0,0,0,0,0,frame:1"
    "frames" => "0,0,0,0,0,0,0,0,frame:1"
    "frames per second" => "0,0,-1,0,0,0,0,0,frame:1"
    "franklin" => "0,0,1,1,0,0,0,0,"
    "french gauge" => "1,0,0,0,0,0,0,0,"
    "french_gauge" => "1,0,0,0,0,0,0,0,"
    "fs" => "0,0,1,0,0,0,0,0,"
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
    "fvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "fΩ" => "2,1,-3,-2,0,0,0,0,"
    "g" => "0,1,0,0,0,0,0,0,"
    "g CO2e" => "0,1,0,0,0,0,0,0,co2e:1"
    "g/L" => "-3,1,0,0,0,0,0,0,"
    "g/dL" => "-3,1,0,0,0,0,0,0,"
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
    "geopotential meter" => "2,0,-2,0,0,0,0,0,geopotential:1"
    "geopotential metre" => "2,0,-2,0,0,0,0,0,geopotential:1"
    "gerah" => "0,1,0,0,0,0,0,0,"
    "gerahs" => "0,1,0,0,0,0,0,0,"
    "giga-updates per second" => "0,0,-1,0,0,0,0,0,cell_update:1"
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
    "gpm" => "2,0,-2,0,0,0,0,0,geopotential:1"
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
    "hA" => "0,0,0,1,0,0,0,0,"
    "hB" => "0,0,0,0,0,0,0,1,"
    "hBps" => "0,0,-1,0,0,0,0,1,"
    "hBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "hC" => "0,0,1,1,0,0,0,0,"
    "hDa" => "0,1,0,0,0,0,0,0,"
    "hF" => "-2,-1,4,2,0,0,0,0,"
    "hGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "hH" => "2,1,-2,-2,0,0,0,0,"
    "hHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "hJ" => "2,1,-2,0,0,0,0,0,"
    "hJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "hK" => "0,0,0,0,1,0,0,0,"
    "hL" => "3,0,0,0,0,0,0,0,"
    "hN" => "1,1,-2,0,0,0,0,0,"
    "hPa" => "-1,1,-2,0,0,0,0,0,"
    "hS" => "-2,-1,3,2,0,0,0,0,"
    "hSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "hT" => "0,1,-2,-1,0,0,0,0,"
    "hV" => "2,1,-3,-1,0,0,0,0,"
    "hVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "hW" => "2,1,-3,0,0,0,0,0,"
    "hWb" => "2,1,-2,-1,0,0,0,0,"
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
    "hb" => "0,0,0,0,0,0,0,1,"
    "hbps" => "0,0,-1,0,0,0,0,1,"
    "hcd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "hcentury" => "0,0,1,0,0,0,0,0,"
    "heV" => "2,1,-2,0,0,0,0,0,"
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
    "hfortnight" => "0,0,1,0,0,0,0,0,"
    "hg" => "0,1,0,0,0,0,0,0,"
    "hin" => "3,0,0,0,0,0,0,0,"
    "hins" => "3,0,0,0,0,0,0,0,"
    "hkat" => "0,0,-1,0,0,1,0,0,"
    "hl" => "3,0,0,0,0,0,0,0,"
    "hlm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "hlx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "hm" => "1,0,0,0,0,0,0,0,"
    "hmol" => "0,0,0,0,0,1,0,0,"
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
    "hpc" => "1,0,0,0,0,0,0,0,"
    "hs" => "0,0,1,0,0,0,0,0,"
    "ht" => "0,1,0,0,0,0,0,0,"
    "hvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "hΩ" => "2,1,-3,-2,0,0,0,0,"
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
    "international table calorie" => "2,1,-2,0,0,0,0,0,"
    "international unit" => "0,0,0,0,0,0,0,0,international_unit:1"
    "international units" => "0,0,0,0,0,0,0,0,international_unit:1"
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
    "janskies" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "jansky" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "janskys" => "0,1,-2,0,0,0,0,0,cycle:-1"
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
    "kA" => "0,0,0,1,0,0,0,0,"
    "kB" => "0,0,0,0,0,0,0,1,"
    "kBps" => "0,0,-1,0,0,0,0,1,"
    "kBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "kC" => "0,0,1,1,0,0,0,0,"
    "kDa" => "0,1,0,0,0,0,0,0,"
    "kF" => "-2,-1,4,2,0,0,0,0,"
    "kFLOPS" => "0,0,-1,0,0,0,0,0,flop:1"
    "kGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "kH" => "2,1,-2,-2,0,0,0,0,"
    "kHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "kJ" => "2,1,-2,0,0,0,0,0,"
    "kJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "kK" => "0,0,0,0,1,0,0,0,"
    "kL" => "3,0,0,0,0,0,0,0,"
    "kN" => "1,1,-2,0,0,0,0,0,"
    "kPa" => "-1,1,-2,0,0,0,0,0,"
    "kS" => "-2,-1,3,2,0,0,0,0,"
    "kSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "kT" => "0,1,-2,-1,0,0,0,0,"
    "kV" => "2,1,-3,-1,0,0,0,0,"
    "kVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "kW" => "2,1,-3,0,0,0,0,0,"
    "kWb" => "2,1,-2,-1,0,0,0,0,"
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
    "kb" => "0,0,0,0,0,0,0,1,"
    "kbps" => "0,0,-1,0,0,0,0,1,"
    "kcal" => "2,1,-2,0,0,0,0,0,"
    "kcal_IT" => "2,1,-2,0,0,0,0,0,"
    "kcal_th" => "2,1,-2,0,0,0,0,0,"
    "kcd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "kcentury" => "0,0,1,0,0,0,0,0,"
    "keV" => "2,1,-2,0,0,0,0,0,"
    "kelvin" => "0,0,0,0,1,0,0,0,"
    "kelvin difference" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "kflops" => "0,0,-1,0,0,0,0,0,flop:1"
    "kfortnight" => "0,0,1,0,0,0,0,0,"
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
    "kkat" => "0,0,-1,0,0,1,0,0,"
    "kl" => "3,0,0,0,0,0,0,0,"
    "klm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "klx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "km" => "1,0,0,0,0,0,0,0,"
    "km/h" => "1,0,-1,0,0,0,0,0,"
    "kmol" => "0,0,0,0,0,1,0,0,"
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
    "kpc" => "1,0,0,0,0,0,0,0,"
    "kph" => "1,0,-1,0,0,0,0,0,"
    "ks" => "0,0,1,0,0,0,0,0,"
    "kt" => "1,0,-1,0,0,0,0,0,"
    "ktok/s" => "0,0,-1,0,0,0,0,0,token:1"
    "kvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "kΩ" => "2,1,-3,-2,0,0,0,0,"
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
    "mB" => "0,0,0,0,0,0,0,1,"
    "mBps" => "0,0,-1,0,0,0,0,1,"
    "mBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "mC" => "0,0,1,1,0,0,0,0,"
    "mDa" => "0,1,0,0,0,0,0,0,"
    "mEq/L" => "-3,0,0,0,0,1,0,0,chemical_equivalent:1"
    "mF" => "-2,-1,4,2,0,0,0,0,"
    "mGal" => "1,0,-2,0,0,0,0,0,"
    "mGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "mH" => "2,1,-2,-2,0,0,0,0,"
    "mH2O" => "-1,1,-2,0,0,0,0,0,"
    "mHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "mJ" => "2,1,-2,0,0,0,0,0,"
    "mJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "mK" => "0,0,0,0,1,0,0,0,"
    "mL" => "3,0,0,0,0,0,0,0,"
    "mM" => "-3,0,0,0,0,1,0,0,"
    "mN" => "1,1,-2,0,0,0,0,0,"
    "mOsm/L" => "-3,0,0,0,0,1,0,0,osmotic_entity:1"
    "mPa" => "-1,1,-2,0,0,0,0,0,"
    "mS" => "-2,-1,3,2,0,0,0,0,"
    "mSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "mT" => "0,1,-2,-1,0,0,0,0,"
    "mV" => "2,1,-3,-1,0,0,0,0,"
    "mVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "mW" => "2,1,-3,0,0,0,0,0,"
    "mWb" => "2,1,-2,-1,0,0,0,0,"
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
    "mas" => "0,0,0,0,0,0,0,0,angle:1"
    "mass density" => "-3,1,0,0,0,0,0,0,"
    "mass flow" => "0,1,-1,0,0,0,0,0,"
    "maund" => "0,1,0,0,0,0,0,0,"
    "maunds" => "0,1,0,0,0,0,0,0,"
    "maxwell" => "2,1,-2,-1,0,0,0,0,"
    "maxwells" => "2,1,-2,-1,0,0,0,0,"
    "mb" => "0,0,0,0,0,0,0,1,"
    "mbar" => "-1,1,-2,0,0,0,0,0,"
    "mbps" => "0,0,-1,0,0,0,0,1,"
    "mcd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "mcentury" => "0,0,1,0,0,0,0,0,"
    "meV" => "2,1,-2,0,0,0,0,0,"
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
    "mfortnight" => "0,0,1,0,0,0,0,0,"
    "mg" => "0,1,0,0,0,0,0,0,"
    "mg/L" => "-3,1,0,0,0,0,0,0,"
    "mg/dL" => "-3,1,0,0,0,0,0,0,"
    "mg/dL glucose" => "0,0,0,0,0,0,0,0,glucose_concentration:1"
    "mg/dL_glucose" => "0,0,0,0,0,0,0,0,glucose_concentration:1"
    "mho" => "-2,-1,3,2,0,0,0,0,"
    "mi" => "1,0,0,0,0,0,0,0,"
    "mi/h" => "1,0,-1,0,0,0,0,0,"
    "mickey" => "1,0,0,0,0,0,0,0,"
    "mickeys" => "1,0,0,0,0,0,0,0,"
    "microarcsecond" => "0,0,0,0,0,0,0,0,angle:1"
    "microarcseconds" => "0,0,0,0,0,0,0,0,angle:1"
    "microlife" => "0,0,1,0,0,0,0,0,"
    "microlives" => "0,0,1,0,0,0,0,0,"
    "micromolar" => "-3,0,0,0,0,1,0,0,"
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
    "milliarcsecond" => "0,0,0,0,0,0,0,0,angle:1"
    "milliarcseconds" => "0,0,0,0,0,0,0,0,angle:1"
    "milligal" => "1,0,-2,0,0,0,0,0,"
    "milligals" => "1,0,-2,0,0,0,0,0,"
    "millihelen" => "0,0,0,0,0,0,0,0,beauty:1"
    "millihelens" => "0,0,0,0,0,0,0,0,beauty:1"
    "millimolar" => "-3,0,0,0,0,1,0,0,"
    "mils" => "0,0,0,0,0,0,0,0,angle:1"
    "min" => "0,0,1,0,0,0,0,0,"
    "mina" => "0,1,0,0,0,0,0,0,"
    "minas" => "0,1,0,0,0,0,0,0,"
    "minute" => "0,0,1,0,0,0,0,0,"
    "minutes" => "0,0,1,0,0,0,0,0,"
    "mkat" => "0,0,-1,0,0,1,0,0,"
    "ml" => "3,0,0,0,0,0,0,0,"
    "mlm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "mlx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "mm" => "1,0,0,0,0,0,0,0,"
    "mmHg" => "-1,1,-2,0,0,0,0,0,"
    "mmol" => "0,0,0,0,0,1,0,0,"
    "mmol/L" => "-3,0,0,0,0,1,0,0,"
    "mmol/L glucose" => "0,0,0,0,0,0,0,0,glucose_concentration:1"
    "mmol/L_glucose" => "0,0,0,0,0,0,0,0,glucose_concentration:1"
    "mo" => "0,0,1,0,0,0,0,0,"
    "mohs" => "0,0,0,0,0,0,0,0,hardness_mohs:1"
    "mol" => "0,0,0,0,0,1,0,0,"
    "mol/L" => "-3,0,0,0,0,1,0,0,"
    "mol/mol" => "0,0,0,0,0,0,0,0,ratio:1"
    "mol/m³" => "-3,0,0,0,0,1,0,0,"
    "mol_photon/m²/s" => "-2,0,-1,0,0,1,0,0,photon:1"
    "molal" => "0,-1,0,0,0,1,0,0,"
    "molar" => "-3,0,0,0,0,1,0,0,"
    "molar concentration" => "-3,0,0,0,0,1,0,0,"
    "molarity" => "-3,0,0,0,0,1,0,0,"
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
    "mpc" => "1,0,0,0,0,0,0,0,"
    "mpg" => "-2,0,0,0,0,0,0,0,"
    "mpge" => "-2,0,0,0,0,0,0,0,"
    "mph" => "1,0,-1,0,0,0,0,0,"
    "ms" => "0,0,1,0,0,0,0,0,"
    "mt" => "0,1,0,0,0,0,0,0,"
    "mu" => "2,0,0,0,0,0,0,0,"
    "muB" => "2,0,0,1,0,0,0,0,"
    "muon mass" => "0,1,0,0,0,0,0,0,"
    "muon_mass" => "0,1,0,0,0,0,0,0,"
    "mus" => "2,0,0,0,0,0,0,0,"
    "mvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "m²" => "2,0,0,0,0,0,0,0,"
    "m³" => "3,0,0,0,0,0,0,0,"
    "m³/(kg·s²)" => "3,-1,-2,0,0,0,0,0,"
    "m³/s" => "3,0,-1,0,0,0,0,0,"
    "mΩ" => "2,1,-3,-2,0,0,0,0,"
    "mₚₗ" => "0,1,0,0,0,0,0,0,"
    "nA" => "0,0,0,1,0,0,0,0,"
    "nB" => "0,0,0,0,0,0,0,1,"
    "nBps" => "0,0,-1,0,0,0,0,1,"
    "nBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "nC" => "0,0,1,1,0,0,0,0,"
    "nDa" => "0,1,0,0,0,0,0,0,"
    "nF" => "-2,-1,4,2,0,0,0,0,"
    "nGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "nH" => "2,1,-2,-2,0,0,0,0,"
    "nHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "nJ" => "2,1,-2,0,0,0,0,0,"
    "nJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "nK" => "0,0,0,0,1,0,0,0,"
    "nL" => "3,0,0,0,0,0,0,0,"
    "nM" => "-3,0,0,0,0,1,0,0,"
    "nN" => "1,1,-2,0,0,0,0,0,"
    "nPa" => "-1,1,-2,0,0,0,0,0,"
    "nS" => "-2,-1,3,2,0,0,0,0,"
    "nSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "nT" => "0,1,-2,-1,0,0,0,0,"
    "nV" => "2,1,-3,-1,0,0,0,0,"
    "nVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "nW" => "2,1,-3,0,0,0,0,0,"
    "nWb" => "2,1,-2,-1,0,0,0,0,"
    "nail_cloth" => "1,0,0,0,0,0,0,0,"
    "nanobarn" => "2,0,0,0,0,0,0,0,"
    "nanobarns" => "2,0,0,0,0,0,0,0,"
    "nanomolar" => "-3,0,0,0,0,1,0,0,"
    "nat" => "0,0,0,0,0,0,0,1,"
    "nats" => "0,0,0,0,0,0,0,1,"
    "nautical mile" => "1,0,0,0,0,0,0,0,"
    "nautical miles" => "1,0,0,0,0,0,0,0,"
    "nb" => "0,0,0,0,0,0,0,1,"
    "nb-1" => "-2,0,0,0,0,0,0,0,"
    "nb^-1" => "-2,0,0,0,0,0,0,0,"
    "nbarn" => "2,0,0,0,0,0,0,0,"
    "nbps" => "0,0,-1,0,0,0,0,1,"
    "nb⁻¹" => "-2,0,0,0,0,0,0,0,"
    "ncd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "ncentury" => "0,0,1,0,0,0,0,0,"
    "neV" => "2,1,-2,0,0,0,0,0,"
    "nebuchadnezzar" => "3,0,0,0,0,0,0,0,"
    "nebuchadnezzars" => "3,0,0,0,0,0,0,0,"
    "neutron mass" => "0,1,0,0,0,0,0,0,"
    "neutron_mass" => "0,1,0,0,0,0,0,0,"
    "newton" => "1,1,-2,0,0,0,0,0,"
    "newtons" => "1,1,-2,0,0,0,0,0,"
    "newtons per meter" => "0,1,-2,0,0,0,0,0,"
    "nfortnight" => "0,0,1,0,0,0,0,0,"
    "ng" => "0,1,0,0,0,0,0,0,"
    "ng/mL" => "-3,1,0,0,0,0,0,0,"
    "nibble" => "0,0,0,0,0,0,0,1,"
    "nibbles" => "0,0,0,0,0,0,0,1,"
    "nit" => "-2,0,0,0,0,0,1,0,luminance:1"
    "nits" => "-2,0,0,0,0,0,1,0,luminance:1"
    "nkat" => "0,0,-1,0,0,1,0,0,"
    "nl" => "3,0,0,0,0,0,0,0,"
    "nlm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "nlx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "nm" => "1,0,0,0,0,0,0,0,"
    "nmi" => "1,0,0,0,0,0,0,0,"
    "nmol" => "0,0,0,0,0,1,0,0,"
    "nmol/L" => "-3,0,0,0,0,1,0,0,"
    "nominal solar luminosity" => "2,1,-3,0,0,0,0,0,"
    "nominal solar radius" => "1,0,0,0,0,0,0,0,"
    "normality" => "-3,0,0,0,0,1,0,0,chemical_equivalent:1"
    "npc" => "1,0,0,0,0,0,0,0,"
    "ns" => "0,0,1,0,0,0,0,0,"
    "nt" => "0,1,0,0,0,0,0,0,"
    "nvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "nΩ" => "2,1,-3,-2,0,0,0,0,"
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
    "op/J" => "-2,-1,2,0,0,0,0,0,op:1"
    "operations per joule" => "-2,-1,2,0,0,0,0,0,op:1"
    "ops" => "0,0,0,0,0,0,0,0,op:1"
    "ops_per_s" => "0,0,-1,0,0,0,0,0,op:1"
    "osmol" => "0,0,0,0,0,1,0,0,osmotic_entity:1"
    "osmolar" => "-3,0,0,0,0,1,0,0,osmotic_entity:1"
    "osmole" => "0,0,0,0,0,1,0,0,osmotic_entity:1"
    "osmoles" => "0,0,0,0,0,1,0,0,osmotic_entity:1"
    "ounce" => "0,1,0,0,0,0,0,0,"
    "ounces" => "0,1,0,0,0,0,0,0,"
    "outhouse" => "2,0,0,0,0,0,0,0,"
    "oz" => "0,1,0,0,0,0,0,0,"
    "ozt" => "0,1,0,0,0,0,0,0,"
    "pA" => "0,0,0,1,0,0,0,0,"
    "pB" => "0,0,0,0,0,0,0,1,"
    "pBps" => "0,0,-1,0,0,0,0,1,"
    "pBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "pC" => "0,0,1,1,0,0,0,0,"
    "pDa" => "0,1,0,0,0,0,0,0,"
    "pF" => "-2,-1,4,2,0,0,0,0,"
    "pGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "pH" => "2,1,-2,-2,0,0,0,0,"
    "pHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "pJ" => "2,1,-2,0,0,0,0,0,"
    "pJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "pK" => "0,0,0,0,1,0,0,0,"
    "pL" => "3,0,0,0,0,0,0,0,"
    "pN" => "1,1,-2,0,0,0,0,0,"
    "pPa" => "-1,1,-2,0,0,0,0,0,"
    "pS" => "-2,-1,3,2,0,0,0,0,"
    "pSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "pT" => "0,1,-2,-1,0,0,0,0,"
    "pV" => "2,1,-3,-1,0,0,0,0,"
    "pVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "pW" => "2,1,-3,0,0,0,0,0,"
    "pWb" => "2,1,-2,-1,0,0,0,0,"
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
    "parts per billion by volume" => "0,0,0,0,0,0,0,0,volume_fraction:1"
    "parts per hundred million" => "0,0,0,0,0,0,0,0,ratio:1"
    "parts per million" => "0,0,0,0,0,0,0,0,ratio:1"
    "parts per million by mass" => "0,0,0,0,0,0,0,0,mass_fraction:1"
    "parts per million by volume" => "0,0,0,0,0,0,0,0,volume_fraction:1"
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
    "pbps" => "0,0,-1,0,0,0,0,1,"
    "pb⁻¹" => "-2,0,0,0,0,0,0,0,"
    "pc" => "1,0,0,0,0,0,0,0,"
    "pcd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "pcentury" => "0,0,1,0,0,0,0,0,"
    "peV" => "2,1,-2,0,0,0,0,0,"
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
    "pfortnight" => "0,0,1,0,0,0,0,0,"
    "pg" => "0,1,0,0,0,0,0,0,"
    "phon" => "0,0,0,0,0,0,0,0,loudness_level:1"
    "phons" => "0,0,0,0,0,0,0,0,loudness_level:1"
    "phot" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "photon" => "0,0,0,0,0,0,0,0,photon:1"
    "photons" => "0,0,0,0,0,0,0,0,photon:1"
    "photosynthetic photon flux density" => "-2,0,-1,0,0,1,0,0,photon:1"
    "phots" => "-2,0,0,0,0,0,1,0,illuminance:1"
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
    "pkat" => "0,0,-1,0,0,1,0,0,"
    "pl" => "3,0,0,0,0,0,0,0,"
    "planck length" => "1,0,0,0,0,0,0,0,"
    "planck mass" => "0,1,0,0,0,0,0,0,"
    "planck time" => "0,0,1,0,0,0,0,0,"
    "plaque forming unit" => "0,0,0,0,0,0,0,0,plaque_forming_unit:1"
    "plaque-forming unit" => "0,0,0,0,0,0,0,0,plaque_forming_unit:1"
    "plm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "plx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "pm" => "1,0,0,0,0,0,0,0,"
    "pmol" => "0,0,0,0,0,1,0,0,"
    "point" => "1,0,0,0,0,0,0,0,"
    "points" => "1,0,0,0,0,0,0,0,"
    "poise" => "-1,1,-1,0,0,0,0,0,"
    "potential vorticity unit" => "2,-1,-1,0,1,0,0,0,"
    "potential vorticity units" => "2,-1,-1,0,1,0,0,0,"
    "pouce" => "1,0,0,0,0,0,0,0,"
    "pouces" => "1,0,0,0,0,0,0,0,"
    "pound" => "0,1,0,0,0,0,0,0,"
    "pound force" => "1,1,-2,0,0,0,0,0,"
    "pound-force" => "1,1,-2,0,0,0,0,0,"
    "pounds" => "0,1,0,0,0,0,0,0,"
    "ppb" => "0,0,0,0,0,0,0,0,ratio:1"
    "ppbv" => "0,0,0,0,0,0,0,0,volume_fraction:1"
    "ppc" => "1,0,0,0,0,0,0,0,"
    "pphm" => "0,0,0,0,0,0,0,0,ratio:1"
    "ppm" => "0,0,0,0,0,0,0,0,ratio:1"
    "ppmv" => "0,0,0,0,0,0,0,0,volume_fraction:1"
    "ppmw" => "0,0,0,0,0,0,0,0,mass_fraction:1"
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
    "pvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "px" => "1,0,0,0,0,0,0,0,"
    "pΩ" => "2,1,-3,-2,0,0,0,0,"
    "qA" => "0,0,0,1,0,0,0,0,"
    "qB" => "0,0,0,0,0,0,0,1,"
    "qBps" => "0,0,-1,0,0,0,0,1,"
    "qBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "qC" => "0,0,1,1,0,0,0,0,"
    "qDa" => "0,1,0,0,0,0,0,0,"
    "qF" => "-2,-1,4,2,0,0,0,0,"
    "qGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "qH" => "2,1,-2,-2,0,0,0,0,"
    "qHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "qJ" => "2,1,-2,0,0,0,0,0,"
    "qJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "qK" => "0,0,0,0,1,0,0,0,"
    "qL" => "3,0,0,0,0,0,0,0,"
    "qN" => "1,1,-2,0,0,0,0,0,"
    "qPa" => "-1,1,-2,0,0,0,0,0,"
    "qS" => "-2,-1,3,2,0,0,0,0,"
    "qSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "qT" => "0,1,-2,-1,0,0,0,0,"
    "qV" => "2,1,-3,-1,0,0,0,0,"
    "qVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "qW" => "2,1,-3,0,0,0,0,0,"
    "qWb" => "2,1,-2,-1,0,0,0,0,"
    "qb" => "0,0,0,0,0,0,0,1,"
    "qbps" => "0,0,-1,0,0,0,0,1,"
    "qcd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "qcentury" => "0,0,1,0,0,0,0,0,"
    "qeV" => "2,1,-2,0,0,0,0,0,"
    "qfortnight" => "0,0,1,0,0,0,0,0,"
    "qg" => "0,1,0,0,0,0,0,0,"
    "qkat" => "0,0,-1,0,0,1,0,0,"
    "ql" => "3,0,0,0,0,0,0,0,"
    "qlm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "qlx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "qm" => "1,0,0,0,0,0,0,0,"
    "qmol" => "0,0,0,0,0,1,0,0,"
    "qpc" => "1,0,0,0,0,0,0,0,"
    "qps" => "0,0,-1,0,0,0,0,0,query:1"
    "qquad" => "0,0,0,0,0,0,0,0,em:1"
    "qr" => "0,1,0,0,0,0,0,0,"
    "qs" => "0,0,1,0,0,0,0,0,"
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
    "qvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "qword" => "0,0,0,0,0,0,0,1,"
    "qwords" => "0,0,0,0,0,0,0,1,"
    "qΩ" => "2,1,-3,-2,0,0,0,0,"
    "rA" => "0,0,0,1,0,0,0,0,"
    "rB" => "0,0,0,0,0,0,0,1,"
    "rBps" => "0,0,-1,0,0,0,0,1,"
    "rBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "rC" => "0,0,1,1,0,0,0,0,"
    "rDa" => "0,1,0,0,0,0,0,0,"
    "rF" => "-2,-1,4,2,0,0,0,0,"
    "rGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "rH" => "2,1,-2,-2,0,0,0,0,"
    "rHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "rJ" => "2,1,-2,0,0,0,0,0,"
    "rJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "rK" => "0,0,0,0,1,0,0,0,"
    "rL" => "3,0,0,0,0,0,0,0,"
    "rN" => "1,1,-2,0,0,0,0,0,"
    "rPa" => "-1,1,-2,0,0,0,0,0,"
    "rS" => "-2,-1,3,2,0,0,0,0,"
    "rSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "rT" => "0,1,-2,-1,0,0,0,0,"
    "rV" => "2,1,-3,-1,0,0,0,0,"
    "rVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "rW" => "2,1,-3,0,0,0,0,0,"
    "rWb" => "2,1,-2,-1,0,0,0,0,"
    "rack unit" => "1,0,0,0,0,0,0,0,"
    "rack units" => "1,0,0,0,0,0,0,0,"
    "rad" => "0,0,0,0,0,0,0,0,angle:1"
    "rad/s" => "0,0,-1,0,0,0,0,0,angle:1"
    "rad/s²" => "0,0,-2,0,0,0,0,0,angle:1"
    "rad_dose" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "radian" => "0,0,0,0,0,0,0,0,angle:1"
    "radiance" => "0,1,-3,0,0,0,0,0,solid_angle:-1"
    "radians" => "0,0,0,0,0,0,0,0,angle:1"
    "radiant exposure" => "0,1,-2,0,0,0,0,0,"
    "radiant intensity" => "2,1,-3,0,0,0,0,0,solid_angle:-1"
    "radiation absorbed dose" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "rankine" => "0,0,0,0,1,0,0,0,"
    "rankine difference" => "0,0,0,0,1,0,0,0,temperature_delta:1"
    "rb" => "0,0,0,0,0,0,0,1,"
    "rbe" => "0,0,0,0,0,0,0,0,rbe:1"
    "rbps" => "0,0,-1,0,0,0,0,1,"
    "rcd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "rcentury" => "0,0,1,0,0,0,0,0,"
    "rd" => "0,0,-1,0,0,0,0,0,decay:1"
    "reV" => "2,1,-2,0,0,0,0,0,"
    "reactive power" => "2,1,-3,0,0,0,0,0,reactive_power:1"
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
    "rfortnight" => "0,0,1,0,0,0,0,0,"
    "rg" => "0,1,0,0,0,0,0,0,"
    "ri" => "1,0,0,0,0,0,0,0,"
    "richter" => "0,0,0,0,0,0,0,0,magnitude:1"
    "richter scale" => "0,0,0,0,0,0,0,0,magnitude:1"
    "rkat" => "0,0,-1,0,0,1,0,0,"
    "rl" => "3,0,0,0,0,0,0,0,"
    "rlm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "rlx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "rm" => "1,0,0,0,0,0,0,0,"
    "rmol" => "0,0,0,0,0,1,0,0,"
    "rockwell" => "0,0,0,0,0,0,0,0,hardness_rockwell:1"
    "rod" => "1,0,0,0,0,0,0,0,"
    "rods" => "1,0,0,0,0,0,0,0,"
    "roentgen" => "0,-1,1,1,0,0,0,0,ionizing_radiation_exposure:1"
    "roentgens" => "0,-1,1,1,0,0,0,0,ionizing_radiation_exposure:1"
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
    "rpc" => "1,0,0,0,0,0,0,0,"
    "rpm" => "0,0,-1,0,0,0,0,0,revolution:1"
    "rps" => "0,0,-1,0,0,0,0,0,request:1"
    "rs" => "0,0,1,0,0,0,0,0,"
    "rt" => "0,1,0,0,0,0,0,0,"
    "rundlet" => "3,0,0,0,0,0,0,0,"
    "rundlets" => "3,0,0,0,0,0,0,0,"
    "russian funt" => "0,1,0,0,0,0,0,0,"
    "russian_funt" => "0,1,0,0,0,0,0,0,"
    "rutherford" => "0,0,-1,0,0,0,0,0,decay:1"
    "rutherfords" => "0,0,-1,0,0,0,0,0,decay:1"
    "rvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "rydberg" => "2,1,-2,0,0,0,0,0,"
    "rydberg_unit" => "2,1,-2,0,0,0,0,0,"
    "rydbergs" => "2,1,-2,0,0,0,0,0,"
    "réaumur" => "0,0,0,0,1,0,0,0,"
    "rømer" => "0,0,0,0,1,0,0,0,"
    "rΩ" => "2,1,-3,-2,0,0,0,0,"
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
    "spectral flux density" => "0,1,-2,0,0,0,0,0,cycle:-1"
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
    "statA" => "0,0,0,1,0,0,0,0,"
    "statC" => "0,0,1,1,0,0,0,0,"
    "statF" => "-2,-1,4,2,0,0,0,0,"
    "statH" => "2,1,-2,-2,0,0,0,0,"
    "statV" => "2,1,-3,-1,0,0,0,0,"
    "statampere" => "0,0,0,1,0,0,0,0,"
    "statcoulomb" => "0,0,1,1,0,0,0,0,"
    "statfarad" => "-2,-1,4,2,0,0,0,0,"
    "stathenry" => "2,1,-2,-2,0,0,0,0,"
    "statohm" => "2,1,-3,-2,0,0,0,0,"
    "statvolt" => "2,1,-3,-1,0,0,0,0,"
    "statΩ" => "2,1,-3,-2,0,0,0,0,"
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
    "svedberg" => "0,0,1,0,0,0,0,0,"
    "svedbergs" => "0,0,1,0,0,0,0,0,"
    "sverdrup" => "3,0,-1,0,0,0,0,0,"
    "sverdrups" => "3,0,-1,0,0,0,0,0,"
    "symbol" => "0,0,0,0,0,0,0,0,symbol:1"
    "symbols" => "0,0,0,0,0,0,0,0,symbol:1"
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
    "thermochemical calorie" => "2,1,-2,0,0,0,0,0,"
    "thermochemical kilocalorie" => "2,1,-2,0,0,0,0,0,"
    "therms" => "2,1,-2,0,0,0,0,0,"
    "tick" => "0,0,0,0,0,0,0,0,tick:1"
    "ticks" => "0,0,0,0,0,0,0,0,tick:1"
    "tierce" => "3,0,0,0,0,0,0,0,"
    "tierces" => "3,0,0,0,0,0,0,0,"
    "tn" => "0,1,0,0,0,0,0,0,"
    "toise" => "1,0,0,0,0,0,0,0,"
    "toises" => "1,0,0,0,0,0,0,0,"
    "tok" => "0,0,0,0,0,0,0,0,token:1"
    "tok/J" => "-2,-1,2,0,0,0,0,0,token:1"
    "tok/s" => "0,0,-1,0,0,0,0,0,token:1"
    "token" => "0,0,0,0,0,0,0,0,token:1"
    "tokens" => "0,0,0,0,0,0,0,0,token:1"
    "tokens per joule" => "-2,-1,2,0,0,0,0,0,token:1"
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
    "total electron content unit" => "-2,0,0,0,0,0,0,0,electron_column_density:1"
    "tps" => "0,0,-1,0,0,0,0,0,transaction:1"
    "transaction" => "0,0,0,0,0,0,0,0,transaction:1"
    "transactions" => "0,0,0,0,0,0,0,0,transaction:1"
    "transfer" => "0,0,0,0,0,0,0,0,transfer:1"
    "transfers" => "0,0,0,0,0,0,0,0,transfer:1"
    "transport carbon intensity" => "-1,1,0,0,0,0,0,0,transport_co2e:1"
    "traversed edges per second" => "0,0,-1,0,0,0,0,0,graph_edge:1"
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
    "uA" => "0,0,0,1,0,0,0,0,"
    "uB" => "0,0,0,0,0,0,0,1,"
    "uBps" => "0,0,-1,0,0,0,0,1,"
    "uBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "uC" => "0,0,1,1,0,0,0,0,"
    "uDa" => "0,1,0,0,0,0,0,0,"
    "uF" => "-2,-1,4,2,0,0,0,0,"
    "uGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "uH" => "2,1,-2,-2,0,0,0,0,"
    "uHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "uJ" => "2,1,-2,0,0,0,0,0,"
    "uJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "uK" => "0,0,0,0,1,0,0,0,"
    "uL" => "3,0,0,0,0,0,0,0,"
    "uM" => "-3,0,0,0,0,1,0,0,"
    "uN" => "1,1,-2,0,0,0,0,0,"
    "uPa" => "-1,1,-2,0,0,0,0,0,"
    "uS" => "-2,-1,3,2,0,0,0,0,"
    "uSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "uT" => "0,1,-2,-1,0,0,0,0,"
    "uV" => "2,1,-3,-1,0,0,0,0,"
    "uVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "uW" => "2,1,-3,0,0,0,0,0,"
    "uWb" => "2,1,-2,-1,0,0,0,0,"
    "uas" => "0,0,0,0,0,0,0,0,angle:1"
    "ub" => "0,0,0,0,0,0,0,1,"
    "ubps" => "0,0,-1,0,0,0,0,1,"
    "ucd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "ucentury" => "0,0,1,0,0,0,0,0,"
    "ueV" => "2,1,-2,0,0,0,0,0,"
    "ufortnight" => "0,0,1,0,0,0,0,0,"
    "ug" => "0,1,0,0,0,0,0,0,"
    "ukat" => "0,0,-1,0,0,1,0,0,"
    "ul" => "3,0,0,0,0,0,0,0,"
    "ulm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "ulx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "um" => "1,0,0,0,0,0,0,0,"
    "umol" => "0,0,0,0,0,1,0,0,"
    "uncia_roma" => "0,1,0,0,0,0,0,0,"
    "upc" => "1,0,0,0,0,0,0,0,"
    "update" => "0,0,0,0,0,0,0,0,cell_update:1"
    "updates" => "0,0,0,0,0,0,0,0,cell_update:1"
    "us" => "0,0,1,0,0,0,0,0,"
    "ut" => "0,1,0,0,0,0,0,0,"
    "uvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "uΩ" => "2,1,-3,-2,0,0,0,0,"
    "var" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "vershok" => "1,0,0,0,0,0,0,0,"
    "vershoks" => "1,0,0,0,0,0,0,0,"
    "verst" => "1,0,0,0,0,0,0,0,"
    "versts" => "1,0,0,0,0,0,0,0,"
    "vh" => "0,0,0,0,0,0,0,0,viewport_height_percent:1"
    "vickers" => "0,0,0,0,0,0,0,0,hardness_vickers:1"
    "viewport height" => "0,0,0,0,0,0,0,0,viewport_height_percent:1"
    "viewport width" => "0,0,0,0,0,0,0,0,viewport_width_percent:1"
    "volt" => "2,1,-3,-1,0,0,0,0,"
    "volt ampere" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "volt-ampere" => "2,1,-3,0,0,0,0,0,apparent_power:1"
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
    "yA" => "0,0,0,1,0,0,0,0,"
    "yB" => "0,0,0,0,0,0,0,1,"
    "yBps" => "0,0,-1,0,0,0,0,1,"
    "yBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "yC" => "0,0,1,1,0,0,0,0,"
    "yDa" => "0,1,0,0,0,0,0,0,"
    "yF" => "-2,-1,4,2,0,0,0,0,"
    "yGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "yH" => "2,1,-2,-2,0,0,0,0,"
    "yHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "yJ" => "2,1,-2,0,0,0,0,0,"
    "yJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "yK" => "0,0,0,0,1,0,0,0,"
    "yL" => "3,0,0,0,0,0,0,0,"
    "yN" => "1,1,-2,0,0,0,0,0,"
    "yPa" => "-1,1,-2,0,0,0,0,0,"
    "yS" => "-2,-1,3,2,0,0,0,0,"
    "ySv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "yT" => "0,1,-2,-1,0,0,0,0,"
    "yV" => "2,1,-3,-1,0,0,0,0,"
    "yVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "yW" => "2,1,-3,0,0,0,0,0,"
    "yWb" => "2,1,-2,-1,0,0,0,0,"
    "yard" => "1,0,0,0,0,0,0,0,"
    "yards" => "1,0,0,0,0,0,0,0,"
    "yb" => "0,0,0,0,0,0,0,1,"
    "ybps" => "0,0,-1,0,0,0,0,1,"
    "ycd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "ycentury" => "0,0,1,0,0,0,0,0,"
    "yd" => "1,0,0,0,0,0,0,0,"
    "yeV" => "2,1,-2,0,0,0,0,0,"
    "year" => "0,0,1,0,0,0,0,0,"
    "years" => "0,0,1,0,0,0,0,0,"
    "yfortnight" => "0,0,1,0,0,0,0,0,"
    "yg" => "0,1,0,0,0,0,0,0,"
    "ykat" => "0,0,-1,0,0,1,0,0,"
    "yl" => "3,0,0,0,0,0,0,0,"
    "ylm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "ylx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "ym" => "1,0,0,0,0,0,0,0,"
    "ymol" => "0,0,0,0,0,1,0,0,"
    "yovel" => "0,0,1,0,0,0,0,0,"
    "yovels" => "0,0,1,0,0,0,0,0,"
    "ypc" => "1,0,0,0,0,0,0,0,"
    "yr" => "0,0,1,0,0,0,0,0,"
    "ys" => "0,0,1,0,0,0,0,0,"
    "yt" => "0,1,0,0,0,0,0,0,"
    "yvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "yΩ" => "2,1,-3,-2,0,0,0,0,"
    "zA" => "0,0,0,1,0,0,0,0,"
    "zB" => "0,0,0,0,0,0,0,1,"
    "zBps" => "0,0,-1,0,0,0,0,1,"
    "zBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "zC" => "0,0,1,1,0,0,0,0,"
    "zDa" => "0,1,0,0,0,0,0,0,"
    "zF" => "-2,-1,4,2,0,0,0,0,"
    "zGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "zH" => "2,1,-2,-2,0,0,0,0,"
    "zHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "zJ" => "2,1,-2,0,0,0,0,0,"
    "zJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "zK" => "0,0,0,0,1,0,0,0,"
    "zL" => "3,0,0,0,0,0,0,0,"
    "zN" => "1,1,-2,0,0,0,0,0,"
    "zPa" => "-1,1,-2,0,0,0,0,0,"
    "zS" => "-2,-1,3,2,0,0,0,0,"
    "zSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "zT" => "0,1,-2,-1,0,0,0,0,"
    "zV" => "2,1,-3,-1,0,0,0,0,"
    "zVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "zW" => "2,1,-3,0,0,0,0,0,"
    "zWb" => "2,1,-2,-1,0,0,0,0,"
    "zb" => "0,0,0,0,0,0,0,1,"
    "zbps" => "0,0,-1,0,0,0,0,1,"
    "zcd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "zcentury" => "0,0,1,0,0,0,0,0,"
    "zeV" => "2,1,-2,0,0,0,0,0,"
    "zeret" => "1,0,0,0,0,0,0,0,"
    "zfortnight" => "0,0,1,0,0,0,0,0,"
    "zg" => "0,1,0,0,0,0,0,0,"
    "zhang" => "1,0,0,0,0,0,0,0,"
    "zhangs" => "1,0,0,0,0,0,0,0,"
    "zkat" => "0,0,-1,0,0,1,0,0,"
    "zl" => "3,0,0,0,0,0,0,0,"
    "zlm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "zlx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "zm" => "1,0,0,0,0,0,0,0,"
    "zmol" => "0,0,0,0,0,1,0,0,"
    "zpc" => "1,0,0,0,0,0,0,0,"
    "zs" => "0,0,1,0,0,0,0,0,"
    "zt" => "0,1,0,0,0,0,0,0,"
    "zvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "zΩ" => "2,1,-3,-2,0,0,0,0,"
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
    "µB" => "0,0,0,0,0,0,0,1,"
    "µBps" => "0,0,-1,0,0,0,0,1,"
    "µBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "µC" => "0,0,1,1,0,0,0,0,"
    "µDa" => "0,1,0,0,0,0,0,0,"
    "µF" => "-2,-1,4,2,0,0,0,0,"
    "µGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "µH" => "2,1,-2,-2,0,0,0,0,"
    "µHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "µJ" => "2,1,-2,0,0,0,0,0,"
    "µJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "µK" => "0,0,0,0,1,0,0,0,"
    "µL" => "3,0,0,0,0,0,0,0,"
    "µM" => "-3,0,0,0,0,1,0,0,"
    "µN" => "1,1,-2,0,0,0,0,0,"
    "µPa" => "-1,1,-2,0,0,0,0,0,"
    "µS" => "-2,-1,3,2,0,0,0,0,"
    "µSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "µT" => "0,1,-2,-1,0,0,0,0,"
    "µV" => "2,1,-3,-1,0,0,0,0,"
    "µVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "µW" => "2,1,-3,0,0,0,0,0,"
    "µWb" => "2,1,-2,-1,0,0,0,0,"
    "µas" => "0,0,0,0,0,0,0,0,angle:1"
    "µb" => "0,0,0,0,0,0,0,1,"
    "µbps" => "0,0,-1,0,0,0,0,1,"
    "µcd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "µcentury" => "0,0,1,0,0,0,0,0,"
    "µeV" => "2,1,-2,0,0,0,0,0,"
    "µfortnight" => "0,0,1,0,0,0,0,0,"
    "µg" => "0,1,0,0,0,0,0,0,"
    "µg/mL" => "-3,1,0,0,0,0,0,0,"
    "µkat" => "0,0,-1,0,0,1,0,0,"
    "µl" => "3,0,0,0,0,0,0,0,"
    "µlm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "µlx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "µm" => "1,0,0,0,0,0,0,0,"
    "µmol" => "0,0,0,0,0,1,0,0,"
    "µmol/L" => "-3,0,0,0,0,1,0,0,"
    "µmol_photon/m²/s" => "-2,0,-1,0,0,1,0,0,photon:1"
    "µpc" => "1,0,0,0,0,0,0,0,"
    "µs" => "0,0,1,0,0,0,0,0,"
    "µt" => "0,1,0,0,0,0,0,0,"
    "µvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "µΩ" => "2,1,-3,-2,0,0,0,0,"
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
    "μA" => "0,0,0,1,0,0,0,0,"
    "μB" => "0,0,0,0,0,0,0,1,"
    "μBps" => "0,0,-1,0,0,0,0,1,"
    "μBq" => "0,0,-1,0,0,0,0,0,decay:1"
    "μC" => "0,0,1,1,0,0,0,0,"
    "μDa" => "0,1,0,0,0,0,0,0,"
    "μF" => "-2,-1,4,2,0,0,0,0,"
    "μGy" => "2,0,-2,0,0,0,0,0,absorbed_dose:1"
    "μH" => "2,1,-2,-2,0,0,0,0,"
    "μHz" => "0,0,-1,0,0,0,0,0,cycle:1"
    "μJ" => "2,1,-2,0,0,0,0,0,"
    "μJy" => "0,1,-2,0,0,0,0,0,cycle:-1"
    "μK" => "0,0,0,0,1,0,0,0,"
    "μL" => "3,0,0,0,0,0,0,0,"
    "μM" => "-3,0,0,0,0,1,0,0,"
    "μN" => "1,1,-2,0,0,0,0,0,"
    "μPa" => "-1,1,-2,0,0,0,0,0,"
    "μS" => "-2,-1,3,2,0,0,0,0,"
    "μSv" => "2,0,-2,0,0,0,0,0,equivalent_dose:1"
    "μT" => "0,1,-2,-1,0,0,0,0,"
    "μV" => "2,1,-3,-1,0,0,0,0,"
    "μVA" => "2,1,-3,0,0,0,0,0,apparent_power:1"
    "μW" => "2,1,-3,0,0,0,0,0,"
    "μWb" => "2,1,-2,-1,0,0,0,0,"
    "μ_B" => "2,0,0,1,0,0,0,0,"
    "μas" => "0,0,0,0,0,0,0,0,angle:1"
    "μb" => "0,0,0,0,0,0,0,1,"
    "μbps" => "0,0,-1,0,0,0,0,1,"
    "μcd" => "0,0,0,0,0,0,1,0,luminous_intensity:1"
    "μcentury" => "0,0,1,0,0,0,0,0,"
    "μeV" => "2,1,-2,0,0,0,0,0,"
    "μfortnight" => "0,0,1,0,0,0,0,0,"
    "μg" => "0,1,0,0,0,0,0,0,"
    "μkat" => "0,0,-1,0,0,1,0,0,"
    "μl" => "3,0,0,0,0,0,0,0,"
    "μlife" => "0,0,1,0,0,0,0,0,"
    "μlm" => "0,0,0,0,0,0,1,0,luminous_flux:1"
    "μlx" => "-2,0,0,0,0,0,1,0,illuminance:1"
    "μm" => "1,0,0,0,0,0,0,0,"
    "μmol" => "0,0,0,0,0,1,0,0,"
    "μmort" => "0,0,0,0,0,0,0,0,"
    "μpc" => "1,0,0,0,0,0,0,0,"
    "μs" => "0,0,1,0,0,0,0,0,"
    "μt" => "0,1,0,0,0,0,0,0,"
    "μvar" => "2,1,-3,0,0,0,0,0,reactive_power:1"
    "μΩ" => "2,1,-3,-2,0,0,0,0,"
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
  if id >= 8192
    raise compile_error_for_node(:E_LOWER_TOO_MANY_UNITS, "Too many custom units (max 4096)", ctx[:source_path], node)
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
