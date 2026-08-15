# Lowering / literals — value lowering for every literal node type
# (basic literals, arrays/hashes/symbols, ranges, regexes, and the deep
# domain types: floats, decimals, dates, times, durations, currencies,
# quantities, IPs, CIDRs, characters, codepoints, colors, and so on).
#
# Depends on pass_registry.w, types.w, analysis.w, monomorphize.w.
# Shared lowering dependencies come from pass_registry.w; only the generated
# unit lookup workers are imported here.


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
  # are handled by int_literal_exceeds_i64? above (their `val` wrapped), so
  # this arm must stay off them: `-9223372036854775808` reaches lower_int
  # through lower_unary_op's negate-the-literal fold, where `val` is the
  # PROMOTED magnitude 0 - (-2^63) = +2^63 (boxed :int arithmetic promotes)
  # while `raw` still spells the exact i64 minimum. Taking val's text there
  # printed the literal positive; the decimal raw-text path below is exact.
  if val > 9223372036854775807 && !decimal_int_literal?(node.raw)
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
    emit_wire_bigint_literal_i64(wfn, utf8_byte_length(text) + 1, slot_id, str_id, temp, temp_ptr)
    return typed_value(:i64, temp)

  str_tv = lower_string(ctx, Tungsten:AST:String.new(text))
  str_reg = ensure_i64_value(wfn, str_tv)
  temp = next_temp(wfn)
  emit_wire_call_direct_i64(wfn, nil, [str_reg], nil, nil, "w_bigint_from_dec_str", nil, nil, temp)
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
  emit_wire_string_i64(ctx[:func], byte_len + 1, str_id, temp, temp_ptr)
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
      # An integer part stringifies through w_int_to_s, which mints an
      # independent heap string per call (w_to_s may hand back its argument
      # or a rope's cached flat, so its result can never be owned). That
      # makes the part a fresh anonymous producer the concat below may
      # release — `"[i]"` in a loop leaked one heap string per 6+ digit
      # integer.
      part_fresh = false
      part_type = infer_type(part[1], ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
      if is_integer_like_type(part_type)
        emit_wire_call_direct_i64(wfn, nil, [expr_reg], nil, nil, "w_int_to_s", nil, nil, part_reg)
        part_fresh = true
      else
        emit_wire_call_direct_i64(wfn, nil, [expr_reg], nil, nil, "w_to_s", nil, nil, part_reg)
    if result == nil
      result = part_reg
    else
      concat = next_temp(wfn)
      # Owned operands: a chain link's `result` is the PREVIOUS concat's
      # temp — anonymous by construction (interpolation builds it; no user
      # name exists) and consumed only here — and a fresh integer part is
      # likewise consumed only here. w_str_concat_own releases each owned
      # heap operand after copying it out (flattening instead of building a
      # rope past 61 bytes), so an N-part interpolation leaks nothing.
      # env gate: TUNGSTEN_FREE=0 must silence every compiler-inserted free.
      own_mask = 0
      if env("TUNGSTEN_FREE") != "0"
        if i >= 2 && result_is_chain
          own_mask += 1
        if part_fresh
          own_mask += 2
      if own_mask != 0
        emit_wire_call_direct_i64(wfn, nil, [result, part_reg, own_mask.to_s()], nil, nil, "w_str_concat_own", nil, nil, concat)
      else
        emit_wire_call_direct_i64(wfn, nil, [result, part_reg], nil, nil, "w_str_concat", nil, nil, concat)
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
      emit_wire_small_array_const_load(wfn, name, arr)
      return typed_value(:i64, arr)
  # ## reuse — empty [] gets a per-site thread-local slot, reused across calls.
  if node.reuse_safe == true && (node.elements == nil || node.elements.size() == 0)
    site_id = ctx[:mod][:next_reuse_site]
    ctx[:mod][:next_reuse_site] = site_id + 1
    slot_name = "reuse.site." + site_id.to_s()
    ctx[:mod][:reuse_sites].push(slot_name)
    emit_wire_call_reuse_or_new_array(wfn, slot_name, arr)
    return typed_value(:i64, arr)
  # ## recycle — pop from thread-local pool or allocate. Recycled at scope exit.
  if node.recycle_safe == true && (node.elements == nil || node.elements.size() == 0)
    emit_wire_call_recycle_or_new_array(wfn, arr)
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
    emit_wire_call_direct_i64(wfn, nil, ["65", n_elems.to_s()], nil, nil, "w_array_new_uninit_sized", nil, nil, arr)
  else
    emit_wire_call_direct_i64(wfn, nil, [], nil, nil, "w_array_new_empty", nil, nil, arr)
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
    emit_wire_call_direct_i64(wfn, nil, [arr, i.to_s(), val_reg], nil, nil, "__w_array_lit_store", nil, nil, push_temp)
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
  emit_wire_call_direct_i64(wfn, nil, [element_bits, node.elements.size().to_s()], nil, nil, "w_array_new_inline", nil, nil, arr)
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
    emit_wire_typed_array_set_inline(wfn, arr, store_bits, i.to_s(), true, scratch, true, stored, val_bits)
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
    emit_wire_call_reuse_and_drain_or_new_hash(wfn, slot_name, hash_reg)
    return typed_value(:i64, hash_reg)
  # ## reuse — empty {} gets a per-site thread-local slot, reused across calls.
  if node.reuse_safe == true && (node.entries == nil || node.entries.size() == 0)
    site_id = ctx[:mod][:next_reuse_site]
    ctx[:mod][:next_reuse_site] = site_id + 1
    slot_name = "reuse.site." + site_id.to_s()
    ctx[:mod][:reuse_sites].push(slot_name)
    emit_wire_call_reuse_or_new_hash(wfn, slot_name, hash_reg)
    return typed_value(:i64, hash_reg)
  # ## recycle — pop from thread-local pool or allocate. Recycled at scope exit.
  if node.recycle_safe == true && (node.entries == nil || node.entries.size() == 0)
    emit_wire_call_recycle_or_new_hash(wfn, hash_reg)
    track_recycle_temp(wfn, hash_reg, :hash)
    return typed_value(:i64, hash_reg)
  emit_wire_call_direct_i64(wfn, nil, [], nil, nil, "w_hash_new", nil, nil, hash_reg)
  entries = node.entries
  i = 0
  while i < entries.size()
    entry = entries[i]
    key_val = lower_expression(ctx, entry[0])
    key_reg = ensure_i64_value(wfn, key_val)
    val_val = lower_expression(ctx, entry[1])
    val_reg = ensure_i64_value(wfn, val_val)
    set_temp = next_temp(wfn)
    emit_wire_call_direct_i64(wfn, nil, [hash_reg, key_reg, val_reg], nil, nil, "w_hash_set", nil, nil, set_temp)
    i += 1
  # A call-site kwargs group (`f(a: 1)`) passes as ONE hash argument marked
  # W_HASH_FLAG_KWARGS; keyword-param callees rebind it by name at entry
  # (w_kwargs_remap12 prologue), everyone else receives a plain hash.
  if node.from_kwargs == true
    mark_temp = next_temp(wfn)
    emit_wire_call_direct_i64(wfn, nil, [hash_reg], nil, nil, "w_hash_mark_kwargs", nil, nil, mark_temp)
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
  emit_wire_symbol_i64(wfn, byte_len + 1, str_id, temp, temp_ptr)
  typed_value(:i64, temp)

-> lower_regex(ctx, node)
  wfn = ctx[:func]
  pattern_tv = lower_string(ctx, Tungsten:AST:String.new(node.pattern))
  options_tv = lower_string(ctx, Tungsten:AST:String.new(node.options))
  pattern_reg = ensure_i64_value(wfn, pattern_tv)
  options_reg = ensure_i64_value(wfn, options_tv)
  temp = next_temp(wfn)
  emit_wire_call_direct_i64(wfn, nil, [pattern_reg, options_reg], nil, nil, "w_regex_new", nil, nil, temp)
  typed_value(:i64, temp)

-> lower_regex_capture(ctx, node)
  wfn = ctx[:func]
  index_tv = lower_int(ctx, Tungsten:AST:Int.new(ast_get(node, :index)))
  index_reg = ensure_i64_value(wfn, index_tv)
  temp = next_temp(wfn)
  emit_wire_call_direct_i64(wfn, nil, [index_reg], nil, nil, "w_regex_capture", nil, nil, temp)
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
    emit_wire_call_direct_i64(wfn, nil, [from_reg], nil, nil, "w_range_bound_i64", nil, nil, from_raw)
  else
    from_raw = next_temp(wfn)
    emit_wire_nanunbox_int(wfn, from_reg, from_raw, from_raw + ".shl")
  if to_static_type != nil && !is_integer_like_type(to_static_type)
    to_raw = next_temp(wfn)
    emit_wire_call_direct_i64(wfn, nil, [to_reg], nil, nil, "w_range_bound_i64", nil, nil, to_raw)
  else
    to_raw = next_temp(wfn)
    emit_wire_nanunbox_int(wfn, to_reg, to_raw, to_raw + ".shl")

  excl = "0"
  if node.exclusive == true
    excl = "1"
  temp = next_temp(wfn)
  emit_wire_call_direct_i64(wfn, nil, [from_raw, to_raw, excl], nil, nil, "w_range_make", nil, nil, temp)
  typed_value(:i64, temp)



# -- Deep literal lowerings (domain types) --

# A `~` literal keeps its SOURCE TEXT in the AST, and that text becomes the
# LLVM operand of every `double` instruction it feeds. LLVM's assembler only
# reads a token as floating point when the mantissa carries a decimal point:
# `~5`, `~1e10` and `~1_000.5` would emit `bitcast double 5 to i64` (and
# `1e10` / `1_000.5`), which clang rejects with "integer/byte constant must
# have integer/byte type". Normalize the text here — the single place a float
# literal enters WIRE — by dropping digit separators and giving the mantissa
# an explicit fractional part, keeping any exponent. Texts that already have
# one (`2.5`, `9.9999999999999995e-08`) pass through byte-for-byte.
-> llvm_double_literal_text(src)
  s = ""
  i = 0
  while i < src.size()
    c = src[i]
    if c != "_"
      s = s + c
    i += 1
  mant = s
  expo = ""
  e_idx = s.index("e")
  if e_idx == nil
    e_idx = s.index("E")
  if e_idx != nil
    mant = s.slice(0, e_idx)
    expo = s.slice(e_idx, s.size() - e_idx)
  if mant.index(".") == nil
    mant = mant + ".0"
  elsif mant.slice(mant.size() - 1, 1) == "."
    mant = mant + "0"
  if mant.slice(0, 1) == "."
    mant = "0" + mant
  elsif mant.slice(0, 2) == "-."
    mant = "-0" + mant.slice(1, mant.size() - 1)
  mant + expo

-> lower_float(ctx, node)
  typed_value(:raw_f64, llvm_double_literal_text(node.value.to_s()))

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
    emit_wire_call_direct_i64(wfn, nil, [str_reg, sc_bits, neg_arg], nil, nil, "w_decimal_from_digits", nil, nil, btemp)
    return typed_value(:i64, btemp)
  sig = digits_txt.to_i()
  if neg
    sig = 0 - sig
  temp = next_temp(wfn)
  emit_wire_const_decimal(wfn, scale, sig, temp)
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
      emit_wire_small_array_alloca(wfn, temp_ptr, total_bytes)
      emit_wire_ptr_to_i64(wfn, temp_int, temp_ptr)
      emit_wire_call_direct_i64(wfn, nil, [temp_int, bits.to_s(), size_const.to_s()], nil, nil, "w_small_array_init", nil, nil, temp_box)
      return typed_value(:i64, temp_box)
    # ## reuse — per-site thread-local slot reused across calls. Shape is
    # stable (same element_bits) at a given site; capacity grows as needed.
    if node.reuse_safe == true
      site_id = ctx[:mod][:next_reuse_site]
      ctx[:mod][:next_reuse_site] = site_id + 1
      slot_name = "reuse.site." + site_id.to_s()
      ctx[:mod][:reuse_sites].push(slot_name)
      temp = next_temp(wfn)
      emit_wire_call_reuse_or_new_typed(wfn, bits, size_raw, slot_name, temp)
      return typed_value(:i64, temp)
    # ## recycle — pop from shape-keyed pool. Recycled at scope exit.
    if node.recycle_safe == true
      temp = next_temp(wfn)
      emit_wire_call_recycle_or_new_typed(wfn, bits, size_raw, temp)
      track_recycle_temp(wfn, temp, :typed)
      return typed_value(:i64, temp)
    # T[N] semantics: zero-filled buffer with size = cap = N, ready to
    # read or index-write without bounds-growth checks. Push-to-fill
    # (`t = i32[N]; t.push(…)`) is no longer the canonical idiom; the
    # inline `[]=` path assumes size == cap and skips the size update.
    temp = next_temp(wfn)
    emit_wire_call_direct_i64(wfn, nil, [bits.to_s(), size_raw], nil, nil, "w_array_zeros", nil, nil, temp)
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
  emit_wire_const_currency(wfn, scale, sig, symbol_id, temp)
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
  emit_wire_const_quantity(wfn, scale, sig, temp, unit_id)
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
    emit_wire_const_duration_ns(wfn, parsed[:ns], temp)
  else
    emit_wire_const_duration_months_ms(wfn, parsed[:months], parsed[:ms], temp)
  typed_value(:i64, temp)

-> lower_uuid(ctx, node)
  wfn = ctx[:func]
  str_id = module_string_constant(ctx[:mod], node.value)
  byte_len = utf8_byte_length(node.value) + 1
  temp_ptr = next_temp(wfn)
  temp = next_temp(wfn)
  emit_wire_const_uuid(wfn, byte_len, str_id, temp, temp_ptr)
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
  emit_wire_const_date(wfn, day, 0, 0, month, 0, temp, 0, year)
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
  emit_wire_const_date(wfn, day, parsed[:hour], parsed[:min], month, parsed[:sec], temp, parsed[:tz], year)
  typed_value(:i64, temp)

-> lower_time(ctx, node)
  wfn = ctx[:func]
  # Parse "hh:mm:ss[.frac][±hh:mm|Z]"
  parsed = parse_time_string(node.value)
  validate_time(parsed[:hour], parsed[:min], parsed[:sec], node.value, ctx, node)
  temp = next_temp(wfn)
  emit_wire_const_date(wfn, 0, parsed[:hour], parsed[:min], 0, parsed[:sec], temp, parsed[:tz], 0)
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
  emit_wire_const_ipv4(wfn, a, b, c, -1, d, temp)
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
  emit_wire_const_ipv4(wfn, a, b, c, prefix, d, temp)
  typed_value(:i64, temp)

-> lower_ipv6(ctx, node)
  wfn = ctx[:func]
  # String-based (like lower_uuid): intern the canonical address text and let
  # the runtime parse it into 16 bytes. cidr -1 = plain address.
  str_id = module_string_constant(ctx[:mod], node.value)
  byte_len = utf8_byte_length(node.value) + 1
  temp_ptr = next_temp(wfn)
  temp = next_temp(wfn)
  emit_wire_const_ipv6(wfn, byte_len, -1, str_id, temp, temp_ptr)
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
  emit_wire_const_ipv6(wfn, byte_len, prefix, str_id, temp, temp_ptr)
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
  emit_wire_const_rational(wfn, den, num, temp)
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
  emit_wire_const_char(wfn, node.value, temp)
  typed_value(:i64, temp)

-> lower_color(ctx, node)
  wfn = ctx[:func]
  temp = next_temp(wfn)
  packed = node.rgba
  emit_wire_const_color(wfn, packed & 0xff, (packed >> 8) & 0xff, (packed >> 16) & 0xff, (packed >> 24) & 0xff, temp)
  typed_value(:i64, temp)

-> lower_cidr_match(ctx, node)
  wfn = ctx[:func]
  # Lower both the subject (IP) and the CIDR pattern
  subj_tv = lower_expression(ctx, node.subject)
  cidr_tv = lower_expression(ctx, node.cidr)
  subj_reg = ensure_i64_value(wfn, subj_tv)
  cidr_reg = ensure_i64_value(wfn, cidr_tv)
  temp = next_temp(wfn)
  emit_wire_call_direct_i64(wfn, nil, [subj_reg, cidr_reg], nil, nil, "w_ipv4_in_cidr", nil, nil, temp)
  typed_value(:i64, temp)

-> lower_regex_match(ctx, node)
  wfn = ctx[:func]
  regex_tv = lower_expression(ctx, node.regex)
  subject_tv = lower_expression(ctx, node.subject)
  regex_reg = ensure_i64_value(wfn, regex_tv)
  subject_reg = ensure_i64_value(wfn, subject_tv)
  temp = next_temp(wfn)
  emit_wire_call_direct_i64(wfn, nil, [regex_reg, subject_reg], nil, nil, "w_regex_match", nil, nil, temp)
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

use literal_units

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
