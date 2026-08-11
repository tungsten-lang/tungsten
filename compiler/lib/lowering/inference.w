# Lowering / inference — expression type inference (infer_type) and
# function return-type inference over the AST, consulted by nearly
# every lowering worker.
#
# This file deliberately has no `use` directives — see pass_registry.w
# for the rationale (path resolution from compiler/lib/lowering/).

-> infer_type(node, var_types, fn_return_types, infer_maps = nil)
  if infer_maps == nil
    infer_maps = lowering_infer_maps
  if node == nil
    return nil
  t = ast_kind(node)
  if t == :type_ascription
    hint = ast_get(node, :type_hint)
    if hint == "w64"
      return :i64
    if hint in ("big" "bigint" "bignum")
      return :bigint
    array_etype = array_hint_element_type(hint)
    if array_etype != nil
      return typed_array_etype_to_sym(array_etype)
    return normalize_type_symbol(hint)
  case t
  when :int
    if node.format == :hex
      v = node.value
      if v >= 0 && v <= 255
        return :u8
      if v >= 0 && v <= 65535
        return :u16
      if v >= 0 && v <= 4294967295
        return :u32
      if v >= 0
        return :u64
    # A literal beyond i64 must NOT infer a machine type — the machine
    # arms emit it as a raw i64 immediate and LLVM wraps it (e.g.
    # `(0 - <77-digit literal>) * 3` silently returned an i64-wrapped
    # result). :int routes it through the boxed/guarded paths, whose
    # runtime fallbacks are BigInt-correct. Magnitude was classified at
    # PARSE time from the token text (:dec_big, int_literal_format and
    # its stage-0 twin): reading the packed node's sparse raw/value
    # fields HERE materializes it and perturbs slab-arena state, which
    # shifts block numbering between stage 1 and stage 2 — an .ll
    # identity break. `format` is an eager field; its read is
    # side-effect-free (the :hex arm's precedent).
    if node.format == :dec_big
      return :int
    return :i64
  when :wvalue
    return nil
  when :float
    return :float
  when :decimal
    return :decimal
  when :bool
    return :bool
  when :typed_array_new, :typed_array
    if node.element_type == "bool" || node.element_type == "u1" || node.element_type == "i1"
      return :bool_array
    etype = node.element_type
    # Non-escaping `i32[N]` (N<=255) promoted to a stack WSmallArray by
    # mark_stackable_typed_arrays: its element access must dispatch to the
    # small_array inline ops, so surface the small_array_* type.
    if typed_array_new_stack_promoted?(node)
      return small_array_etype_to_sym(etype)
    if etype in ("u4" "i4")
      return typed_array_etype_to_sym(etype)
    if etype in ("u8" "i8" "u16" "i16" "u32" "i32" "u64" "i64" "f64" "f32" "f16" "bf16" "w64")
      return typed_array_etype_to_sym(etype)
    return :array
  when :array
    return :array
  when :hash_literal
    return :hash
  when :string, :string_interp
    return :string
  when :regex
    return :regex
  when :date, :datetime
    return :date
  when :time
    return :time
  when :month
    return :month
  when :ip4, :cidr4
    return :ip4
  when :ip6, :cidr6
    return :ip6
  when :rational
    return :rational
  when :char
    return :char
  when :codepoint
    return :codepoint
  when :duration
    return :duration
  when :currency
    return :currency
  when :quantity
    return :quantity
  when :uuid
    return :uuid
  when :symbol
    return :symbol
  when :var
    n = node.name
    return var_types[n]
  when :gvar
    n = node.name
    # `$value` is parsed as a GVar, then lower_gvar exposes the receiver's raw
    # 64-bit content. Keep inference in agreement so `($value >> N) & M`
    # lowers to native shifts/masks rather than polymorphic w_bit_* calls.
    if n == "$value"
      return :raw_i64
    return var_types[n]
  when :view_field_var
    # `recv$value` is the explicit-receiver twin of bare `$value` and must
    # infer :raw_i64 in EVERY expression context, exactly like the gvar
    # case above. Without this, `(other$value >> 47) & 1` in an
    # if-expression typed nil and the shift lowered through the BOXED
    # w_bit path — which, on a bigint receiver, is a LIMB shift: the
    # garbage magnitude tripped the over-band bail to w_add, whose shape
    # gate re-admitted the pair, and the recursion presented as a silent
    # stack death. (Real declared fields fall through to nil here — their
    # lowering resolves the layout itself.)
    if node.field == "value"
      return :raw_i64
    return nil
  when :self_ref
    return var_types["__self"]
  when :call
    if node.receiver == nil
      if node.name == "StringBuffer"
        return :string_buffer
      if node.name == "wvalue_bits"
        return :raw_i64
      if node.name == "wvalue_from_bits"
        return :value
      if node.name == "ccall_nobox"
        # Whitelisted slab/sparse helpers return an already-boxed WValue
        # of unknown kind — type them :value so a chained call on the
        # result (`ast_get(...).each`) dispatches generically instead of
        # taking the machine-int receiver path, which reads the boxed
        # WValue as a raw handle and corrupts it. See
        # ccall_nobox_returns_wvalue? in lowering/types.w.
        fa = node.args
        if fa != nil && fa.size() >= 1 && is_ast_node?(fa[0]) && ast_kind(fa[0]) == :string && ccall_nobox_returns_wvalue?(fa[0].value)
          return :value
        return :i64
      if node.name in ("raw_load_u8" "raw_load_u32" "raw_load_u64" "raw_store_u8")
        return :i64
      if node.name == "ccall_rawargs"
        return :value
      args = node.args
      if args != nil
        arg_types = inferred_arg_types(args, var_types, fn_return_types, infer_maps)
        typed_key = typed_call_signature_key(node.name, arg_types)
        typed_rt = fn_return_types[typed_key]
        if typed_rt != nil
          return normalize_type_symbol(typed_rt)
      return fn_return_types[node.name]

    if ast_kind(node.receiver) in (:var :class_ref)
      static_rt = fn_return_types[node.receiver.name + "." + node.name]
      if static_rt != nil
        return normalize_type_symbol(static_rt)
    if node.receiver != nil && node.receiver.name == "Array" && node.name == "new" && node.args != nil && node.args.size() <= 2
      return :array
    # SmallArray.new(:ebits, size) → :small_array_<ebits>. Lets downstream
    # call sites (s[i], s[i] = v, s.size, ...) take the SmallArray inline-op
    # fast path when the receiver was assigned from this constructor.
    if node.receiver != nil && node.receiver.name == "SmallArray" && node.name == "new" && node.args != nil && node.args.size() == 2
      ebits = ebits_const_value(node.args[0])
      if ebits != nil
        if ebits == 4
          return :small_array_u4
        if ebits == 8
          return :small_array_u8
        if ebits == 16
          return :small_array_u16
        if ebits == 32
          return :small_array_u32
        if ebits == 64
          return :small_array_u64
        if ebits == -4
          return :small_array_i4
        if ebits == 108
          return :small_array_i8
        if ebits == 116
          return :small_array_i16
        if ebits == 33
          return :small_array_i32
        if ebits == 66
          return :small_array_i64
        if ebits == -32
          return :small_array_f32
        if ebits == -64
          return :small_array_f64
        if ebits == -116
          return :small_array_bf16
        if ebits == -16
          return :small_array_f16
        if ebits == 65
          return :small_array
    if node.name == "lchs"
      return infer_lchs_return_type(node.args)
    if node.name == "to_i" && node.args != nil && node.args.size() == 0
      return :i64
    # to_s always yields text (both the bare and radix forms). Every builtin
    # returns a string and user to_s methods that don't would already break
    # interpolation, so downstream sites — `.size()`, `s + x.to_s()` — may
    # take the typed-string direct routes instead of IC dispatch.
    if node.name == "to_s" && node.args != nil && node.args.size() <= 1
      return :string
    # Math.* compiler intrinsics always yield a float: the w_math_*
    # intercepts (lowering/method_call.w) wrap their result in w_float
    # unconditionally. Without this, an expression like `Math.sin(x) + c`
    # infers nil and the `+` falls back to a boxed w_add call instead of a
    # raw fadd — the shared-inference twin of the raw libm fast path. This
    # The shared registry includes intrinsics with source fallbacks too; those
    # fallbacks remain available to other frontends, while compiled calls use
    # the native path consistently.
    if node.receiver != nil && ast_kind(node.receiver) in (:var :class_ref :call) && node.receiver.name == "Math"
      if math_intrinsic_runtime_name(node.name, node.args.size()) != nil
        return :float
    recv_t = infer_type(node.receiver, var_types, fn_return_types, infer_maps)
    # bool_array is its own legacy type and not in is_array_type?, so name it
     # explicitly: arr[i] returns :bool, lining up with `id_bool(x) (bool) bool`
     # typed-overload dispatch.
    if recv_t == :bool_array && node.name in ("\[]" "[]")
      return :bool
    if is_array_type?(recv_t) && node.name in ("\[]" "[]")
      elem_t = recv_t
      if is_big_array_type?(recv_t) || is_small_array_type?(recv_t)
        elem_t = small_array_to_typed_array_type(recv_t)
      if elem_t == :typed_array_w64 || elem_t == nil || recv_t == :array
        return nil
      value_t = typed_array_element_value_type(elem_t)
      if value_t != nil
        return value_t
      return :int
    if is_array_type?(recv_t) && node.name == "size"
      return :i64
    if is_typed_array_type?(recv_t) && node.name in ("min" "max" "sum")
      if recv_t in (:typed_array_f64 :typed_array_f32 :typed_array_bf16 :typed_array_f16)
        return :float
      return :int
    if is_typed_array_type?(recv_t) && node.name in ("fastsum" "sumsq" "dot")
      if recv_t in (:typed_array_f64 :typed_array_f32 :typed_array_bf16 :typed_array_f16)
        return :float
      if recv_t in (:typed_array_i8 :typed_array_u8) && node.name == "dot"
        return :int
    if is_typed_array_type?(recv_t) && node.name in ("cross" "scale" "scale!")
      if recv_t in (:typed_array_f64 :typed_array_f32 :typed_array_bf16 :typed_array_f16)
        return recv_t
    if is_typed_array_type?(recv_t) && node.name in ("matvec_i8" "matmul_i8")
      if recv_t in (:typed_array_i8 :typed_array_u8)
        return :typed_array_i32
    if is_typed_array_type?(recv_t) && node.name in ("cos" "sin" "sqrt" "exp" "log" "tan")
      return :typed_array_f64
    if recv_t == :string_buffer
      if node.name == "to_s"
        return :string
      if node.name in ("append" "<<" "<</1")
        return :string_buffer
      if node.name in ("size" "byte_size")
        return :i64
    if recv_t == :string
      if node.name in ("repeat" "concat" "append" "prepend" "<<" "<</1")
        return :string
      if node.name in ("upcase" "downcase" "swapcase" "capitalize" "strip" "ltrim" "rtrim" "reverse" "replace" "gsub")
        return :string
      if node.name in ("ascii?" "valid_utf8?" "empty?" "include?" "starts_with?" "ends_with?")
        return :bool
      # Byte length (String#size is bytes, not codepoints) — raw machine
      # int, mirroring the is_array_type? size rule above.
      if node.name == "size" && (node.args == nil || node.args.size() == 0)
        return :i64
    return nil
  when :binary_op
    lt = infer_type(node.left, var_types, fn_return_types, infer_maps)
    rt = infer_type(node.right, var_types, fn_return_types, infer_maps)
    if node.op in (:DOT_PLUS :DOT_MINUS :DOT_STAR :DOT_SLASH :DOT_PIPE :DOT_AMP :DOT_CARET :DOT_LSHIFT :DOT_RSHIFT) && is_typed_array_type?(lt)
      return lt
    if node.op == :DOT_PRODUCT && is_typed_array_type?(lt) && is_typed_array_type?(rt)
      if lt in (:typed_array_i8 :typed_array_u8) && rt in (:typed_array_i8 :typed_array_u8)
        return :int
      return :float
    if node.op == :CROSS_PRODUCT && is_typed_array_type?(lt) && is_typed_array_type?(rt)
      return lt
    if node.op == :LSHIFT && lt == :string_buffer && rt == :string
      return :string_buffer
    if node.op == :LSHIFT && lt == :string
      return :string
    # Concatenation result is text — keeps the :string fact flowing so a
    # following .size()/+ takes the direct routes instead of IC dispatch.
    if node.op == :PLUS && lt == :string && rt == :string
      return :string
    if node.op == :PERCENT && lt == :string
      return :string
    # `int ** int` is intentionally NOT typed :int. w_pow returns a *boxed*
    # WValue that promotes to a BigInt whenever the result exceeds i48 (already
    # true at 2**60). Typing it :int authorizes the inline machine-int path for
    # a following op — e.g. `2**607 - 1` lowered to `sub i64` on the unboxed
    # bigint, truncating it to garbage. Falling through to nil routes downstream
    # arithmetic through the boxed, bigint-promoting runtime path, which is the
    # same path the variable form (`2 ** x - 1`) already takes correctly.
    #
    # `LIT << x` mirrors that rule: a bare literal base would infer :i64
    # through the machine map below, authorizing the inline machine path
    # downstream even though the untyped shift lowers through the boxed
    # __w_shl_fast and may yield a BigInt — `(1 << 200) + 999` unboxed the
    # BigInt result and answered 999. A bare literal carries no machine-type
    # opt-in, so the result is nil (boxed). Declared machine bases
    # (`## i64`/`## u64` slots) keep their machine result type below.
    if node.op == :LSHIFT && node.left != nil && is_ast_node?(node.left) && ast_kind(node.left) == :int
      return nil
    if is_integer_like_type(lt) && is_integer_like_type(rt)
      int_ops = infer_maps[:int_op_map]
      cmp_ops = infer_maps[:cmp_op_map]
      if int_ops[node.op] != nil
        # A `:int` operand is boxed and may hold a BigInt, and the guarded
        # arms' runtime fallbacks then produce a BigInt RESULT — so the
        # result must stay `:int` too. machine_int_result_type ignores
        # `:int` (it only ranks machine widths), and letting the other
        # operand's :i64 label the result authorized the machine path for
        # the ENCLOSING op: `(0 - <big literal>) * 3` kept the guarded
        # subtract but then ran `mul i64` on its possibly-boxed result.
        # Mirrors lower_binary_op's promotable_int_operand exclusion.
        if lt == :int || rt == :int
          return :int
        mt = machine_int_result_type(lt, rt)
        if mt != nil
          return mt
        return :int
      if cmp_ops[node.op] != nil
        return :bool
    if (lt == :float || lt == :f64) && (rt == :float || rt == :f64)
      float_ops = infer_maps[:float_op_map]
      fcmp_ops = infer_maps[:fcmp_op_map]
      if float_ops[node.op] != nil
        if lt == :f64 || rt == :f64
          return :f64
        return :float
      if fcmp_ops[node.op] != nil
        return :bool
    # int op float → float (promotion)
    if (lt == :float && is_integer_like_type(rt)) || (is_integer_like_type(lt) && rt == :float)
      float_ops = infer_maps[:float_op_map]
      if float_ops[node.op] != nil
        return :float
  when :in_test
    return :bool
  when :unary_op
    op = node.op
    if op in (:PLUS :MINUS) && node.operand != nil && ast_kind(node.operand) == :int
      return infer_type(node.operand, var_types, fn_return_types, infer_maps)
  else
    nil

-> infer_fn_return_type(node, infer_maps = nil)
  body = node.body
  if body == nil || body.size() == 0
    return nil
  last = body[body.size() - 1]
  if ast_kind(last) == :return && last.value != nil
    last = last.value
  # A machine-int `## hint` on the tail expression is authoritative — the
  # general inferencer does not track hints, which loses u64-ness and later
  # boxes the raw return through the signed int fast path.
  if is_ast_node?(last) && last.type_hint != nil
    if last.type_hint in ("i64" "u64" "i128" "u128")
      return normalize_type_symbol(last.type_hint)
  infer_type(last, {}, {}, infer_maps)
