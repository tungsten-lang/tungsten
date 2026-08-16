# Lowering / views — `- data` memory-layout blocks: field sizes and
# offsets, view-field reads and writes, and view class resolution.
#
# This file deliberately has no `use` directives — see pass_registry.w
# for the rationale (path resolution from compiler/lib/lowering/).

-> type_size(t)
  if t.starts_with?("*")
    return 8

  # Fixed array: u8[7] → 1 * 7 = 7
  if t.index("\[") != nil && t.index("\]") != nil
    bracket = t.index("\[")
    base = t.slice(0, bracket)
    count_str = t.slice(bracket + 1, t.index("\]") - bracket - 1)

    if count_str != ""
      return type_size(base) * count_str.to_i()
    return 0
  case t
  when "u8", "i8"
    1
  when "u16", "i16"
    2
  when "u32", "i32"
    4
  when "u64", "i64", "*"
    8
  when "i128", "u128"
    16
  else
    8

-> pointer_array_field?(t)
  t.starts_with?("*") && t.ends_with?("\[]")

-> pointer_array_element_type(t)
  if pointer_array_field?(t)
    return t.slice(1, t.size() - 3)
  "w64"

# A fixed inline array is storage embedded directly in the backing struct,
# e.g. WNetAddr.bytes (`u8[16]`). It is distinct from `* u8[] slots`, whose
# field contains a separately allocated pointer. v0 only indexes inline u8
# fields; widening this predicate later keeps the load-size decision explicit.
-> inline_u8_array_field?(t)
  !t.starts_with?("*") && t.starts_with?("u8\[") && t.ends_with?("\]") && t != "u8\[]"

# The widened form (bignum limb access): any non-pointer `T[N]` or flexible
# `T[]` tail whose element is a fixed machine scalar. Fixed `u8[N]` keeps its
# dedicated byte op through inline_u8_array_field?; this predicate serves the
# strided general load/store path (e.g. BigInt's `u64[] limbs`). Element
# access is bounds-independent raw memory, exactly like the byte form — the
# containing method owns the semantic bounds check.
-> inline_array_element_type(t)
  if t.starts_with?("*")
    return nil
  bracket = t.index("\[")
  if bracket == nil || !t.ends_with?("\]")
    return nil
  base = t.slice(0, bracket)
  if base in ("u8" "i8" "u16" "i16" "u32" "i32" "u64" "i64")
    return base
  nil

-> inline_array_field?(t)
  inline_array_element_type(t) != nil

-> view_field_info(ctx, field_name)
  class_name = ctx[:class_name]
  layouts = ctx[:mod][:view_layouts]
  if layouts == nil || layouts[class_name] == nil
    return nil
  layouts[class_name][field_name]

-> collect_view_fields(body)
  if body == nil
    return nil
  fields = nil
  i = 0
  while i < body.size()
    node = body[i]
    if ast_kind(node) == :view_decl && ast_get(node, :kind) == "struct"
      layout = node.count
      if layout != nil && layout[:fields] != nil
        fields = {}
        offset = 0
        j = 0
        while j < layout[:fields].size()
          f = layout[:fields][j]
          size = type_size(f[:type])
          fields[f[:name]] = {offset: offset, size: size, type: f[:type]}
          offset += size
          j += 1
    i += 1
  fields

-> lower_view_field(ctx, node)
  wfn = ctx[:func]
  field_name = node.field

  # Look up field offset and type from the class layout
  class_name = ctx[:class_name]
  info = view_field_info(ctx, field_name)
  if info == nil
    layouts = ctx[:mod][:view_layouts]
    if layouts == nil || layouts[class_name] == nil
      raise compile_error_for_node(:E_LOWER_VIEW_NO_LAYOUT, "No view layout for class " + class_name, ctx[:source_path], node)
    raise compile_error_for_node(:E_LOWER_VIEW_UNKNOWN_FIELD, "Unknown field '" + field_name + "' in " + class_name + " layout", ctx[:source_path], node)

  # Get self pointer (masked to remove subtag)
  self_tv = lower_var(ctx, Tungsten:AST:Var.new("__self"))
  self_reg = ensure_i64_value(wfn, self_tv)

  # Classes that share the W_SUBTAG_GENERIC subtag
  # (BigArray — keyed at 0x80|W_TYPE_*) embed a `type` byte at offset 0
  # of their heap struct as a secondary dispatch discriminator. The
  # .w data block describes the user-visible layout starting AFTER
  # that byte; add the implicit byte here so the gep lands on the
  # right field of the C struct. (SmallArray was promoted to
  # its own subtag and no longer carries this byte; its .w layout
  # starts directly at offset 0.)
  effective_offset = info[:offset]
  if class_uses_implicit_type_byte?(class_name)
    effective_offset = info[:offset] + 1

  temp = next_temp(wfn)
  emit_wire_view_load_field(wfn, info[:type], effective_offset, self_reg, info[:size], temp)
  typed_value(view_field_value_type(info[:type]), temp)

# `$field = value` inside a class method — write a scalar field in that
# class's native `- data` layout. The store returns the value after conversion
# to the declared field width, and keeps it raw until a real WValue boundary.
# This makes mutation-only native methods (for example a signed i32 header
# update) compile to a mask/gep/store with no runtime bridge or allocation.
-> lower_view_field_set(ctx, field_name, val_tv)
  wfn = ctx[:func]
  info = view_field_info(ctx, field_name)
  field_type = info[:type]

  # Flexible and fixed inline arrays are aggregate storage, not scalar
  # assignable fields. Their element write paths remain the only supported
  # mutation boundary.
  if field_type.index("\[") != nil && !field_type.starts_with?("*")
    raise "Cannot assign aggregate native-data field '$" + field_name + "' of type " + field_type
  # The view emitter currently carries scalar values in at most one machine
  # word. Reject i128/u128 explicitly instead of silently storing their low
  # 64 bits through the generic WValue branch.
  if type_size(field_type) > 8
    raise "Cannot assign native-data field '$" + field_name + "' wider than 64 bits"

  self_tv = lower_var(ctx, Tungsten:AST:Var.new("__self"))
  self_reg = ensure_i64_value(wfn, self_tv)

  effective_offset = info[:offset]
  if class_uses_implicit_type_byte?(ctx[:class_name])
    effective_offset = info[:offset] + 1

  result_type = view_field_value_type(field_type)
  value_reg = nil
  if field_type == "f32"
    value_reg = ensure_raw_f32(wfn, val_tv)
  elsif field_type == "f64"
    value_reg = ensure_raw_f64(wfn, val_tv)
  elsif field_type.starts_with?("*")
    value_reg = ensure_raw_i64(wfn, val_tv)
  elsif field_type == "u64"
    value_reg = ensure_raw_u64(wfn, val_tv)
  elsif field_type in ("i8" "i16" "i32" "i64" "u8" "u16" "u32" "bool")
    value_reg = ensure_raw_i64(wfn, val_tv)
  else
    # w64 and named scalar object slots contain an already-boxed WValue.
    value_reg = ensure_i64_value(wfn, val_tv)

  temp = next_temp(wfn)
  emit_wire_view_store_field(wfn, field_type, effective_offset, self_reg, info[:size], temp, value_reg)
  typed_value(result_type, temp)

# `receiver$field` — the explicit-receiver twin of lower_view_field. The
# receiver expression's inferred type names a class with a `- data` view
# layout; we read the field at its layout offset off the (masked) receiver
# pointer with the same :view_load_field op. Unlike lower_view_field, the
# class comes from the receiver's type rather than ctx[:class_name], so this
# works at top level and for any named variable, not just inside a method.
-> lower_view_field_var(ctx, node)
  wfn = ctx[:func]
  field_name = node.field
  recv = node.receiver

  # `recv$value` is the explicit-receiver twin of bare `$value`: the raw
  # NaN-boxed word of the receiver, typed :raw_i64. Needs no layout (it is
  # the WValue itself, not memory), so it resolves before the layout lookup
  # and works for any receiver — same emitted code as wvalue_bits(recv).
  if field_name == "value"
    return typed_value(:raw_i64, ensure_i64_value(wfn, lower_expression(ctx, recv)))

  recv_type = infer_type(recv, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
  class_name = view_layout_class_for_type(ctx[:mod], recv_type)
  if class_name == nil
    raise compile_error_for_node(:E_LOWER_VIEW_NO_LAYOUT, "No view-decl layout for receiver of '$" + field_name + "' (add a `## ClassName` type hint so the layout is known)", ctx[:source_path], node)
  info = ctx[:mod][:view_layouts][class_name][field_name]
  if info == nil
    raise compile_error_for_node(:E_LOWER_VIEW_UNKNOWN_FIELD, "Unknown field '" + field_name + "' in " + class_name + " layout", ctx[:source_path], node)

  recv_tv = lower_expression(ctx, recv)
  recv_reg = ensure_i64_value(wfn, recv_tv)

  # Same implicit-type-byte adjustment as lower_view_field (BigArray et al).
  effective_offset = info[:offset]
  if class_uses_implicit_type_byte?(class_name)
    effective_offset = info[:offset] + 1

  temp = next_temp(wfn)
  emit_wire_view_load_field(wfn, info[:type], effective_offset, recv_reg, info[:size], temp)
  typed_value(view_field_value_type(info[:type]), temp)

# `receiver$field = value` — explicit-receiver twin of
# lower_view_field_set. The receiver's inferred type selects the layout; the
# emitted store is otherwise identical to an implicit-self native-data store.
-> lower_view_field_var_set(ctx, node, val_tv)
  wfn = ctx[:func]
  field_name = node.field
  recv = node.receiver
  recv_type = infer_type(recv, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
  class_name = view_layout_class_for_type(ctx[:mod], recv_type)
  if class_name == nil
    raise compile_error_for_node(:E_LOWER_VIEW_NO_LAYOUT, "No view-decl layout for receiver of '$" + field_name + "' (add a `## ClassName` type hint so the layout is known)", ctx[:source_path], node)
  info = ctx[:mod][:view_layouts][class_name][field_name]
  if info == nil
    raise compile_error_for_node(:E_LOWER_VIEW_UNKNOWN_FIELD, "Unknown field '" + field_name + "' in " + class_name + " layout", ctx[:source_path], node)
  field_type = info[:type]

  if field_type.index("\[") != nil && !field_type.starts_with?("*")
    raise "Cannot assign aggregate native-data field '$" + field_name + "' of type " + field_type
  if type_size(field_type) > 8
    raise "Cannot assign native-data field '$" + field_name + "' wider than 64 bits"

  recv_tv = lower_expression(ctx, recv)
  recv_reg = ensure_i64_value(wfn, recv_tv)

  effective_offset = info[:offset]
  if class_uses_implicit_type_byte?(class_name)
    effective_offset = info[:offset] + 1

  result_type = view_field_value_type(field_type)
  value_reg = nil
  if field_type == "f32"
    value_reg = ensure_raw_f32(wfn, val_tv)
  elsif field_type == "f64"
    value_reg = ensure_raw_f64(wfn, val_tv)
  elsif field_type.starts_with?("*")
    value_reg = ensure_raw_i64(wfn, val_tv)
  elsif field_type == "u64"
    value_reg = ensure_raw_u64(wfn, val_tv)
  elsif field_type in ("i8" "i16" "i32" "i64" "u8" "u16" "u32" "bool")
    value_reg = ensure_raw_i64(wfn, val_tv)
  else
    value_reg = ensure_i64_value(wfn, val_tv)

  temp = next_temp(wfn)
  emit_wire_view_store_field(wfn, field_type, effective_offset, recv_reg, info[:size], temp, value_reg)
  typed_value(result_type, temp)

# Preserve scalar view fields in their machine representation until a real
# WValue boundary. Previously u8/u16/u32 fields were boxed by the emitter and
# then commonly unboxed again for comparisons, loop bounds, and indexes. The
# declared field type also lets signed fields use sign extension and u64 use
# the unsigned boxing bridge when a boxed value is eventually required.
-> view_field_value_type(field_type)
  if field_type.starts_with?("*")
    return :raw_i64
  if field_type in ("i1" "i4" "i8" "i16" "i32" "u1" "u4" "u8" "u16" "u32" "bool")
    return :raw_int
  case field_type
    when "i64"
      :raw_i64
    when "u64"
      :raw_u64
    when "f32"
      :raw_f32
    when "f64"
      :raw_f64
    else
      # w64 and named object fields already contain a WValue.
      :i64

# Resolve the class name (a view_layouts key) for an inferred receiver type.
# User classes and explicit `## ClassName` hints carry the class name as the
# type symbol directly (`:Widget` -> "Widget"); builtin lowering type symbols
# (`:array`) are mapped through a small alias table to their layout class.
-> view_layout_class_for_type(mod, type_sym)
  if type_sym == nil
    return nil
  layouts = mod[:view_layouts]
  if layouts == nil
    return nil
  direct = type_sym.to_s()
  if layouts[direct] != nil
    return direct
  alias_name = builtin_type_view_class(type_sym)
  if alias_name != nil && layouts[alias_name] != nil
    return alias_name
  nil

# Builtin lowering type symbol -> its `- data` view-layout class name.
-> builtin_type_view_class(type_sym)
  case type_sym
    :array         => "Array"
    :string_buffer => "StringBuffer"
    :hash          => "Hash"
    => nil

# Returns true for classes that live in the W_SUBTAG_GENERIC bucket and
# therefore have an implicit type-byte at offset 0 of their heap struct
# that the user-visible .w data block omits. Currently BigArray and Mmap
# (keys 0x92 and 0x91). Subtag-promoted classes (SmallArray, Array, Atomic,
# StrBuf, …) keyed below 0x80 return false.
-> class_uses_implicit_type_byte?(class_name)
  key = type_dispatch_key(class_name)
  if key == nil
    return false
  key >= 128

-> lower_view_access(ctx, node)
  wfn = ctx[:func]
  view_name = node.view_name

  # Get self pointer (masked to remove subtag)
  self_tv = lower_var(ctx, Tungsten:AST:Var.new("__self"))
  self_reg = ensure_i64_value(wfn, self_tv)

  # Evaluate index
  idx_tv = lower_expression(ctx, node.index)
  idx_reg = ensure_i64_value(wfn, idx_tv)
  idx_raw = ensure_raw_int(wfn, idx_tv)

  temp = next_temp(wfn)
  if view_name == "bytes"
    emit_wire_view_load_byte(wfn, idx_raw, self_reg, temp)
  elsif view_name == "bits"
    emit_wire_view_load_bit(wfn, idx_raw, self_reg, temp)
  else
    emit_wire_view_load_byte(wfn, idx_raw, self_reg, temp)
  typed_value(:i64, temp)

-> lower_view_base(ctx)
  wfn = ctx[:func]
  self_tv = lower_var(ctx, Tungsten:AST:Var.new("__self"))
  self_reg = ensure_i64_value(wfn, self_tv)
  temp = next_temp(wfn)
  emit_wire_view_base_ptr(wfn, temp, self_reg)
  typed_value(:i64, temp)

-> lower_view_value(ctx)
  lower_var(ctx, Tungsten:AST:Var.new("__self"))
