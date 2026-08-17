# Emitter runtime instructions — constants, calls, control flow, and objects.

-> render_runtime_instruction(inst, string_wvs, used_ptr_ids, phi_label_redirects = nil, fp_flags = "", arm64_target = true, windows_target = false)
  op = wire_kind(inst)

  case op
  # Float
  when :const_float
    bits_temp = wire_get(inst, :temp) + ".bits"
    bits_temp + " = bitcast double " + wire_get(inst, :value) + " to i64\n  " + wire_get(inst, :temp) + " = add i64 " + bits_temp + ", " + machine_i64_text(w_double_bias)
  when :const_decimal
    wire_get(inst, :temp) + " = call i64 @w_decimal(i64 " + wire_get(inst, :sig).to_s() + ", i32 " + wire_get(inst, :scale).to_s() + ")"
  when :const_currency
    wire_get(inst, :temp) + " = call i64 @w_currency(i32 " + wire_get(inst, :symbol_id).to_s() + ", i64 " + wire_get(inst, :sig).to_s() + ", i32 " + wire_get(inst, :scale).to_s() + ")"
  when :const_quantity
    wire_get(inst, :temp) + " = call i64 @w_quantity(i32 " + wire_get(inst, :unit_id).to_s() + ", i64 " + wire_get(inst, :sig).to_s() + ", i32 " + wire_get(inst, :scale).to_s() + ")"
  when :const_duration_ns
    wire_get(inst, :temp) + " = call i64 @w_duration_ns(i64 " + wire_get(inst, :ns).to_s() + ")"
  when :const_duration_months_ms
    wire_get(inst, :temp) + " = call i64 @w_duration_months_ms(i32 " + wire_get(inst, :months).to_s() + ", i32 " + wire_get(inst, :ms).to_s() + ")"

  when :const_uuid
    used_ptr_ids[wire_get(inst, :string_id)] = true
    lbr = "\["
    rbr = "]"
    bl = wire_get(inst, :byte_len).to_s()
    wire_get(inst, :temp_ptr) + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :string_id).to_s() + ", i32 0, i32 0\n  " + wire_get(inst, :temp) + " = call i64 @w_uuid_from_hex(ptr " + wire_get(inst, :temp_ptr) + ")"

  when :const_date
    wire_get(inst, :temp) + " = call i64 @w_date(i32 " + wire_get(inst, :year).to_s() + ", i32 " + wire_get(inst, :month).to_s() + ", i32 " + wire_get(inst, :day).to_s() + ", i32 " + wire_get(inst, :hour).to_s() + ", i32 " + wire_get(inst, :min).to_s() + ", i32 " + wire_get(inst, :sec).to_s() + ", i32 " + wire_get(inst, :tz).to_s() + ")"

  when :const_ipv4
    wire_get(inst, :temp) + " = call i64 @w_ipv4(i32 " + wire_get(inst, :a).to_s() + ", i32 " + wire_get(inst, :b).to_s() + ", i32 " + wire_get(inst, :c).to_s() + ", i32 " + wire_get(inst, :d).to_s() + ", i32 " + wire_get(inst, :cidr).to_s() + ")"

  when :const_ipv6
    used_ptr_ids[wire_get(inst, :string_id)] = true
    lbr = "\["
    rbr = "]"
    bl = wire_get(inst, :byte_len).to_s()
    wire_get(inst, :temp_ptr) + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :string_id).to_s() + ", i32 0, i32 0\n  " + wire_get(inst, :temp) + " = call i64 @w_ipv6_from_string(ptr " + wire_get(inst, :temp_ptr) + ", i32 " + wire_get(inst, :cidr).to_s() + ")"

  when :const_rational
    wire_get(inst, :temp) + " = call i64 @w_rational(i32 " + wire_get(inst, :num).to_s() + ", i32 " + wire_get(inst, :den).to_s() + ")"

  when :const_char
    wire_get(inst, :temp) + " = call i64 @w_box_char(i32 " + wire_get(inst, :codepoint).to_s() + ")" + wvalue_char_range_metadata_suffix()

  when :const_color
    wire_get(inst, :temp) + " = call i64 @w_color(i32 " + wire_get(inst, :r).to_s() + ", i32 " + wire_get(inst, :g).to_s() + ", i32 " + wire_get(inst, :b).to_s() + ", i32 " + wire_get(inst, :a).to_s() + ")"

  # View access: load byte from raw object pointer.
  # The receiver mask for EVERY view op is 140737488355312
  # (0x00007FFF_FFFF_FFF0): it strips the low subtag nibble like the old
  # -16 AND the top-17 tag/sign bits, because BigInt receivers now ride a
  # top-level tag (0xFFFB, bit 47 reserved for tag-sign) rather than the
  # object space. Object-space receivers have zero top bits, so the wider
  # mask is a no-op for them. The array/hash/strbuf header derefs elsewhere
  # in this file keep -16: they sit behind subtag guards a bigint cannot
  # pass.
  when :view_load_byte
    ptr_raw = wire_get(inst, :temp) + ".ptr"
    byte_ptr = wire_get(inst, :temp) + ".bp"
    byte_val = wire_get(inst, :temp) + ".b"
    ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + wire_get(inst, :index) + "\n  " + byte_val + " = load i8, ptr " + wire_get(inst, :temp) + ".gep\n  " + wire_get(inst, :temp) + ".zext = zext i8 " + byte_val + " to i64\n  " + w_int_call_with_range(wire_get(inst, :temp), wire_get(inst, :temp) + ".zext", 0, 256)

  # Fixed inline u8[N] field: load at the statically known field offset plus
  # the caller-checked dynamic index. No hidden bounds branch is emitted.
  when :view_load_inline_byte
    ptr_raw = wire_get(inst, :temp) + ".ptr"
    byte_ptr = wire_get(inst, :temp) + ".bp"
    byte_val = wire_get(inst, :temp) + ".b"
    ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".base = getelementptr i8, ptr " + byte_ptr + ", i64 " + wire_get(inst, :offset).to_s() + "\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + wire_get(inst, :temp) + ".base, i64 " + wire_get(inst, :index) + "\n  " + byte_val + " = load i8, ptr " + wire_get(inst, :temp) + ".gep\n  " + wire_get(inst, :temp) + " = zext i8 " + byte_val + " to i64"

  # Widened inline array element (`u64[] limbs` and friends): strided load at
  # field offset + index * element size. i-prefixed elements sign-extend,
  # u-prefixed zero-extend; 64-bit elements load raw. Alignment is the static
  # residue of the field offset, which every element shares. Like the byte
  # form, no hidden bounds branch is emitted — the method owns the check.
  when :view_load_inline_elem
    ptr_raw = wire_get(inst, :temp) + ".ptr"
    byte_ptr = wire_get(inst, :temp) + ".bp"
    bits = (wire_get(inst, :size) * 8).to_s()
    elem_align = (wire_get(inst, :offset) % wire_get(inst, :size)) == 0 ? wire_get(inst, :size).to_s() : "1"
    head = ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".base = getelementptr i8, ptr " + byte_ptr + ", i64 " + wire_get(inst, :offset).to_s() + "\n  " + wire_get(inst, :temp) + ".gep = getelementptr i" + bits + ", ptr " + wire_get(inst, :temp) + ".base, i64 " + wire_get(inst, :index) + "\n  "
    if wire_get(inst, :size) == 8
      head + wire_get(inst, :temp) + " = load i64, ptr " + wire_get(inst, :temp) + ".gep, align " + elem_align
    else
      extension = wire_get(inst, :elem).starts_with?("i") ? "sext" : "zext"
      head + wire_get(inst, :temp) + ".w = load i" + bits + ", ptr " + wire_get(inst, :temp) + ".gep, align " + elem_align + "\n  " + wire_get(inst, :temp) + " = " + extension + " i" + bits + " " + wire_get(inst, :temp) + ".w to i64"

  # Store twin: truncate the raw value to the element width and store at the
  # same strided address; the instruction's temp carries the raw value
  # through so `$f[i] = v` keeps ordinary assignment-expression semantics.
  when :view_store_inline_elem
    ptr_raw = wire_get(inst, :temp) + ".ptr"
    byte_ptr = wire_get(inst, :temp) + ".bp"
    bits = (wire_get(inst, :size) * 8).to_s()
    elem_align = (wire_get(inst, :offset) % wire_get(inst, :size)) == 0 ? wire_get(inst, :size).to_s() : "1"
    head = ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".base = getelementptr i8, ptr " + byte_ptr + ", i64 " + wire_get(inst, :offset).to_s() + "\n  " + wire_get(inst, :temp) + ".gep = getelementptr i" + bits + ", ptr " + wire_get(inst, :temp) + ".base, i64 " + wire_get(inst, :index) + "\n  "
    if wire_get(inst, :size) == 8
      head + "store i64 " + wire_get(inst, :value) + ", ptr " + wire_get(inst, :temp) + ".gep, align " + elem_align + "\n  " + wire_get(inst, :temp) + " = add i64 " + wire_get(inst, :value) + ", 0"
    else
      head + wire_get(inst, :temp) + ".t = trunc i64 " + wire_get(inst, :value) + " to i" + bits + "\n  store i" + bits + " " + wire_get(inst, :temp) + ".t, ptr " + wire_get(inst, :temp) + ".gep, align " + elem_align + "\n  " + wire_get(inst, :temp) + " = add i64 " + wire_get(inst, :value) + ", 0"

  # View access: load bit from raw object pointer
  when :view_load_bit
    ptr_raw = wire_get(inst, :temp) + ".ptr"
    byte_ptr = wire_get(inst, :temp) + ".bp"
    byte_idx = wire_get(inst, :temp) + ".bidx"
    bit_idx = wire_get(inst, :temp) + ".bitidx"
    byte_val = wire_get(inst, :temp) + ".b"
    shifted = wire_get(inst, :temp) + ".sh"
    masked = wire_get(inst, :temp) + ".m"
    ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + byte_idx + " = lshr i64 " + wire_get(inst, :index) + ", 3\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + byte_idx + "\n  " + byte_val + " = load i8, ptr " + wire_get(inst, :temp) + ".gep\n  " + bit_idx + " = and i64 " + wire_get(inst, :index) + ", 7\n  " + bit_idx + ".trunc = trunc i64 " + bit_idx + " to i8\n  " + shifted + " = lshr i8 " + byte_val + ", " + bit_idx + ".trunc\n  " + masked + " = and i8 " + shifted + ", 1\n  " + wire_get(inst, :temp) + ".zext = zext i8 " + masked + " to i64\n  " + w_int_call_with_range(wire_get(inst, :temp), wire_get(inst, :temp) + ".zext", 0, 2)

  # View field: load a named field at known offset/size from raw object pointer
  when :view_load_field
    ptr_raw = wire_get(inst, :temp) + ".ptr"
    byte_ptr = wire_get(inst, :temp) + ".bp"
    ftype = wire_get(inst, :field_type)
    offset = wire_get(inst, :offset).to_s()
    size = wire_get(inst, :size)
    extension = ftype.starts_with?("i") ? "sext" : "zext"
    if ftype.starts_with?("*")
      # Pointer field: load ptr, then ptrtoint
      ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + wire_get(inst, :temp) + ".p = load ptr, ptr " + wire_get(inst, :temp) + ".gep\n  " + wire_get(inst, :temp) + " = ptrtoint ptr " + wire_get(inst, :temp) + ".p to i64"
    elsif ftype == "f32"
      ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + wire_get(inst, :temp) + " = load float, ptr " + wire_get(inst, :temp) + ".gep, align 1"
    elsif ftype == "f64"
      ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + wire_get(inst, :temp) + " = load double, ptr " + wire_get(inst, :temp) + ".gep, align 1"
    elsif size == 1
      ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + wire_get(inst, :temp) + ".b = load i8, ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = " + extension + " i8 " + wire_get(inst, :temp) + ".b to i64"
    elsif size == 2
      ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + wire_get(inst, :temp) + ".h = load i16, ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = " + extension + " i16 " + wire_get(inst, :temp) + ".h to i64"
    elsif size == 4
      ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + wire_get(inst, :temp) + ".w = load i32, ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = " + extension + " i32 " + wire_get(inst, :temp) + ".w to i64"
    else
      # 8 bytes (i64)
      ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  " + wire_get(inst, :temp) + " = load i64, ptr " + wire_get(inst, :temp) + ".gep"

  # View field: store a scalar at a known native-data offset and return the
  # value converted to the field's declared width. Native layouts can be
  # packed, so every field store deliberately uses align 1 like field loads.
  when :view_store_field
    ptr_raw = wire_get(inst, :temp) + ".ptr"
    byte_ptr = wire_get(inst, :temp) + ".bp"
    ftype = wire_get(inst, :field_type)
    offset = wire_get(inst, :offset).to_s()
    size = wire_get(inst, :size)
    if size > 8
      raise "view_store_field cannot store fields wider than 64 bits"
    extension = ftype.starts_with?("i") ? "sext" : "zext"
    prefix = ptr_raw + " = and i64 " + wire_get(inst, :ptr) + ", 140737488355312\n  " + byte_ptr + " = inttoptr i64 " + ptr_raw + " to ptr\n  " + wire_get(inst, :temp) + ".gep = getelementptr i8, ptr " + byte_ptr + ", i64 " + offset + "\n  "
    if ftype.starts_with?("*")
      prefix + wire_get(inst, :temp) + ".p = inttoptr i64 " + wire_get(inst, :value) + " to ptr\n  store ptr " + wire_get(inst, :temp) + ".p, ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = or i64 " + wire_get(inst, :value) + ", 0"
    elsif ftype == "f32"
      prefix + "store float " + wire_get(inst, :value) + ", ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = select i1 true, float " + wire_get(inst, :value) + ", float " + wire_get(inst, :value)
    elsif ftype == "f64"
      prefix + "store double " + wire_get(inst, :value) + ", ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = select i1 true, double " + wire_get(inst, :value) + ", double " + wire_get(inst, :value)
    elsif size == 1
      prefix + wire_get(inst, :temp) + ".b = trunc i64 " + wire_get(inst, :value) + " to i8\n  store i8 " + wire_get(inst, :temp) + ".b, ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = " + extension + " i8 " + wire_get(inst, :temp) + ".b to i64"
    elsif size == 2
      prefix + wire_get(inst, :temp) + ".h = trunc i64 " + wire_get(inst, :value) + " to i16\n  store i16 " + wire_get(inst, :temp) + ".h, ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = " + extension + " i16 " + wire_get(inst, :temp) + ".h to i64"
    elsif size == 4
      prefix + wire_get(inst, :temp) + ".w = trunc i64 " + wire_get(inst, :value) + " to i32\n  store i32 " + wire_get(inst, :temp) + ".w, ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = " + extension + " i32 " + wire_get(inst, :temp) + ".w to i64"
    else
      prefix + "store i64 " + wire_get(inst, :value) + ", ptr " + wire_get(inst, :temp) + ".gep, align 1\n  " + wire_get(inst, :temp) + " = or i64 " + wire_get(inst, :value) + ", 0"

  # View base: extract raw pointer from object
  when :view_base_ptr
    wire_get(inst, :temp) + " = and i64 " + wire_get(inst, :value) + ", -16"

  # Register custom unit: call w_register_unit(i32 id, ptr name)
  when :register_unit
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :str_id)]
    if swv != nil
      "call void @w_register_unit_wv(i32 " + wire_get(inst, :unit_id).to_s() + ", i64 " + llvm_wvalue_literal(swv) + ")"
    else
      used_ptr_ids[wire_get(inst, :str_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :byte_len).to_s()
      tmp = "%reg.unit." + wire_get(inst, :unit_id).to_s()
      tmp + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :str_id).to_s() + ", i32 0, i32 0\n  " + tmp + ".wv = call i64 @w_string(ptr " + tmp + ")\n  call void @w_register_unit_wv(i32 " + wire_get(inst, :unit_id).to_s() + ", i64 " + tmp + ".wv)"

  # String
  when :string_i64
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :string_id)]
    if swv != nil
      wire_get(inst, :temp) + " = or i64 0, " + llvm_wvalue_literal(swv)
    else
      used_ptr_ids[wire_get(inst, :string_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :byte_len).to_s()
      wire_get(inst, :temp_ptr) + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :string_id).to_s() + ", i32 0, i32 0\n  " + wire_get(inst, :temp) + " = call i64 @w_string(ptr " + wire_get(inst, :temp_ptr) + ")"

  # BigInt source literal: pass the executable's constant decimal bytes and
  # its module-local publication slot directly to the runtime.  The steady
  # state is one atomic load plus a recycler-backed copy of the pinned
  # template, preserving explicit alias-visible BigInt bang semantics.
  when :bigint_literal_i64
    used_ptr_ids[wire_get(inst, :string_id)] = true
    lbr = "\["
    rbr = "]"
    bl = wire_get(inst, :byte_len).to_s()
    wire_get(inst, :temp_ptr) + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :string_id).to_s() + ", i32 0, i32 0\n  " + wire_get(inst, :temp) + " = call i64 @w_bigint_literal_cached(ptr " + wire_get(inst, :temp_ptr) + ", ptr @.bigint.literal." + wire_get(inst, :slot_id).to_s() + ")"

  # Symbol: string WValue with bit 0 set
  when :symbol_i64
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :string_id)]
    if swv != nil
      wire_get(inst, :temp) + " = or i64 " + llvm_wvalue_literal(swv) + ", 1"
    else
      used_ptr_ids[wire_get(inst, :string_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :byte_len).to_s()
      wire_get(inst, :temp_ptr) + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :string_id).to_s() + ", i32 0, i32 0\n  " + wire_get(inst, :temp) + ".s = call i64 @w_string(ptr " + wire_get(inst, :temp_ptr) + ")\n  " + wire_get(inst, :temp) + " = call i64 @w_str_to_sym(i64 " + wire_get(inst, :temp) + ".s)"

  # Slab-AST constructor fusion (fix #3). Inline bump + N field stores
  # against the same slot address — no per-field re-derivation of the
  # slot pointer from the W_PACKED_NODE encoding.
  when :slab_alloc_init
    t = wire_get(inst, :temp)
    kind = wire_get(inst, :kind)
    sc = wire_get(inst, :sc)
    fields = wire_get(inst, :fields)
    nf = wire_sequence_size(fields)
    lbr = "\["
    label_fast = "sai_" + t.slice(1, t.size() - 1) + "_fast"
    label_slow = "sai_" + t.slice(1, t.size() - 1) + "_slow"
    label_merge = "sai_" + t.slice(1, t.size() - 1) + "_merge"
    parts = StringBuffer(1200 + nf * 200)
    # Freeze array-valued fields into the AST extra arena before the
    # store — child lists live arena-side (w_ast_freeze_if_array is a
    # tag-check passthrough for everything else). Emitted in the entry
    # block so the frozen temps dominate both the fast and slow stores.
    fi = 0
    while fi < nf
      parts << t + ".fz" + fi.to_s() + " = call i64 @w_ast_freeze_if_array(i64 " + wire_sequence_get(fields, fi) + ")\n  "
      fi += 1
    parts << t + ".cursor_p = getelementptr inbounds { ptr, i32, i32 }, ptr @g_ast_store, i32 0, i32 1\n  "
    parts << t + ".cursor = load i32, ptr " + t + ".cursor_p, align 4\n  "
    parts << t + ".cap_p = getelementptr inbounds { ptr, i32, i32 }, ptr @g_ast_store, i32 0, i32 2\n  "
    parts << t + ".cap = load i32, ptr " + t + ".cap_p, align 4\n  "
    parts << t + ".new_cursor = add i32 " + t + ".cursor, " + nf.to_s() + "\n  "
    parts << t + ".has_room = icmp ule i32 " + t + ".new_cursor, " + t + ".cap\n  "
    parts << "br i1 " + t + ".has_room, label %" + label_fast + ", label %" + label_slow + ", !prof !31411\n"
    parts << label_fast + ":\n  "
    parts << "store i32 " + t + ".new_cursor, ptr " + t + ".cursor_p, align 4\n  "
    parts << t + ".base_p = getelementptr inbounds { ptr, i32, i32 }, ptr @g_ast_store, i32 0, i32 0\n  "
    parts << t + ".base = load ptr, ptr " + t + ".base_p, align 8\n  "
    parts << t + ".cursor64 = zext i32 " + t + ".cursor to i64\n  "
    parts << t + ".slot_addr = getelementptr i64, ptr " + t + ".base, i64 " + t + ".cursor64\n  "
    fi = 0
    while fi < nf
      parts << t + ".fp" + fi.to_s() + " = getelementptr i64, ptr " + t + ".slot_addr, i64 " + fi.to_s() + "\n  "
      parts << "store i64 " + t + ".fz" + fi.to_s() + ", ptr " + t + ".fp" + fi.to_s() + ", align 8\n  "
      fi += 1
    parts << t + ".sc_shifted = shl i64 " + sc + ", 34\n  "
    parts << t + ".kind_shifted = shl i64 " + kind + ", 36\n  "
    parts << t + ".p1 = or i64 " + t + ".sc_shifted, " + t + ".cursor64\n  "
    parts << t + ".p2 = or i64 " + t + ".kind_shifted, " + t + ".p1\n  "
    parts << t + ".fast_result = or i64 u0xFFFE600000000000, " + t + ".p2\n  "
    parts << "br label %" + label_merge + "\n"
    parts << label_slow + ":\n  "
    parts << t + ".slow_node = call i64 @w_node_alloc(i64 " + kind + ", i64 " + sc + ")\n  "
    parts << t + ".s.off = and i64 " + t + ".slow_node, 4294967295\n  "
    parts << t + ".s.base_p = getelementptr inbounds { ptr, i32, i32 }, ptr @g_ast_store, i32 0, i32 0\n  "
    parts << t + ".s.base = load ptr, ptr " + t + ".s.base_p, align 8\n  "
    parts << t + ".s.slot_addr = getelementptr i64, ptr " + t + ".s.base, i64 " + t + ".s.off\n  "
    fi = 0
    while fi < nf
      parts << t + ".s.fp" + fi.to_s() + " = getelementptr i64, ptr " + t + ".s.slot_addr, i64 " + fi.to_s() + "\n  "
      parts << "store i64 " + t + ".fz" + fi.to_s() + ", ptr " + t + ".s.fp" + fi.to_s() + ", align 8\n  "
      fi += 1
    parts << "br label %" + label_merge + "\n"
    parts << label_merge + ":\n  "
    parts << t + " = phi i64 " + lbr + " " + t + ".fast_result, %" + label_fast + " ], " + lbr + " " + t + ".slow_node, %" + label_slow + " ]"
    return parts.to_s()

  # Direct function calls. When carrying src_line, the call is rendered
  # `notail` and followed by a BB split (csd.N.ret) so the return address
  # is addressable for the __w_call_site lookup.
  when :call_direct_i64
    # Slab-AST intrinsic: w_node_alloc(kind, sc) — emit an inline bump
    # against @g_ast_store with a cmp/branch fallback to the runtime
    # @w_node_alloc on cap exhaustion (which grows + bumps). With fix #1's
    # constant-folded KIND_*/SC_* globals, LLVM collapses the kind/sc
    # shifts and OR into a single constant + bump in the fast path.
    #
    # Layout: the exact-width word arena is {ptr base, i32 cursor, i32 cap}.
    # Indices 1 and 2 reach cursor/cap respectively.
    #
    # Slab-AST intrinsic: w_node_field_load(node, offset) / w_node_field_store(
    # node, offset, value) — when the offset arg is a literal (which it always
    # is in ast.w call sites), emit inline LLVM IR that walks the
    # @g_ast_store slab directly instead of calling out to the runtime
    # helper. LLVM can then CSE the @g_ast_store base load across multiple
    # field accesses of the same node and fold the offset arithmetic into a
    # GEP. The args list is already lowered by the generic ccall_nobox path
    # in lowering/calls.w; the int-literal offset reaches here as a raw
    # decimal string because lower_int returns typed_value(:raw_int,
    # val.to_s()) without emitting an instruction.
    # Slab-AST intrinsic: decode the full-tier 8-bit kind or compact-tier
    # 5-bit kind according to prefix bit 44.
    args = wire_get(inst, :args)
    if wire_get(inst, :name) == "w_node_kind_extern" && wire_sequence_size(args) == 1
      t = wire_get(inst, :temp)
      v = wire_sequence_get(args, 0)
      parts = StringBuffer(260)
      parts << t + ".prefix_sh = lshr i64 " + v + ", 44\n  "
      parts << t + ".prefix = and i64 " + t + ".prefix_sh, 1\n  "
      parts << t + ".full_sh = lshr i64 " + v + ", 36\n  "
      parts << t + ".full = and i64 " + t + ".full_sh, 255\n  "
      parts << t + ".compact_sh = lshr i64 " + v + ", 39\n  "
      parts << t + ".compact = and i64 " + t + ".compact_sh, 31\n  "
      parts << t + ".is_compact = icmp eq i64 " + t + ".prefix, 1\n  "
      parts << t + " = select i1 " + t + ".is_compact, i64 " + t + ".compact, i64 " + t + ".full"
      return parts.to_s()
    # Slab-AST intrinsic: w_is_node_extern(v) → 1 if v is a W_PACKED_NODE
    # (W_TAG_PACKED with subtype 3), 0 otherwise. (v >> 45) == 0x7FFF3
    # exploits the contiguous tag+subtype layout: 0xFFFE << 3 | 3.
    if wire_get(inst, :name) == "w_is_node_extern" && wire_sequence_size(args) == 1
      t = wire_get(inst, :temp)
      v = wire_sequence_get(args, 0)
      parts = StringBuffer(180)
      parts << t + ".upper = lshr i64 " + v + ", 45\n  "
      parts << t + ".is_node = icmp eq i64 " + t + ".upper, 524275\n  "
      parts << t + " = zext i1 " + t + ".is_node to i64"
      return parts.to_s()
    if wire_get(inst, :name) == "w_node_alloc" && wire_sequence_size(args) == 2
      t = wire_get(inst, :temp)
      kind_in = wire_sequence_get(args, 0)
      sc_in = wire_sequence_get(args, 1)
      parts = StringBuffer(240)
      # Defensive unbox: kind/sc here may carry the raw_int nanbox tag
      # (0xFFFA…) when they come from a runtime expression rather than a
      # literal KIND_*/SC_* global — e.g. ast_deep_clone's
      # `sc = sc_for_kind(kid)`, where the result is a `## i64` value
      # boxed into a general WValue local. Masking the low 48 bits extracts
      # the value and is idempotent for already-clean small ints.
      kind = t + ".kind_clean"
      sc = t + ".sc_clean"
      parts << kind + " = and i64 " + kind_in + ", 281474976710655\n  "
      parts << sc + " = and i64 " + sc_in + ", 281474976710655\n  "
      parts << t + " = call i64 @w_node_alloc(i64 " + kind + ", i64 " + sc + ")"
      return parts.to_s()
    slab_intrinsic = false
    if wire_get(inst, :name) == "w_node_field_load" || wire_get(inst, :name) == "w_node_field_store"
      if wire_sequence_size(args) >= 2
        first_char = wire_sequence_get(args, 1)[0]
        if first_char != "%"
          slab_intrinsic = true
    if slab_intrinsic
      t = wire_get(inst, :temp)
      n = wire_sequence_get(args, 0)
      ivar_word = wire_sequence_get(args, 1).to_i().to_s()
      parts = StringBuffer(460)
      parts << t + ".off = and i64 " + n + ", 4294967295\n  "
      parts << t + ".full = add i64 " + t + ".off, " + ivar_word + "\n  "
      parts << t + ".base_p = getelementptr inbounds { ptr, i32, i32 }, ptr @g_ast_store, i32 0, i32 0\n  "
      parts << t + ".base = load ptr, ptr " + t + ".base_p, align 8\n  "
      parts << t + ".gep = getelementptr i64, ptr " + t + ".base, i64 " + t + ".full"
      if wire_get(inst, :name) == "w_node_field_load"
        parts << "\n  " + t + " = load i64, ptr " + t + ".gep, align 8"
      else
        # Freeze array values into the AST extra arena on the inline
        # store path too — mirrors the C-side w_node_field_store hook.
        parts << "\n  " + t + ".fz = call i64 @w_ast_freeze_if_array(i64 " + wire_sequence_get(args, 2) + ")"
        parts << "\n  store i64 " + t + ".fz, ptr " + t + ".gep, align 8"
        parts << "\n  " + t + " = add i64 " + t + ".fz, 0"
      return parts.to_s()
    args_str = render_call_args(wire_get(inst, :args), wire_get(inst, :arg_types))
    base = wire_get(inst, :temp) + " = " + call_prefix(inst) + " i64 @" + wire_get(inst, :name) + "(" + args_str + ")" + known_call_range_metadata_suffix(inst, "i64")
    if wire_get(inst, :src_line) != nil && wire_get(inst, :loc_site_id) != nil
      ret_lbl = "csd." + wire_get(inst, :loc_site_id).to_s() + ".ret"
      base + "\n  br label %" + ret_lbl + "\n" + ret_lbl + ":"
    else
      base
  when :call_direct_i128
    args_str = render_call_args(wire_get(inst, :args), wire_get(inst, :arg_types))
    wire_get(inst, :temp) + " = " + call_prefix(inst) + " i128 @" + wire_get(inst, :name) + "(" + args_str + ")"
  when :call_direct_i64_ptr1
    wire_get(inst, :temp) + " = " + call_prefix(inst) + " i64 @" + wire_get(inst, :name) + "(ptr " + wire_get(inst, :arg) + ")"

  # Load a compile-time SmallArray constant.
  # The named global is a private LLVM constant emitted at module scope
  # (see the small-array-consts emission pass; align 16). W_SUBTAG_SMALL_
  # ARRAY = 9, so the box is `(ptr & ~0xF) | 9`. Because the global is
  # 16-byte aligned the low nibble is already zero and a plain `or 9`
  # suffices.
  when :small_array_const_load
    wire_get(inst, :temp) + ".raw = ptrtoint ptr " + wire_get(inst, :const_name) + " to i64\n  " + wire_get(inst, :temp) + " = or i64 " + wire_get(inst, :temp) + ".raw, 9"

  # Allocate a SmallArray on the stack via
  # LLVM `alloca`. `total_bytes` is the WSmallArray header (2) + payload
  # bytes for the literal's ebits and size. The lowering follows up with
  # a ptrtoint and a call to w_small_array_init to stamp the header and
  # apply the W_SUBTAG_SMALL_ARRAY box. align 16 keeps the low nibble
  # clear so the runtime's box can OR the subtag in safely.
  #
  # The zeroing store is NOT optional. `i64[n]` and `SmallArray.new(:i64, n)`
  # are zero-initialised by contract, and the heap forms get that from
  # calloc — but `alloca` hands back whatever the previous frame at this
  # depth left behind, and w_small_array_init writes only the 2 header
  # bytes. Without this a recursive program reads its own dead frames
  # (proved: spec/compiler/small_array_stack_zero_init_spec.w). LLVM folds
  # the store into a single llvm.memset of total_bytes; the stack path is
  # still the cheaper half of calloc (no malloc, no free).
  when :small_array_alloca
    bytes = wire_get(inst, :total_bytes).to_s()
    wire_get(inst, :temp_ptr) + " = alloca \[" + bytes + " x i8\], align 16\n  store \[" + bytes + " x i8\] zeroinitializer, ptr " + wire_get(inst, :temp_ptr) + ", align 16"
  when :call_direct_void
    args_str = render_call_args(wire_get(inst, :args), wire_get(inst, :arg_types))
    base = call_prefix(inst) + " void @" + wire_get(inst, :name) + "(" + args_str + ")"
    if wire_get(inst, :src_line) != nil && wire_get(inst, :loc_site_id) != nil
      ret_lbl = "csd." + wire_get(inst, :loc_site_id).to_s() + ".ret"
      base + "\n  br label %" + ret_lbl + "\n" + ret_lbl + ":"
    else
      base

  # Source-loc hook fired before noreturn Tungsten calls (w_raise).
  # Writes (file, line, col) to thread-locals so the error formatter
  # recovers precise location even when the side-table misses.
  when :call_loc_set_col
    used_ptr_ids[wire_get(inst, :file_str_id)] = true
    lbr = "\["
    rbr = "]"
    bl = wire_get(inst, :file_byte_len).to_s()
    wire_get(inst, :temp_ptr) + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :file_str_id).to_s() + ", i32 0, i32 0\n  call void @__w_loc_set_col(ptr " + wire_get(inst, :temp_ptr) + ", i32 " + wire_get(inst, :line).to_s() + ", i32 " + wire_get(inst, :col).to_s() + ")"
  when :call_direct_void_ptr1
    call_prefix(inst) + " void @" + wire_get(inst, :name) + "(ptr " + wire_get(inst, :arg) + ")"
  when :call_direct_ptr
    args_str = render_call_args(wire_get(inst, :args), wire_get(inst, :arg_types))
    wire_get(inst, :temp) + " = " + call_prefix(inst) + " ptr @" + wire_get(inst, :name) + "(" + args_str + ")"

  # Call-site reuse allocation — per-site thread-local slot, reused across
  # calls. First call allocates and stores in the slot; subsequent calls
  # reset length and return the cached buffer. Zero malloc steady-state.
  when :call_reuse_or_new_array
    wire_get(inst, :temp) + " = call i64 @w_array_reuse_or_new_empty(ptr @" + wire_get(inst, :slot) + ")"
  when :call_reuse_or_new_hash
    wire_get(inst, :temp) + " = call i64 @w_hash_reuse_or_new(ptr @" + wire_get(inst, :slot) + ")"
  when :call_reuse_or_new_typed
    wire_get(inst, :temp) + " = call i64 @w_array_reuse_or_new(ptr @" + wire_get(inst, :slot) + ", i64 " + wire_get(inst, :bits).to_s() + ", i64 " + wire_get(inst, :cap) + ")"
  when :call_fused_out_reuse
    wire_get(inst, :temp) + " = call i64 @w_fused_out_reuse_or_new(ptr @" + wire_get(inst, :slot) + ", i64 " + wire_get(inst, :bits).to_s() + ", i64 " + wire_get(inst, :cap) + ")"
  when :call_reuse_or_new_strbuf
    wire_get(inst, :temp) + " = call i64 @w_strbuf_reuse_or_new(ptr @" + wire_get(inst, :slot) + ", i64 " + wire_get(inst, :cap) + ")"
  when :call_reuse_and_drain_or_new_hash
    wire_get(inst, :temp) + " = call i64 @w_hash_reuse_and_drain_or_new(ptr @" + wire_get(inst, :slot) + ")"

  # Recycle pool allocation (## recycle): pop from thread-local pool or alloc.
  when :call_recycle_or_new_array
    wire_get(inst, :temp) + " = call i64 @w_array_recycle_or_new_empty()"
  when :call_recycle_or_new_hash
    wire_get(inst, :temp) + " = call i64 @w_hash_recycle_or_new()"
  when :call_recycle_or_new_typed
    wire_get(inst, :temp) + " = call i64 @w_array_recycle_or_new(i64 " + wire_get(inst, :bits).to_s() + ", i64 " + wire_get(inst, :cap) + ")"
  when :call_recycle_or_new_strbuf
    wire_get(inst, :temp) + " = call i64 @w_strbuf_recycle_or_new(i64 " + wire_get(inst, :cap) + ")"

  # Recycle return-to-pool (emitted at scope exit for ## recycle vars).
  when :call_recycle_array
    "call void @w_array_recycle_public(i64 " + wire_get(inst, :value) + ")"
  when :call_recycle_hash
    "call void @w_hash_recycle(i64 " + wire_get(inst, :value) + ")"
  when :call_recycle_typed
    "call void @w_array_recycle(i64 " + wire_get(inst, :value) + ")"
  when :call_recycle_strbuf
    "call void @w_strbuf_recycle(i64 " + wire_get(inst, :value) + ")"

  # Cleanup stack push/pop for exception-safe recycle. Push after alloc,
  # pop just before the normal-path recycle fires. On w_raise, any entries
  # above the enclosing exception frame's saved cleanup_depth are invoked.
  when :cleanup_push_array
    "call void @w_cleanup_push(i64 " + wire_get(inst, :value) + ", ptr @w_array_recycle_public)"
  when :cleanup_push_hash
    "call void @w_cleanup_push(i64 " + wire_get(inst, :value) + ", ptr @w_hash_recycle)"
  when :cleanup_push_typed
    "call void @w_cleanup_push(i64 " + wire_get(inst, :value) + ", ptr @w_array_recycle)"
  when :cleanup_push_strbuf
    "call void @w_cleanup_push(i64 " + wire_get(inst, :value) + ", ptr @w_strbuf_recycle)"
  when :cleanup_pop
    "call void @w_cleanup_pop()"

  # Exception handling
  when :setjmp
    jump_name = windows_target ? "setjmp" : "_setjmp"
    wire_get(inst, :temp) + " = call i32 @" + jump_name + "(ptr " + wire_get(inst, :buf) + ")"
  when :icmp_eq_i32
    wire_get(inst, :temp) + " = icmp eq i32 " + wire_get(inst, :lhs) + ", " + wire_get(inst, :rhs)

  # Method dispatch (dynamic) — inline-cached via w_method_call_cached.
  # When the call carries source-loc info, split the basic block so the
  # return address is addressable via blockaddress(@fn, %cs.N.ret). Same
  # pattern the overflow-check ops use (see :add_i48_checked).
  when :call_method_i64
    args = wire_get(inst, :args)
    argc = wire_sequence_size(args)
    ic_ptr = wire_get(inst, :temp) + ".ic"
    ic_id = wire_get(inst, :ic_id).to_s()
    ic_gep = ic_ptr + " = getelementptr inbounds \[24 x i8], ptr @.ic, i64 " + ic_id + "\n  "
    ic_arg = ", ptr " + ic_ptr
    name_val = wire_get(inst, :method_name_val)
    parts = StringBuffer(128 + argc * 64)
    parts << ic_gep
    # Guarded devirtualization (lowering attaches devirt_fn/devirt_class when
    # the receiver's exact class is statically known): receiver is a WObject
    # (obj space, subtag 4) whose class_id (u16 at +0) equals @class.<C>'s
    # class_id (u16 at +16 in WClass) -> direct call to the method's function
    # symbol; anything else -> the ordinary IC dispatch below. The direct arm
    # skips dispatch entirely and lets LLVM inline small method bodies.
    dv_temp = wire_get(inst, :temp)
    if wire_get(inst, :devirt_fn) != nil
      t = wire_get(inst, :temp)
      lbl = "dv." + ic_id
      parts << t + ".hi = lshr i64 " + wire_get(inst, :receiver) + ", 48\n  "
      parts << t + ".z = icmp eq i64 " + t + ".hi, 0\n  "
      parts << t + ".ge = icmp uge i64 " + wire_get(inst, :receiver) + ", 16\n  "
      parts << t + ".o = and i1 " + t + ".z, " + t + ".ge\n  "
      parts << t + ".sb = and i64 " + wire_get(inst, :receiver) + ", 15\n  "
      parts << t + ".isi = icmp eq i64 " + t + ".sb, 4\n  "
      parts << t + ".oi = and i1 " + t + ".o, " + t + ".isi\n  "
      parts << "br i1 " + t + ".oi, label %" + lbl + ".ck, label %" + lbl + ".s\n"
      parts << lbl + ".ck:\n  "
      parts << t + ".om = and i64 " + wire_get(inst, :receiver) + ", -16\n  "
      parts << t + ".op = inttoptr i64 " + t + ".om to ptr\n  "
      parts << t + ".oc = load i16, ptr " + t + ".op, align 2\n  "
      parts << t + ".cw = load i64, ptr @class." + llvm_safe_name(wire_get(inst, :devirt_class).gsub(":", "__")) + "\n  "
      parts << t + ".cm = and i64 " + t + ".cw, -16\n  "
      parts << t + ".cp = inttoptr i64 " + t + ".cm to ptr\n  "
      parts << t + ".cip = getelementptr i8, ptr " + t + ".cp, i64 16\n  "
      parts << t + ".cc = load i16, ptr " + t + ".cip, align 2\n  "
      parts << t + ".same = icmp eq i16 " + t + ".oc, " + t + ".cc\n  "
      parts << "br i1 " + t + ".same, label %" + lbl + ".d, label %" + lbl + ".s\n"
      parts << lbl + ".d:\n  "
      parts << t + ".dv = call i64 @" + wire_get(inst, :devirt_fn) + "(i64 " + wire_get(inst, :receiver)
      di = 0
      while di < argc
        parts << ", i64 " + wire_sequence_get(args, di)
        di += 1
      parts << ")\n  "
      parts << "br label %" + lbl + ".done\n"
      parts << lbl + ".s:\n  "
      dv_temp = t + ".sv"
    elsif wire_get(inst, :construct_fn) != nil
      t = wire_get(inst, :temp)
      lbl = "dv." + ic_id
      parts << t + ".cw = load i64, ptr @class." + llvm_safe_name(wire_get(inst, :construct_class).gsub(":", "__")) + "\n  "
      parts << t + ".same = icmp eq i64 " + wire_get(inst, :receiver) + ", " + t + ".cw\n  "
      parts << "br i1 " + t + ".same, label %" + lbl + ".d, label %" + lbl + ".s\n"
      parts << lbl + ".d:\n  "
      parts << t + ".dv = call i64 @w_object_new(i64 " + wire_get(inst, :receiver) + ")\n  "
      parts << t + ".init = call i64 @" + wire_get(inst, :construct_fn) + "(i64 " + t + ".dv"
      di = 0
      while di < argc
        parts << ", i64 " + wire_sequence_get(args, di)
        di += 1
      parts << ")\n  "
      parts << "br label %" + lbl + ".done\n"
      parts << lbl + ".s:\n  "
      dv_temp = t + ".sv"
    # `notail` prevents LLVM from collapsing the call+ret pair into a tail
    # call when we need a real return address for the call-site lookup.
    # Without this, -O3 converts `call + br + ret` into a `b` (unconditional
    # branch) and the block-address we emit into @__w_call_site never matches
    # any PC captured by `backtrace()`.
    call_keyword = "call"
    if wire_get(inst, :src_line) != nil
      call_keyword = "notail call"
    if argc == 0
      parts << dv_temp + " = " + call_keyword + " i64 @w_method_call_cached_0(i64 " + wire_get(inst, :receiver) + ", i64 " + name_val + ic_arg + ")"
    elsif scalar_source_one_call?(inst)
      parts << dv_temp + " = " + call_keyword + " i64 @w_method_call_cached_1(i64 " + wire_get(inst, :receiver) + ", i64 " + name_val + ", i64 " + wire_sequence_get(args, 0) + ic_arg + ")"
    elsif scalar_source_two_call?(inst)
      parts << dv_temp + " = " + call_keyword + " i64 @w_method_call_cached_2(i64 " + wire_get(inst, :receiver) + ", i64 " + name_val + ", i64 " + wire_sequence_get(args, 0) + ", i64 " + wire_sequence_get(args, 1) + ic_arg + ")"
    else
      stack_arr = "%__mcall_args"
      i = 0
      while i < argc
        if i == 0
          slot = stack_arr
        else
          slot = wire_get(inst, :temp_args_val) + "." + i.to_s()
          parts << slot + " = getelementptr inbounds i64, ptr " + stack_arr + ", i32 " + i.to_s() + "\n  "
        parts << "store i64 " + wire_sequence_get(args, i) + ", ptr " + slot + ", align 8\n  "
        i += 1
      parts << dv_temp + " = " + call_keyword + " i64 @w_method_call_cached(i64 " + wire_get(inst, :receiver) + ", i64 " + name_val + ", ptr " + stack_arr + ", i32 " + argc.to_s() + ic_arg + ")"
    if wire_get(inst, :src_line) != nil
      ret_lbl = "cs." + ic_id + ".ret"
      parts << "\n  br label %"
      parts << ret_lbl
      parts << "\n"
      parts << ret_lbl
      parts << ":"
    if wire_get(inst, :devirt_fn) != nil || wire_get(inst, :construct_fn) != nil
      t = wire_get(inst, :temp)
      lbl = "dv." + ic_id
      # The slow arm's value is defined in whichever block the IC render
      # left us in: the cs.N.ret continuation when a call-site table entry
      # was emitted, else the dv.N.s block itself.
      slow_pred = lbl + ".s"
      if wire_get(inst, :src_line) != nil
        slow_pred = "cs." + ic_id + ".ret"
      parts << "\n  br label %" + lbl + ".done\n"
      parts << lbl + ".done:\n  "
      parts << t + " = phi i64 \[" + t + ".dv, %" + lbl + ".d], \[" + t + ".sv, %" + slow_pred + "]"
    parts.to_s()

  # Control flow
  when :br
    unroll_count = wire_get(inst, :unroll_count)
    if wire_get(inst, :novec) == true && unroll_count != nil && unroll_count > 0
      "br label %" + wire_get(inst, :label) + ", !llvm.loop !" + latch_loop_md_ref_for(inst, :both, unroll_count)
    elsif wire_get(inst, :novec) == true
      "br label %" + wire_get(inst, :label) + ", !llvm.loop !" + latch_loop_md_ref_for(inst, :novec)
    elsif unroll_count != nil && unroll_count > 0
      "br label %" + wire_get(inst, :label) + ", !llvm.loop !" + latch_loop_md_ref_for(inst, :unroll, unroll_count)
    else
      "br label %" + wire_get(inst, :label)
  when :cond_br
    prof = ""
    if wire_get(inst, :prof) == :likely
      prof = ", !prof !31411"
    elsif wire_get(inst, :prof) == :unlikely
      prof = ", !prof !31412"
    "br i1 " + wire_get(inst, :cond) + ", label %" + wire_get(inst, :then_label) + ", label %" + wire_get(inst, :else_label) + prof

  # i64 add with an overflow flag: temp = sum, temp.ovf = i1. Feeds the
  # sum-chunk accumulator's flush branch; lhs/rhs ride the substituted
  # fields so SSA renames reach them.
  when :sadd_with_overflow
    t = wire_get(inst, :temp)
    t + ".pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 " + wire_get(inst, :lhs) + ", i64 " + wire_get(inst, :rhs) + ")\n  " + t + " = extractvalue {i64, i1} " + t + ".pair, 0\n  " + t + ".ovf = extractvalue {i64, i1} " + t + ".pair, 1"
  when :switch_i64
    cases = wire_get(inst, :cases)
    is_symbol = wire_get(inst, :is_symbol)
    out = StringBuffer(96 + wire_sequence_size(cases) * 48)
    out << "switch i64 " + wire_get(inst, :value) + ", label %" + wire_get(inst, :default_label) + " \[\n"
    i = 0
    while i < wire_sequence_size(cases)
      c = wire_sequence_get(cases, i)
      # Case key resolution: cases with :string_id are medium-length
      # (6-61 byte) symbol or string arms whose slab WValue isn't
      # known until build_string_wvalues assigns the slot. Resolve
      # via string_wvs at emit time. For symbol switches, OR in the
      # `| 1` symbol bit; for string switches, keep the bare slab
      # WValue. SSO-5 keys already have the symbol bit (or not)
      # baked into their literal value at lowering time.
      key_text = nil
      sid = c[:string_id]
      if sid != nil
        swv = nil
        if string_wvs != nil
          swv = string_wvs[sid]
        if swv == nil
          # Heap-mode string (>61 bytes): WValue isn't compile-time
          # known. The case lowering's guard should have rejected
          # this; if we reach here it's a bug — bail to a value
          # that will never match the subject.
          key_text = "0"
        else
          if is_symbol == true
            key_text = llvm_wvalue_literal(swv + 1)
          else
            key_text = llvm_wvalue_literal(swv)
      else
        key_text = c[:value].to_s()
      out << "    i64 " + key_text + ", label %" + c[:label] + "\n"
      i += 1
    out << "  ]"
    out.to_s()
  when :ret_i64
    "ret i64 " + (wire_get(inst, :value) == nil ? "0" : wire_get(inst, :value).to_s())
  when :ret_i32
    "ret i32 " + (wire_get(inst, :value) == nil ? "0" : wire_get(inst, :value).to_s())
  when :ret_void
    "ret void"
  when :unreachable
    "unreachable"

  # Phi
  when :phi_i1
    lbr = "\["
    rbr = "]"
    a_label = redirect_phi_label(wire_get(inst, :a_label), phi_label_redirects)
    b_label = redirect_phi_label(wire_get(inst, :b_label), phi_label_redirects)
    wire_get(inst, :temp) + " = phi i1 " + lbr + " " + wire_get(inst, :a_value) + ", %" + a_label + " " + rbr + ", " + lbr + " " + wire_get(inst, :b_value) + ", %" + b_label + " " + rbr
  when :phi_i64
    lbr = "\["
    rbr = "]"
    a_label = redirect_phi_label(wire_get(inst, :a_label), phi_label_redirects)
    b_label = redirect_phi_label(wire_get(inst, :b_label), phi_label_redirects)
    wire_get(inst, :temp) + " = phi i64 " + lbr + " " + wire_get(inst, :a_value) + ", %" + a_label + " " + rbr + ", " + lbr + " " + wire_get(inst, :b_value) + ", %" + b_label + " " + rbr

  # Argv init (main preamble)
  when :argv_init
    "call void @w_argv_init(i32 %argc, ptr %argv)"

  # I/O
  when :puts_i64
    if wire_get(inst, :temp) != nil
      wire_get(inst, :temp) + " = call i64 @w_puts(i64 " + wire_get(inst, :value) + ")"
    else
      "call i64 @w_puts(i64 " + wire_get(inst, :value) + ")"
  when :print_i64
    if wire_get(inst, :temp) != nil
      wire_get(inst, :temp) + " = call i64 @w_print(i64 " + wire_get(inst, :value) + ")"
    else
      "call i64 @w_print(i64 " + wire_get(inst, :value) + ")"

  # Memoization
  when :memo_init
    wire_get(inst, :temp) + " = call ptr @w_memo_init(ptr null)"
  when :store_memo_ptr
    "store ptr " + wire_get(inst, :value) + ", ptr @" + wire_get(inst, :global)
  when :load_memo_ptr
    wire_get(inst, :temp) + " = load ptr, ptr @" + wire_get(inst, :global)
  when :memo_call0_i64
    wire_get(inst, :temp) + " = call i64 @__w_memo_call0_i64(ptr " + wire_get(inst, :table) + ", ptr @" + wire_get(inst, :fn_name) + ")"
  when :memo_call1_i64
    wire_get(inst, :temp) + " = call i64 @__w_memo_call1_i64(ptr " + wire_get(inst, :table) + ", ptr @" + wire_get(inst, :fn_name) + ", i64 " + wire_sequence_get(wire_get(inst, :args), 0) + ")"
  when :memo_call2_i64
    wire_get(inst, :temp) + " = call i64 @__w_memo_call2_i64(ptr " + wire_get(inst, :table) + ", ptr @" + wire_get(inst, :fn_name) + ", i64 " + wire_sequence_get(wire_get(inst, :args), 0) + ", i64 " + wire_sequence_get(wire_get(inst, :args), 1) + ")"

  # Classes
  when :class_new
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :name_str_id)]
    if swv != nil
      super_arg = nil
      if wire_get(inst, :super_reg) != nil
        super_arg = wire_get(inst, :super_reg)
      else
        super_arg = w_nil.to_s()
      wire_get(inst, :temp) + " = call i64 @w_class_new_wv(i64 " + llvm_wvalue_literal(swv) + ", i64 " + super_arg + ")"
    else
      used_ptr_ids[wire_get(inst, :name_str_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :name_byte_len).to_s()
      parts = StringBuffer(160)
      parts << wire_get(inst, :temp) + ".ptr = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :name_str_id).to_s() + ", i32 0, i32 0\n  "
      parts << wire_get(inst, :temp) + ".name = call i64 @w_string(ptr " + wire_get(inst, :temp) + ".ptr)\n  "
      super_arg = nil
      if wire_get(inst, :super_reg) != nil
        super_arg = wire_get(inst, :super_reg)
      else
        super_arg = w_nil.to_s()
      parts << wire_get(inst, :temp) + " = call i64 @w_class_new_wv(i64 " + wire_get(inst, :temp) + ".name, i64 " + super_arg + ")"
      parts.to_s()
  when :class_store
    "store i64 " + wire_get(inst, :value) + ", ptr @class." + llvm_safe_name(wire_get(inst, :class_name).gsub(":", "__"))
  when :type_class_register
    "call void @w_type_class_register_wv(i32 " + wire_get(inst, :dispatch_key).to_s() + ", i64 " + wire_get(inst, :class_temp) + ")"
  when :node_kind_class_register
    "call void @w_node_kind_class_register_wv(i32 " + wire_get(inst, :kind_id).to_s() + ", i64 " + wire_get(inst, :class_temp) + ")"
  when :class_add_method
    add_fn = "w_class_add_method_wv"
    add_args = ", i32 " + wire_get(inst, :arity).to_s()
    if wire_get(inst, :splat_index) != nil && wire_get(inst, :splat_index) >= 0
      add_fn = "w_class_add_method_splat_wv"
      add_args += ", i32 " + wire_get(inst, :min_arity).to_s() + ", i32 " + wire_get(inst, :splat_index).to_s()
    elsif wire_get(inst, :min_arity) != nil && wire_get(inst, :min_arity) < wire_get(inst, :arity)
      add_fn = "w_class_add_method_range_wv"
      add_args += ", i32 " + wire_get(inst, :min_arity).to_s()
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :method_str_id)]
    if swv != nil
      "call void @" + add_fn + "(i64 " + wire_get(inst, :class_temp) + ", i64 " + llvm_wvalue_literal(swv) + ", ptr @" + wire_get(inst, :fn_name) + add_args + ")"
    else
      used_ptr_ids[wire_get(inst, :method_str_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :method_byte_len).to_s()
      parts = StringBuffer(160)
      parts << wire_get(inst, :class_temp) + ".mname = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :method_str_id).to_s() + ", i32 0, i32 0\n  "
      parts << wire_get(inst, :class_temp) + ".mname.wv = call i64 @w_string(ptr " + wire_get(inst, :class_temp) + ".mname)\n  "
      parts << "call void @" + add_fn + "(i64 " + wire_get(inst, :class_temp) + ", i64 " + wire_get(inst, :class_temp) + ".mname.wv, ptr @" + wire_get(inst, :fn_name) + add_args + ")"
      parts.to_s()
  when :class_add_static_method
    add_fn = "w_class_add_static_method_wv"
    add_args = ", i32 " + wire_get(inst, :arity).to_s()
    if wire_get(inst, :splat_index) != nil && wire_get(inst, :splat_index) >= 0
      add_fn = "w_class_add_static_method_splat_wv"
      add_args += ", i32 " + wire_get(inst, :min_arity).to_s() + ", i32 " + wire_get(inst, :splat_index).to_s()
    elsif wire_get(inst, :min_arity) != nil && wire_get(inst, :min_arity) < wire_get(inst, :arity)
      add_fn = "w_class_add_static_method_range_wv"
      add_args += ", i32 " + wire_get(inst, :min_arity).to_s()
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :method_str_id)]
    if swv != nil
      "call void @" + add_fn + "(i64 " + wire_get(inst, :class_temp) + ", i64 " + llvm_wvalue_literal(swv) + ", ptr @" + wire_get(inst, :fn_name) + add_args + ")"
    else
      used_ptr_ids[wire_get(inst, :method_str_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :method_byte_len).to_s()
      parts = StringBuffer(160)
      parts << wire_get(inst, :class_temp) + ".smname = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :method_str_id).to_s() + ", i32 0, i32 0\n  "
      parts << wire_get(inst, :class_temp) + ".smname.wv = call i64 @w_string(ptr " + wire_get(inst, :class_temp) + ".smname)\n  "
      parts << "call void @" + add_fn + "(i64 " + wire_get(inst, :class_temp) + ", i64 " + wire_get(inst, :class_temp) + ".smname.wv, ptr @" + wire_get(inst, :fn_name) + add_args + ")"
      parts.to_s()
  when :load_class
    wire_get(inst, :temp) + " = load i64, ptr @class." + llvm_safe_name(wire_get(inst, :class_name).gsub(":", "__"))
  when :store_global
    t = wire_get(inst, :type)
    if t == nil
      t = "i64"
    "store " + t + " " + wire_get(inst, :value) + ", ptr @global." + llvm_safe_name(wire_get(inst, :name))
  when :load_global
    t = wire_get(inst, :type)
    if t == nil
      t = "i64"
    wire_get(inst, :temp) + " = load " + t + ", ptr @global." + llvm_safe_name(wire_get(inst, :name))
  when :store_cvar
    "store i64 " + wire_get(inst, :value) + ", ptr @cvar." + llvm_safe_name(wire_get(inst, :cvar_key).gsub(":", "__"))
  when :load_cvar
    wire_get(inst, :temp) + " = load i64, ptr @cvar." + llvm_safe_name(wire_get(inst, :cvar_key).gsub(":", "__"))
  when :typed_array_get_inline
    # Inline typed array read: unmask → slots ptr (off 16) → start i32 (off 4) → GEP → load → ext
    # The i32 demote moved offsets: slots 32→16, start 8→4. Start is now
    # i32 and gets sign-extended before being added to the unboxed index.
    # Offsets locked by _Static_assert in runtime.h.
    t = wire_get(inst, :temp)
    s = wire_get(inst, :s)
    s0 = wire_sequence_get(s, 0)
    s1 = wire_sequence_get(s, 1)
    s2 = wire_sequence_get(s, 2)
    s3 = wire_sequence_get(s, 3)
    s4 = wire_sequence_get(s, 4)
    s5 = wire_sequence_get(s, 5)
    s6 = wire_sequence_get(s, 6)
    s7 = wire_sequence_get(s, 7)
    s8 = wire_sequence_get(s, 8)
    s9 = wire_sequence_get(s, 9)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    idx_raw = wire_get(inst, :idx_raw)
    bits = wire_get(inst, :bits)
    if bits == nil
      bits = 64
    signed = wire_get(inst, :signed)
    if signed == nil
      signed = true
    parts = StringBuffer(700)
    parts << s0 + " = and i64 " + arr + ", 140737488355312\n  "   # unmask (W_ARRAY_PTR_MASK)
    parts << s1 + " = inttoptr i64 " + s0 + " to ptr\n  "      # struct ptr
    parts << s2 + " = getelementptr i8, ptr " + s1 + ", i64 16\n  "  # &slots
    parts << s3 + " = load ptr, ptr " + s2 + ", align 8" + tbaa_header_suffix() + "\n  "    # slots ptr — re-read each access: realloc (push/unshift past cap, clear) moves it, so NOT invariant. TBAA=header lets LICM hoist it when no realloc is in the loop.
    parts << s4 + " = getelementptr i8, ptr " + s1 + ", i64 4\n  "  # &start
    parts << s5 + ".raw32 = load i32, ptr " + s4 + ", align 4" + tbaa_header_suffix() + "\n  "  # start (i32) — re-read: shift/unshift move it. TBAA=header, same rationale.
    parts << s5 + " = sext i32 " + s5 + ".raw32 to i64\n  "    # start (i64 for GEP arithmetic)
    if idx_raw == true
      # Raw index — use directly, fill unused scratch with dummy values
      parts << s6 + " = add i64 0, 0\n  "
      parts << s7 + " = add i64 0, 0\n  "
      parts << s8 + " = add i64 " + s5 + ", " + idx + "\n  "
    else
      parts << s6 + " = shl i64 " + idx + ", 16\n  "
      parts << s7 + " = ashr i64 " + s6 + ", 16\n  "
      parts << s8 + " = add i64 " + s5 + ", " + s7 + "\n  "
    if bits == 64
      parts << s9 + " = getelementptr i64, ptr " + s3 + ", i64 " + s8 + "\n  "
      parts << t + " = load i64, ptr " + s9 + ", align 8" + tbaa_elem_suffix()
    elsif bits == 32
      parts << s9 + " = getelementptr i32, ptr " + s3 + ", i64 " + s8 + "\n  "
      raw = t + ".raw"
      parts << raw + " = load i32, ptr " + s9 + ", align 4" + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i32 " + raw + " to i64"
      else
        parts << t + " = zext i32 " + raw + " to i64"
    elsif bits == 16
      parts << s9 + " = getelementptr i16, ptr " + s3 + ", i64 " + s8 + "\n  "
      raw = t + ".raw"
      parts << raw + " = load i16, ptr " + s9 + ", align 2" + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i16 " + raw + " to i64"
      else
        parts << t + " = zext i16 " + raw + " to i64"
    elsif bits == 8
      parts << s9 + " = getelementptr i8, ptr " + s3 + ", i64 " + s8 + "\n  "
      raw = t + ".raw"
      parts << raw + " = load i8, ptr " + s9 + ", align 1" + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i8 " + raw + " to i64"
      else
        parts << t + " = zext i8 " + raw + " to i64"
    elsif bits == 4
      byte_idx = t + ".byteidx"
      raw8 = t + ".raw8"
      raw64 = t + ".raw64"
      slot = t + ".slot"
      shift = t + ".shift"
      shifted = t + ".shifted"
      nibble = t + ".nibble"
      parts << byte_idx + " = lshr i64 " + s8 + ", 1\n  "
      parts << s9 + " = getelementptr i8, ptr " + s3 + ", i64 " + byte_idx + "\n  "
      parts << raw8 + " = load i8, ptr " + s9 + ", align 1" + tbaa_elem_suffix() + "\n  "
      parts << raw64 + " = zext i8 " + raw8 + " to i64\n  "
      parts << slot + " = and i64 " + s8 + ", 1\n  "
      parts << shift + " = shl i64 " + slot + ", 2\n  "
      parts << shifted + " = lshr i64 " + raw64 + ", " + shift + "\n  "
      parts << nibble + " = and i64 " + shifted + ", 15\n  "
      if signed == true
        signbits = t + ".signbits"
        parts << signbits + " = shl i64 " + nibble + ", 60\n  "
        parts << t + " = ashr i64 " + signbits + ", 60"
      else
        parts << t + " = add i64 " + nibble + ", 0"
    else
      parts << s9 + " = getelementptr i64, ptr " + s3 + ", i64 " + s8 + "\n  "
      parts << t + " = load i64, ptr " + s9 + ", align 8" + tbaa_elem_suffix()
    parts.to_s()
  when :typed_array_set_inline
    # Inline typed array write: same i32-offset shift as get.
    t = wire_get(inst, :temp)
    s = wire_get(inst, :s)
    s0 = wire_sequence_get(s, 0)
    s1 = wire_sequence_get(s, 1)
    s2 = wire_sequence_get(s, 2)
    s3 = wire_sequence_get(s, 3)
    s4 = wire_sequence_get(s, 4)
    s5 = wire_sequence_get(s, 5)
    s6 = wire_sequence_get(s, 6)
    s7 = wire_sequence_get(s, 7)
    s8 = wire_sequence_get(s, 8)
    s9 = wire_sequence_get(s, 9)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    idx_raw = wire_get(inst, :idx_raw)
    val = wire_get(inst, :value)
    bits = wire_get(inst, :bits)
    if bits == nil
      bits = 64
    parts = StringBuffer(700)
    parts << s0 + " = and i64 " + arr + ", 140737488355312\n  "
    parts << s1 + " = inttoptr i64 " + s0 + " to ptr\n  "
    parts << s2 + " = getelementptr i8, ptr " + s1 + ", i64 16\n  "  # &slots (i32 demote: was 32)
    parts << s3 + " = load ptr, ptr " + s2 + ", align 8" + tbaa_header_suffix() + "\n  "    # slots ptr — re-read each access: realloc (push/unshift past cap, clear) moves it. TBAA=header lets LICM hoist it when no realloc is in the loop.
    parts << s4 + " = getelementptr i8, ptr " + s1 + ", i64 4\n  "   # &start (i32 demote: was 8)
    parts << s5 + ".raw32 = load i32, ptr " + s4 + ", align 4" + tbaa_header_suffix() + "\n  "   # start (i32) — re-read: shift/unshift move it. TBAA=header, same rationale.
    parts << s5 + " = sext i32 " + s5 + ".raw32 to i64\n  "
    if idx_raw == true
      parts << s6 + " = add i64 0, 0\n  "
      parts << s7 + " = add i64 " + idx + ", 0\n  "
      parts << s8 + " = add i64 " + s5 + ", " + idx + "\n  "
    else
      parts << s6 + " = shl i64 " + idx + ", 16\n  "
      parts << s7 + " = ashr i64 " + s6 + ", 16\n  "
      parts << s8 + " = add i64 " + s5 + ", " + s7 + "\n  "
    if bits == 64
      parts << s9 + " = getelementptr i64, ptr " + s3 + ", i64 " + s8 + "\n  "
      parts << "store i64 " + val + ", ptr " + s9 + ", align 8" + tbaa_elem_suffix() + "\n  "
    elsif bits == 32
      parts << s9 + " = getelementptr i32, ptr " + s3 + ", i64 " + s8 + "\n  "
      tr = t + ".trunc"
      parts << tr + " = trunc i64 " + val + " to i32\n  "
      parts << "store i32 " + tr + ", ptr " + s9 + ", align 4" + tbaa_elem_suffix() + "\n  "
    elsif bits == 16
      parts << s9 + " = getelementptr i16, ptr " + s3 + ", i64 " + s8 + "\n  "
      tr = t + ".trunc"
      parts << tr + " = trunc i64 " + val + " to i16\n  "
      parts << "store i16 " + tr + ", ptr " + s9 + ", align 2" + tbaa_elem_suffix() + "\n  "
    elsif bits == 8
      parts << s9 + " = getelementptr i8, ptr " + s3 + ", i64 " + s8 + "\n  "
      tr = t + ".trunc"
      parts << tr + " = trunc i64 " + val + " to i8\n  "
      parts << "store i8 " + tr + ", ptr " + s9 + ", align 1" + tbaa_elem_suffix() + "\n  "
    elsif bits == 4
      byte_idx = t + ".byteidx"
      raw8 = t + ".raw8"
      raw64 = t + ".raw64"
      slot = t + ".slot"
      shift = t + ".shift"
      mask = t + ".mask"
      clear_mask = t + ".clear_mask"
      cleared = t + ".cleared"
      nibble = t + ".nibble"
      shifted = t + ".shifted"
      merged = t + ".merged"
      tr = t + ".trunc"
      parts << byte_idx + " = lshr i64 " + s8 + ", 1\n  "
      parts << s9 + " = getelementptr i8, ptr " + s3 + ", i64 " + byte_idx + "\n  "
      parts << raw8 + " = load i8, ptr " + s9 + ", align 1" + tbaa_elem_suffix() + "\n  "
      parts << raw64 + " = zext i8 " + raw8 + " to i64\n  "
      parts << slot + " = and i64 " + s8 + ", 1\n  "
      parts << shift + " = shl i64 " + slot + ", 2\n  "
      parts << mask + " = shl i64 15, " + shift + "\n  "
      parts << clear_mask + " = xor i64 " + mask + ", 255\n  "
      parts << cleared + " = and i64 " + raw64 + ", " + clear_mask + "\n  "
      parts << nibble + " = and i64 " + val + ", 15\n  "
      parts << shifted + " = shl i64 " + nibble + ", " + shift + "\n  "
      parts << merged + " = or i64 " + cleared + ", " + shifted + "\n  "
      parts << tr + " = trunc i64 " + merged + " to i8\n  "
      parts << "store i8 " + tr + ", ptr " + s9 + ", align 1" + tbaa_elem_suffix() + "\n  "
    else
      parts << s9 + " = getelementptr i64, ptr " + s3 + ", i64 " + s8 + "\n  "
      parts << "store i64 " + val + ", ptr " + s9 + ", align 8" + tbaa_elem_suffix() + "\n  "
    # No size-grow update: T[N] / Array.new constructors set size == cap
    # at allocation, and the inline `[]=` path is only emitted when the
    # store stays within that preallocated range.
    parts << t + " = add i64 " + val + ", 0"
    parts.to_s()

  # Fused inline compound op: `arr[i] = arr[i] OP X`. Emits one pointer
  # chain (untag, slots ptr, start) and one GEP, then load + op + store
  # in the slot's native width. Lifted from typed_array_set_inline; only
  # emitted for integer typed-arrays in widths 8/16/32/64.
  when :typed_array_compound_op_inline
    t = wire_get(inst, :temp)
    s = wire_get(inst, :s)
    s0 = wire_sequence_get(s, 0)
    s1 = wire_sequence_get(s, 1)
    s2 = wire_sequence_get(s, 2)
    s3 = wire_sequence_get(s, 3)
    s4 = wire_sequence_get(s, 4)
    s5 = wire_sequence_get(s, 5)
    s6 = wire_sequence_get(s, 6)
    s7 = wire_sequence_get(s, 7)
    s8 = wire_sequence_get(s, 8)
    s9 = wire_sequence_get(s, 9)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    idx_raw = wire_get(inst, :idx_raw)
    val = wire_get(inst, :value)
    compound_op = wire_get(inst, :compound_op)
    bits = wire_get(inst, :bits)
    if bits == nil
      bits = 64
    signed = wire_get(inst, :signed)
    if signed == nil
      signed = false
    llvm_op = nil
    case compound_op
    when :PLUS
      llvm_op = "add"
    when :MINUS
      llvm_op = "sub"
    when :STAR
      llvm_op = "mul"
    when :PIPE
      llvm_op = "or"
    when :AMPERSAND
      llvm_op = "and"
    when :CARET
      llvm_op = "xor"
    when :LSHIFT
      llvm_op = "shl"
    when :RSHIFT
      if signed == true
        llvm_op = "ashr"
      else
        llvm_op = "lshr"
    parts = StringBuffer(700)
    parts << s0 + " = and i64 " + arr + ", 140737488355312\n  "
    parts << s1 + " = inttoptr i64 " + s0 + " to ptr\n  "
    parts << s2 + " = getelementptr i8, ptr " + s1 + ", i64 16\n  "
    parts << s3 + " = load ptr, ptr " + s2 + ", align 8" + tbaa_header_suffix() + "\n  "
    parts << s4 + " = getelementptr i8, ptr " + s1 + ", i64 4\n  "
    parts << s5 + ".raw32 = load i32, ptr " + s4 + ", align 4" + tbaa_header_suffix() + "\n  "
    parts << s5 + " = sext i32 " + s5 + ".raw32 to i64\n  "
    if idx_raw == true
      parts << s6 + " = add i64 0, 0\n  "
      parts << s7 + " = add i64 0, 0\n  "
      parts << s8 + " = add i64 " + s5 + ", " + idx + "\n  "
    else
      parts << s6 + " = shl i64 " + idx + ", 16\n  "
      parts << s7 + " = ashr i64 " + s6 + ", 16\n  "
      parts << s8 + " = add i64 " + s5 + ", " + s7 + "\n  "
    if bits == 64
      parts << s9 + " = getelementptr i64, ptr " + s3 + ", i64 " + s8 + "\n  "
      parts << t + ".loaded = load i64, ptr " + s9 + ", align 8" + tbaa_elem_suffix() + "\n  "
      parts << t + ".res = " + llvm_op + " i64 " + t + ".loaded, " + val + "\n  "
      parts << "store i64 " + t + ".res, ptr " + s9 + ", align 8" + tbaa_elem_suffix() + "\n  "
      parts << t + " = add i64 " + t + ".res, 0"
    elsif bits == 32
      parts << s9 + " = getelementptr i32, ptr " + s3 + ", i64 " + s8 + "\n  "
      parts << t + ".loaded = load i32, ptr " + s9 + ", align 4" + tbaa_elem_suffix() + "\n  "
      parts << t + ".v32 = trunc i64 " + val + " to i32\n  "
      parts << t + ".res32 = " + llvm_op + " i32 " + t + ".loaded, " + t + ".v32\n  "
      parts << "store i32 " + t + ".res32, ptr " + s9 + ", align 4" + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i32 " + t + ".res32 to i64"
      else
        parts << t + " = zext i32 " + t + ".res32 to i64"
    elsif bits == 16
      parts << s9 + " = getelementptr i16, ptr " + s3 + ", i64 " + s8 + "\n  "
      parts << t + ".loaded = load i16, ptr " + s9 + ", align 2" + tbaa_elem_suffix() + "\n  "
      parts << t + ".v16 = trunc i64 " + val + " to i16\n  "
      parts << t + ".res16 = " + llvm_op + " i16 " + t + ".loaded, " + t + ".v16\n  "
      parts << "store i16 " + t + ".res16, ptr " + s9 + ", align 2" + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i16 " + t + ".res16 to i64"
      else
        parts << t + " = zext i16 " + t + ".res16 to i64"
    elsif bits == 8
      parts << s9 + " = getelementptr i8, ptr " + s3 + ", i64 " + s8 + "\n  "
      parts << t + ".loaded = load i8, ptr " + s9 + ", align 1" + tbaa_elem_suffix() + "\n  "
      parts << t + ".v8 = trunc i64 " + val + " to i8\n  "
      parts << t + ".res8 = " + llvm_op + " i8 " + t + ".loaded, " + t + ".v8\n  "
      parts << "store i8 " + t + ".res8, ptr " + s9 + ", align 1" + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i8 " + t + ".res8 to i64"
      else
        parts << t + " = zext i8 " + t + ".res8 to i64"
    else
      parts << s9 + " = getelementptr i64, ptr " + s3 + ", i64 " + s8 + "\n  "
      parts << t + ".loaded = load i64, ptr " + s9 + ", align 8" + tbaa_elem_suffix() + "\n  "
      parts << t + ".res = " + llvm_op + " i64 " + t + ".loaded, " + val + "\n  "
      parts << "store i64 " + t + ".res, ptr " + s9 + ", align 8" + tbaa_elem_suffix() + "\n  "
      parts << t + " = add i64 " + t + ".res, 0"
    parts.to_s()

  # BigArray inline read. Layout differs from WArray: the boxed value is a
  # generic object whose C struct carries a type byte at offset 0, i64
  # start/size/cap fields, and slots at offset 32. No bounds check here:
  # this is the unchecked `[]` path, and lowered each supplies in-range indices.
  when :big_array_get_inline
    t = wire_get(inst, :temp)
    s = wire_get(inst, :s)
    s0 = wire_sequence_get(s, 0)
    s1 = wire_sequence_get(s, 1)
    s2 = wire_sequence_get(s, 2)
    s3 = wire_sequence_get(s, 3)
    s4 = wire_sequence_get(s, 4)
    s5 = wire_sequence_get(s, 5)
    s6 = wire_sequence_get(s, 6)
    s7 = wire_sequence_get(s, 7)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    idx_raw = wire_get(inst, :idx_raw)
    bits = wire_get(inst, :bits)
    if bits == nil
      bits = 64
    signed = wire_get(inst, :signed)
    if signed == nil
      signed = true
    parts = StringBuffer(700)
    parts << s0 + " = and i64 " + arr + ", -16\n  "                # unmask
    parts << s1 + " = inttoptr i64 " + s0 + " to ptr\n  "       # WBigArray*
    parts << s2 + " = getelementptr i8, ptr " + s1 + ", i64 32\n  "
    parts << s3 + " = load ptr, ptr " + s2 + ", align 8" + tbaa_header_suffix() + "\n  "     # slots
    parts << s4 + " = getelementptr i8, ptr " + s1 + ", i64 8\n  "
    parts << s5 + " = load i64, ptr " + s4 + ", align 8" + tbaa_header_suffix() + "\n  "     # start
    if idx_raw == true
      parts << s6 + " = add i64 " + s5 + ", " + idx + "\n  "
    else
      parts << s6 + ".sl = shl i64 " + idx + ", 16\n  "
      parts << s6 + ".as = ashr i64 " + s6 + ".sl, 16\n  "
      parts << s6 + " = add i64 " + s5 + ", " + s6 + ".as\n  "
    if bits == 64
      parts << s7 + " = getelementptr i64, ptr " + s3 + ", i64 " + s6 + "\n  "
      parts << t + " = load i64, ptr " + s7 + ", align 8" + tbaa_elem_suffix()
    elsif bits == 32
      parts << s7 + " = getelementptr i32, ptr " + s3 + ", i64 " + s6 + "\n  "
      raw = t + ".raw"
      parts << raw + " = load i32, ptr " + s7 + ", align 4" + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i32 " + raw + " to i64"
      else
        parts << t + " = zext i32 " + raw + " to i64"
    elsif bits == 16
      parts << s7 + " = getelementptr i16, ptr " + s3 + ", i64 " + s6 + "\n  "
      raw = t + ".raw"
      parts << raw + " = load i16, ptr " + s7 + ", align 2" + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i16 " + raw + " to i64"
      else
        parts << t + " = zext i16 " + raw + " to i64"
    elsif bits == 8
      parts << s7 + " = getelementptr i8, ptr " + s3 + ", i64 " + s6 + "\n  "
      raw = t + ".raw"
      parts << raw + " = load i8, ptr " + s7 + ", align 1" + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i8 " + raw + " to i64"
      else
        parts << t + " = zext i8 " + raw + " to i64"
    elsif bits == 4
      byte_idx = t + ".byteidx"
      raw8 = t + ".raw8"
      raw64 = t + ".raw64"
      slot = t + ".slot"
      shift = t + ".shift"
      shifted = t + ".shifted"
      nibble = t + ".nibble"
      parts << byte_idx + " = lshr i64 " + s6 + ", 1\n  "
      parts << s7 + " = getelementptr i8, ptr " + s3 + ", i64 " + byte_idx + "\n  "
      parts << raw8 + " = load i8, ptr " + s7 + ", align 1" + tbaa_elem_suffix() + "\n  "
      parts << raw64 + " = zext i8 " + raw8 + " to i64\n  "
      parts << slot + " = and i64 " + s6 + ", 1\n  "
      parts << shift + " = shl i64 " + slot + ", 2\n  "
      parts << shifted + " = lshr i64 " + raw64 + ", " + shift + "\n  "
      parts << nibble + " = and i64 " + shifted + ", 15\n  "
      if signed == true
        signbits = t + ".signbits"
        parts << signbits + " = shl i64 " + nibble + ", 60\n  "
        parts << t + " = ashr i64 " + signbits + ", 60"
      else
        parts << t + " = add i64 " + nibble + ", 0"
    else
      parts << s7 + " = getelementptr i64, ptr " + s3 + ", i64 " + s6 + "\n  "
      parts << t + " = load i64, ptr " + s7 + ", align 8" + tbaa_elem_suffix()
    parts.to_s()

  # SmallArray inline read. Layout differs
  # from WArray — slots are INLINE at offset 2 (header is just ebits +
  # size), no separate ptr load, no `start` shift. The index is kept as
  # a full i64 for the GEP: a `trunc … to i8` here silently maps any
  # index 128..255 to a NEGATIVE offset (signed i8 wrap), addressing
  # BEFORE the struct. No bounds check — caller proved [0, size).
  when :small_array_get_inline
    t = wire_get(inst, :temp)
    s = wire_get(inst, :s)
    s0 = wire_sequence_get(s, 0)
    s1 = wire_sequence_get(s, 1)
    s2 = wire_sequence_get(s, 2)
    s3 = wire_sequence_get(s, 3)
    s4 = wire_sequence_get(s, 4)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    idx_raw = wire_get(inst, :idx_raw)
    bits = wire_get(inst, :bits)
    if bits == nil
      bits = 8
    signed = wire_get(inst, :signed)
    if signed == nil
      signed = false
    # Element alignment. The HEADERFUL WSmallArray has a 2-byte header, so
    # elements sit at offset 2 + k*w — unaligned → align 1. The HEADERLESS form
    # is a raw [payload x i8] alloca (align 16) with elements at offset k*w →
    # naturally aligned; telling LLVM the true alignment is what lets it
    # vectorize a reduction over the buffer (align 1 blocks it).
    ealign = "align 1"
    if wire_get(inst, :headerless) == true
      if bits == 64
        ealign = "align 8"
      elsif bits == 32
        ealign = "align 4"
      elsif bits == 16
        ealign = "align 2"
    parts = StringBuffer(400)
    if wire_get(inst, :headerless) == true
      # Headerless stack SmallArray: arr IS the raw [payload x i8] alloca ptr —
      # slots start at offset 0 (no 2-byte ebits/size header) and there is no
      # box to unmask. The offset-0 GEP just rebinds arr as the slots base so
      # the per-width element GEPs below are unchanged. Keeping arr a raw ptr
      # (never ptrtoint'd) is what lets LLVM SROA promote the alloca.
      parts << s2 + " = getelementptr i8, ptr " + arr + ", i64 0\n  "
    else
      parts << s0 + " = and i64 " + arr + ", -16\n  "                  # unmask
      parts << s1 + " = inttoptr i64 " + s0 + " to ptr\n  "          # struct ptr
      parts << s2 + " = getelementptr i8, ptr " + s1 + ", i64 2\n  " # &slots[0]
    if idx_raw == true
      parts << s3 + " = add i64 " + idx + ", 0\n  "                  # raw index (i64)
    else
      parts << s3 + ".sl = shl i64 " + idx + ", 16\n  "
      parts << s3 + " = ashr i64 " + s3 + ".sl, 16\n  "            # unbox → i64
    if bits == 64
      parts << s4 + " = getelementptr i64, ptr " + s2 + ", i64 " + s3 + "\n  "
      parts << t + " = load i64, ptr " + s4 + ", " + ealign + tbaa_elem_suffix()
    elsif bits == 32
      parts << s4 + " = getelementptr i32, ptr " + s2 + ", i64 " + s3 + "\n  "
      parts << t + ".raw = load i32, ptr " + s4 + ", " + ealign + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i32 " + t + ".raw to i64"
      else
        parts << t + " = zext i32 " + t + ".raw to i64"
    elsif bits == 16
      parts << s4 + " = getelementptr i16, ptr " + s2 + ", i64 " + s3 + "\n  "
      parts << t + ".raw = load i16, ptr " + s4 + ", " + ealign + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i16 " + t + ".raw to i64"
      else
        parts << t + " = zext i16 " + t + ".raw to i64"
    elsif bits == 8
      parts << s4 + " = getelementptr i8, ptr " + s2 + ", i64 " + s3 + "\n  "
      parts << t + ".raw = load i8, ptr " + s4 + ", align 1" + tbaa_elem_suffix() + "\n  "
      if signed == true
        parts << t + " = sext i8 " + t + ".raw to i64"
      else
        parts << t + " = zext i8 " + t + ".raw to i64"
    elsif bits == 4
      # 4-bit packed: byte_idx = idx >> 1; nibble at slot bit 0/1.
      byte_idx = t + ".byteidx"
      raw8 = t + ".raw8"
      raw64 = t + ".raw64"
      slot = t + ".slot"
      shift = t + ".shift"
      shifted = t + ".shifted"
      nibble = t + ".nibble"
      parts << byte_idx + " = lshr i64 " + s3 + ", 1\n  "
      parts << s4 + " = getelementptr i8, ptr " + s2 + ", i64 " + byte_idx + "\n  "
      parts << raw8 + " = load i8, ptr " + s4 + ", align 1" + tbaa_elem_suffix() + "\n  "
      parts << raw64 + " = zext i8 " + raw8 + " to i64\n  "
      parts << slot + " = and i64 " + s3 + ", 1\n  "
      parts << shift + " = shl i64 " + slot + ", 2\n  "
      parts << shifted + " = lshr i64 " + raw64 + ", " + shift + "\n  "
      parts << nibble + " = and i64 " + shifted + ", 15\n  "
      if signed == true
        signbits = t + ".signbits"
        parts << signbits + " = shl i64 " + nibble + ", 60\n  "
        parts << t + " = ashr i64 " + signbits + ", 60"
      else
        parts << t + " = add i64 " + nibble + ", 0"
    else
      parts << s4 + " = getelementptr i64, ptr " + s2 + ", i64 " + s3 + "\n  "
      parts << t + " = load i64, ptr " + s4 + ", " + ealign + tbaa_elem_suffix()
    parts.to_s()

  # SmallArray inline write — same layout shortcuts as get.
  # Index kept as a full i64 (see get: an i8 trunc would address before
  # the struct for indices 128..255). No size update (SmallArray is
  # fixed-size by construction).
  when :small_array_set_inline
    t = wire_get(inst, :temp)
    s = wire_get(inst, :s)
    s0 = wire_sequence_get(s, 0)
    s1 = wire_sequence_get(s, 1)
    s2 = wire_sequence_get(s, 2)
    s3 = wire_sequence_get(s, 3)
    s4 = wire_sequence_get(s, 4)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    idx_raw = wire_get(inst, :idx_raw)
    val = wire_get(inst, :value)
    bits = wire_get(inst, :bits)
    if bits == nil
      bits = 8
    # Element alignment — natural for the headerless (no-header) form, byte for
    # the headerful WSmallArray. See :small_array_get_inline for the rationale.
    ealign = "align 1"
    if wire_get(inst, :headerless) == true
      if bits == 64
        ealign = "align 8"
      elsif bits == 32
        ealign = "align 4"
      elsif bits == 16
        ealign = "align 2"
    parts = StringBuffer(400)
    if wire_get(inst, :headerless) == true
      # Headerless stack SmallArray write: arr is the raw alloca ptr, slots at
      # offset 0, no unmask. See :small_array_get_inline for the rationale.
      parts << s2 + " = getelementptr i8, ptr " + arr + ", i64 0\n  "
    else
      parts << s0 + " = and i64 " + arr + ", -16\n  "
      parts << s1 + " = inttoptr i64 " + s0 + " to ptr\n  "
      parts << s2 + " = getelementptr i8, ptr " + s1 + ", i64 2\n  "
    if idx_raw == true
      parts << s3 + " = add i64 " + idx + ", 0\n  "
    else
      parts << s3 + ".sl = shl i64 " + idx + ", 16\n  "
      parts << s3 + " = ashr i64 " + s3 + ".sl, 16\n  "
    if bits == 64
      parts << s4 + " = getelementptr i64, ptr " + s2 + ", i64 " + s3 + "\n  "
      parts << "store i64 " + val + ", ptr " + s4 + ", " + ealign + tbaa_elem_suffix() + "\n  "
    elsif bits == 32
      tr = t + ".tr"
      parts << s4 + " = getelementptr i32, ptr " + s2 + ", i64 " + s3 + "\n  "
      parts << tr + " = trunc i64 " + val + " to i32\n  "
      parts << "store i32 " + tr + ", ptr " + s4 + ", " + ealign + tbaa_elem_suffix() + "\n  "
    elsif bits == 16
      tr = t + ".tr"
      parts << s4 + " = getelementptr i16, ptr " + s2 + ", i64 " + s3 + "\n  "
      parts << tr + " = trunc i64 " + val + " to i16\n  "
      parts << "store i16 " + tr + ", ptr " + s4 + ", " + ealign + tbaa_elem_suffix() + "\n  "
    elsif bits == 8
      tr = t + ".tr"
      parts << s4 + " = getelementptr i8, ptr " + s2 + ", i64 " + s3 + "\n  "
      parts << tr + " = trunc i64 " + val + " to i8\n  "
      parts << "store i8 " + tr + ", ptr " + s4 + ", align 1" + tbaa_elem_suffix() + "\n  "
    elsif bits == 4
      # 4-bit pack: read-modify-write of the nibble at slot bit 0/1.
      byte_idx = t + ".byteidx"
      raw8 = t + ".raw8"
      raw64 = t + ".raw64"
      slot = t + ".slot"
      shift = t + ".shift"
      mask = t + ".mask"
      clear_mask = t + ".clear"
      cleared = t + ".cleared"
      nibble = t + ".nibble"
      shifted = t + ".shifted"
      merged = t + ".merged"
      tr = t + ".tr"
      parts << byte_idx + " = lshr i64 " + s3 + ", 1\n  "
      parts << s4 + " = getelementptr i8, ptr " + s2 + ", i64 " + byte_idx + "\n  "
      parts << raw8 + " = load i8, ptr " + s4 + ", align 1" + tbaa_elem_suffix() + "\n  "
      parts << raw64 + " = zext i8 " + raw8 + " to i64\n  "
      parts << slot + " = and i64 " + s3 + ", 1\n  "
      parts << shift + " = shl i64 " + slot + ", 2\n  "
      parts << mask + " = shl i64 15, " + shift + "\n  "
      parts << clear_mask + " = xor i64 " + mask + ", 255\n  "
      parts << cleared + " = and i64 " + raw64 + ", " + clear_mask + "\n  "
      parts << nibble + " = and i64 " + val + ", 15\n  "
      parts << shifted + " = shl i64 " + nibble + ", " + shift + "\n  "
      parts << merged + " = or i64 " + cleared + ", " + shifted + "\n  "
      parts << tr + " = trunc i64 " + merged + " to i8\n  "
      parts << "store i8 " + tr + ", ptr " + s4 + ", align 1" + tbaa_elem_suffix() + "\n  "
    else
      parts << s4 + " = getelementptr i64, ptr " + s2 + ", i8 " + s3 + "\n  "
      parts << "store i64 " + val + ", ptr " + s4 + ", " + ealign + tbaa_elem_suffix() + "\n  "
    # Define result so SSA refs to t are valid.
    parts << t + " = add i64 " + val + ", 0"
    parts.to_s()

  when :array_get_inline
    # Inline WArray read: unmask → slots (off 16) → start i32 (off 4) → unbox idx → GEP → load
    # Offsets locked by _Static_assert in runtime.h (items renamed to slots).
    t = wire_get(inst, :temp)
    s = wire_get(inst, :s)
    s0 = wire_sequence_get(s, 0)
    s1 = wire_sequence_get(s, 1)
    s2 = wire_sequence_get(s, 2)
    s3 = wire_sequence_get(s, 3)
    s4 = wire_sequence_get(s, 4)
    s5 = wire_sequence_get(s, 5)
    s6 = wire_sequence_get(s, 6)
    s7 = wire_sequence_get(s, 7)
    s8 = wire_sequence_get(s, 8)
    s9 = wire_sequence_get(s, 9)
    arr = wire_get(inst, :arr)
    idx = wire_get(inst, :idx)
    parts = StringBuffer(500)
    parts << s0 + " = and i64 " + arr + ", 140737488355312\n  "   # unmask (W_ARRAY_PTR_MASK)
    parts << s1 + " = inttoptr i64 " + s0 + " to ptr\n  "      # struct ptr
    parts << s2 + ".field = getelementptr i8, ptr " + s1 + ", i64 16\n  "  # &slots
    parts << s2 + " = load ptr, ptr " + s2 + ".field, align 8" + tbaa_header_suffix() + "\n  "   # slots ptr — TBAA=header lets LICM hoist when no realloc call is in the loop
    parts << s3 + " = getelementptr i8, ptr " + s1 + ", i64 4\n  "  # &start
    parts << s4 + " = load i32, ptr " + s3 + ", align 4" + tbaa_header_suffix() + "\n  "   # start (i32)
    parts << s5 + " = sext i32 " + s4 + " to i64\n  "          # start (i64)
    parts << s6 + " = shl i64 " + idx + ", 16\n  "                # unbox idx
    parts << s7 + " = ashr i64 " + s6 + ", 16\n  "              # sign-extend
    parts << s8 + " = add i64 " + s5 + ", " + s7 + "\n  "   # effective idx
    parts << s9 + " = getelementptr i64, ptr " + s2 + ", i64 " + s8 + "\n  "  # elem ptr
    parts << t + " = load i64, ptr " + s9 + ", align 8" + tbaa_elem_suffix()           # load element
    parts.to_s()
  when :builtin_class_init
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :name_str_id)]
    if swv != nil
      cn = llvm_safe_name(wire_get(inst, :class_name).gsub(":", "__"))
      parts = StringBuffer(128)
      parts << "%" + cn + ".cls = call i64 @w_class_new_wv(i64 " + llvm_wvalue_literal(swv) + ", i64 " + w_nil.to_s() + ")\n  "
      parts << "store i64 %" + cn + ".cls, ptr @class." + cn
      parts.to_s()
    else
      used_ptr_ids[wire_get(inst, :name_str_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :name_byte_len).to_s()
      cn = llvm_safe_name(wire_get(inst, :class_name).gsub(":", "__"))
      parts = StringBuffer(192)
      parts << "%" + cn + ".ptr = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :name_str_id).to_s() + ", i32 0, i32 0\n  "
      parts << "%" + cn + ".name = call i64 @w_string(ptr %" + cn + ".ptr)\n  "
      parts << "%" + cn + ".cls = call i64 @w_class_new_wv(i64 %" + cn + ".name, i64 " + w_nil.to_s() + ")\n  "
      parts << "store i64 %" + cn + ".cls, ptr @class." + cn
      parts.to_s()

  # Instance variables
  when :ivar_get
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :str_id)]
    if swv != nil
      wire_get(inst, :temp) + " = call i64 @w_ivar_get_wv(i64 " + wire_get(inst, :self_reg) + ", i64 " + llvm_wvalue_literal(swv) + ")"
    else
      used_ptr_ids[wire_get(inst, :str_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :byte_len).to_s()
      parts = StringBuffer(160)
      parts << wire_get(inst, :temp_ptr) + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :str_id).to_s() + ", i32 0, i32 0\n  "
      parts << wire_get(inst, :temp_ptr) + ".wv = call i64 @w_string(ptr " + wire_get(inst, :temp_ptr) + ")\n  "
      parts << wire_get(inst, :temp) + " = call i64 @w_ivar_get_wv(i64 " + wire_get(inst, :self_reg) + ", i64 " + wire_get(inst, :temp_ptr) + ".wv)"
      parts.to_s()
  when :ivar_set
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :str_id)]
    if swv != nil
      wire_get(inst, :temp) + " = call i64 @w_ivar_set_wv(i64 " + wire_get(inst, :self_reg) + ", i64 " + llvm_wvalue_literal(swv) + ", i64 " + wire_get(inst, :value) + ")"
    else
      used_ptr_ids[wire_get(inst, :str_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :byte_len).to_s()
      parts = StringBuffer(160)
      parts << wire_get(inst, :temp_ptr) + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :str_id).to_s() + ", i32 0, i32 0\n  "
      parts << wire_get(inst, :temp_ptr) + ".wv = call i64 @w_string(ptr " + wire_get(inst, :temp_ptr) + ")\n  "
      parts << wire_get(inst, :temp) + " = call i64 @w_ivar_set_wv(i64 " + wire_get(inst, :self_reg) + ", i64 " + wire_get(inst, :temp_ptr) + ".wv, i64 " + wire_get(inst, :value) + ")"
      parts.to_s()
  when :ivar_get_idx
    byte_offset = (8 + wire_get(inst, :offset) * 8).to_s
    t = wire_get(inst, :temp)
    sr = wire_get(inst, :self_reg)
    parts = StringBuffer(160)
    parts << t + ".raw = and i64 " + sr + ", -16\n  "
    parts << t + ".ptr = inttoptr i64 " + t + ".raw to ptr\n  "
    parts << t + ".gep = getelementptr i8, ptr " + t + ".ptr, i64 " + byte_offset + "\n  "
    parts << t + " = load i64, ptr " + t + ".gep, align 8" + tbaa_ivar_suffix()
    parts.to_s()
  when :slab_node_get_idx
    # PR #2: read one slab slot from an AST node.
    # Unused — the active slab field path is the :call_direct_i64
    # branch above that special-cases wire_get(inst, :name) == "w_node_field_load".
    wire_get(inst, :temp) + " = call i64 @w_node_field_load(i64 " + wire_get(inst, :node) + ", i64 " + wire_get(inst, :offset).to_s() + ")"
  when :slab_node_set_idx
    # PR #2: write one slab slot. Unused; see :slab_node_get_idx
    # note above.
    t = wire_get(inst, :temp)
    parts = StringBuffer(192)
    parts << "call void @w_node_field_store(i64 " + wire_get(inst, :node) + ", i64 " + wire_get(inst, :offset).to_s() + ", i64 " + wire_get(inst, :value) + ")\n  "
    parts << t + " = add i64 " + wire_get(inst, :value) + ", 0"
    parts.to_s()
  when :ivar_set_idx
    byte_offset = (8 + wire_get(inst, :offset) * 8).to_s()
    t = wire_get(inst, :temp)
    sr = wire_get(inst, :self_reg)
    parts = StringBuffer(192)
    parts << t + ".raw = and i64 " + sr + ", -16\n  "
    parts << t + ".ptr = inttoptr i64 " + t + ".raw to ptr\n  "
    parts << t + ".gep = getelementptr i8, ptr " + t + ".ptr, i64 " + byte_offset + "\n  "
    parts << "store i64 " + wire_get(inst, :value) + ", ptr " + t + ".gep, align 8" + tbaa_ivar_suffix() + "\n  "
    parts << t + " = add i64 " + wire_get(inst, :value) + ", 0"
    parts.to_s()
  when :class_add_ivar
    swv = nil
    if string_wvs != nil
      swv = string_wvs[wire_get(inst, :ivar_str_id)]
    if swv != nil
      "call i32 @w_class_add_ivar_wv(i64 " + wire_get(inst, :class_temp) + ", i64 " + llvm_wvalue_literal(swv) + ")"
    else
      used_ptr_ids[wire_get(inst, :ivar_str_id)] = true
      lbr = "\["
      rbr = "]"
      bl = wire_get(inst, :ivar_byte_len).to_s()
      ivar_ptr = wire_get(inst, :class_temp) + ".ivar_name"
      parts = StringBuffer(160)
      parts << ivar_ptr + " = getelementptr inbounds " + lbr + bl + " x i8" + rbr + ", ptr @.str." + wire_get(inst, :ivar_str_id).to_s() + ", i32 0, i32 0\n  "
      parts << ivar_ptr + ".wv = call i64 @w_string(ptr " + ivar_ptr + ")\n  "
      parts << "call i32 @w_class_add_ivar_wv(i64 " + wire_get(inst, :class_temp) + ", i64 " + ivar_ptr + ".wv)"
      parts.to_s()

  # Closures
  when :null_ptr
    wire_get(inst, :temp) + " = inttoptr i64 0 to ptr"
  when :ptr_to_i64
    wire_get(inst, :temp) + " = ptrtoint ptr " + wire_get(inst, :value) + " to i64"
  when :i64_to_ptr
    wire_get(inst, :temp) + " = inttoptr i64 " + wire_get(inst, :value) + " to ptr"
  when :closure_new
    wire_get(inst, :temp) + " = call i64 @w_closure_new_a(ptr @" + wire_get(inst, :fn_name) + ", ptr " + wire_get(inst, :captures_ptr) + ", i32 " + wire_get(inst, :capture_count).to_s() + ", i32 " + (wire_get(inst, :block_arity) == nil ? 0 : wire_get(inst, :block_arity)).to_s() + ")"
  when :alloca_array
    lbr = "\["
    rbr = "]"
    wire_get(inst, :ptr) + " = alloca " + lbr + wire_get(inst, :count).to_s() + " x i64" + rbr + ", align 8"
  when :gep_array
    lbr = "\["
    rbr = "]"
    wire_get(inst, :temp) + " = getelementptr inbounds " + lbr + wire_get(inst, :count).to_s() + " x i64" + rbr + ", ptr " + wire_get(inst, :base) + ", i32 0, i32 " + wire_get(inst, :index).to_s()
  when :store_ptr
    "store i64 " + wire_get(inst, :value) + ", ptr " + wire_get(inst, :dest) + ", align 8"
  when :load_ptr
    wire_get(inst, :temp) + " = load i64, ptr " + wire_get(inst, :ptr) + ", align 8"

  # SSA phi with N inputs (from mem2reg)
  when :phi_ssa
    lbr = "\["
    rbr = "]"
    incoming = wire_get(inst, :incoming)
    parts = StringBuffer(wire_sequence_size(incoming) * 32 + 24)
    parts << wire_get(inst, :temp) + " = phi i64 "
    ii = 0
    while ii < wire_sequence_size(incoming)
      if ii > 0
        parts << ", "
      label = redirect_phi_label(wire_sequence_get(incoming, ii + 1), phi_label_redirects)
      parts << lbr + " " + wire_sequence_get(incoming, ii) + ", %" + label + " " + rbr
      ii += 2
    parts.to_s()

  # Free a non-escaped heap value at scope exit
  when :free_value
    "call void @w_value_free(i64 " + wire_get(inst, :value) + ")"

  # Scope markers — pseudo-instructions for ownership analysis, no codegen
  when :scope_push, :scope_pop
    "; scope " + op.to_s()

  else
    "; UNKNOWN WIRE OP: " + op.to_s()

# -- Helpers --

-> render_call_args(args, arg_types = nil)
  parts = []
  i = 0
  while i < wire_sequence_size(args)
    arg_type = "i64"
    if arg_types != nil && wire_sequence_get(arg_types, i) != nil
      arg_type = wire_sequence_get(arg_types, i)
    parts.push(arg_type + " " + wire_sequence_get(args, i))
    i += 1
  parts.join(", ")

-> render_method_call_args_setup(inst)
  args = wire_get(inst, :args)
  if wire_sequence_size(args) == 0
    return wire_get(inst, :temp_args_val) + " = call i64 @w_array_new_empty()\n  "
  out = StringBuffer(wire_sequence_size(args) * 48 + 32)
  out << wire_get(inst, :temp_args_val) + " = call i64 @w_array_new_empty()\n  "
  i = 0
  while i < wire_sequence_size(args)
    out << "call i64 @w_array_push(i64 " + wire_get(inst, :temp_args_val) + ", i64 " + wire_sequence_get(args, i) + ")\n  "
    i += 1
  out.to_s()
