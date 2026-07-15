# Lowering — transforms AST hashes into WIRE IR
# Phase 3: handles int, string, bool, nil, var, assign, binary_op,
# unary_op, simple calls, puts/print, if, while, return.
# Unsupported nodes produce clear error messages.

use runtime_types
use wire
use target
use lowering/pass_registry
use lowering/types
use lowering/analysis
use lowering/monomorphize
use lowering/literals
use lowering/ops
use lowering/blocks
use lowering/control_flow
use lowering/poly_sum
use lowering/pipeline_fusion
use lowering/calls
use lowering/method_call
use lowering/definitions

-> receiver_static_type(ctx, recv_node)
  recv_type = infer_type(recv_node, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
  if recv_type == nil && recv_node != nil && ast_kind(recv_node) == :var
    if ctx[:mod][:top_level_static_types] != nil
      recv_type = ctx[:mod][:top_level_static_types][recv_node.name]
    if recv_type == nil && ctx[:mod][:top_level_var_types] != nil
      recv_type = ctx[:mod][:top_level_var_types][recv_node.name]
  recv_type

-> top_level_assignment_static_type(expr, mod)
  if expr.type_hint != nil
    if expr.type_hint == "w64"
      return :i64
    # Opt-in auto-promoting BigInt accumulator (top-level seed).
    if expr.type_hint == "big" || expr.type_hint == "bigint" || expr.type_hint == "bignum"
      return :bigint
    ht = expr.type_hint
    htl = ht.size()
    # `## f32[]` / `## i32[]` / etc. — normalize to :typed_array_<etype>
    # so receiver_static_type → typed_array_get_inline fast path fires.
    if htl >= 3 && ht.slice(htl - 2, 2) == "\[]"
      return typed_array_etype_to_sym(ht.slice(0, htl - 2))
    return normalize_type_symbol(expr.type_hint)
  # Infer the RHS against the static types collected so far, not an empty
  # map — otherwise a reassignment like `x = x * y` (no `##` hint) can't see
  # that x/y are machine-ints, infers :int, and downgrades x's recorded type.
  st = mod[:top_level_static_types]
  if st == nil
    st = {}
  infer_type(expr.value, st, mod[:fn_return_types], lowering_infer_maps)

-> collect_top_level_static_types(mod, expressions)
  if mod[:top_level_static_types] == nil
    mod[:top_level_static_types] = {}
  if mod[:top_level_const_values] == nil
    mod[:top_level_const_values] = {}

  # First pass: count top-level :assign targets per name. A var assigned
  # exactly once at module scope is eligible for `constant` emission.
  # `assign_count[nm]` is nil → 1, true → "already saw more than one".
  assign_count = {}
  i = 0
  while i < expressions.size()
    expr = expressions[i]
    if expr != nil && is_ast_node?(expr) && ast_kind(expr) == :assign
      target = expr.target
      if target != nil && is_ast_node?(target) && ast_kind(target) == :var
        nm = target.name
        prev = assign_count[nm]
        if prev == nil
          assign_count[nm] = 1
        else
          assign_count[nm] = true
    i += 1

  i = 0
  while i < expressions.size()
    expr = expressions[i]
    if expr != nil && is_ast_node?(expr) && ast_kind(expr) == :assign
      target = expr.target
      if target != nil && is_ast_node?(target) && ast_kind(target) == :var
        name = target.name
        static_type = top_level_assignment_static_type(expr, mod)
        if static_type != nil
          # Don't let a later, weaker inference (e.g. a hintless reassignment
          # inferred as :int) clobber a machine-int type already established by
          # an explicit `## u64`/`## i64` annotation on an earlier assignment.
          prev = mod[:top_level_static_types][name]
          if is_bigint_type(prev) && !is_bigint_type(static_type)
            # Sticky BigInt seed: don't let a later weaker inference downgrade
            # a `## big` top-level accumulator back to :int (which would
            # re-enable native-wrap unboxing in the loop).
            nil
          elsif prev == nil || !is_machine_int_type(prev) || is_machine_int_type(static_type)
            mod[:top_level_static_types][name] = static_type
        # Predeclare the global so function bodies lowered before the
        # assignment still resolve the name as a module-scope value.
        mod[:top_level_vars][name] = true
        # Constant detection: a single-assignment `## i64` top-level var
        # with an integer-literal RHS is folded to an LLVM `constant`.
        # The store at module-init time is skipped; every load of the
        # global folds to the literal.
        if assign_count[name] == 1 && expr.type_hint == "i64"
          val_node = expr.value
          if val_node != nil && is_ast_node?(val_node)
            vk = ast_kind(val_node)
            # :int  — small integer literal (e.g. KIND_PROGRAM = 60)
            # :wvalue — raw 64-bit literal (e.g. AST_NIL = u0xFFFE60CC00000000),
            #   needed for tag-only singletons whose values overflow i48.
            if vk == :int || vk == :wvalue
              iv = val_node.value
              if type(iv) == "Integer"
                mod[:top_level_const_values][name] = iv
    i += 1

-> closure_binding_assignment_count(node, name)
  if node == nil
    return 0
  if type(node) == "Array"
    total = 0
    i = 0
    while i < node.size()
      total += closure_binding_assignment_count(node[i], name)
      i += 1
    return total
  if !is_ast_node?(node)
    return 0
  if ast_kind(node) in (:method_def :fn_def :class_def :module_def :trait_def)
    return 0
  total = 0
  if ast_kind(node) == :assign
    target = node.target
    if target != nil && is_ast_node?(target) && ast_kind(target) == :var && target.name == name
      total += 1
  # The :assign-target-skip case is specific: we don't count the LHS
  # of an assignment as a binding use. Schema for :assign is
  # {:target=>0, :value=>1, :type_hint=>2}; :type_hint is a sym, not
  # AST, so only :value matters.
  if ast_kind(node) == :assign
    total += closure_binding_assignment_count(node.value, name)
  else
    ast_children(node).each -> (c)
      total += closure_binding_assignment_count(c, name)
  total

-> closure_binding_safe_use?(node, name)
  if node == nil
    return true
  if type(node) == "Array"
    i = 0
    while i < node.size()
      if !closure_binding_safe_use?(node[i], name)
        return false
      i += 1
    return true
  if !is_ast_node?(node)
    return true
  if ast_kind(node) in (:method_def :fn_def :class_def :module_def :trait_def)
    return true
  if ast_kind(node) == :var && node.name == name
    return false
  if ast_kind(node) == :assign
    return closure_binding_safe_use?(node.value, name)
  if ast_kind(node) == :block
    params = node.params
    if params != nil
      pi = 0
      while pi < params.size()
        pname = params[pi]
        if is_ast_node?(pname)
          pname = pname.name
        if pname == name
          return true
        pi += 1
  if ast_kind(node) == :call
    # A bare call `name(...)` directly invokes the closure-bound variable. The
    # callee is encoded in Call.name (a string), not as a :var child, so the
    # generic child traversal below never sees it as a use — and the closure
    # would be wrongly elided, leaving the call to load nil ("expected
    # closure"). A direct invocation needs a materialized closure WValue, so it
    # is an escaping use. (`name.call(...)` is already caught: its receiver is a
    # real :var child handled above.)
    if node.receiver == nil && node.name == name
      return false
    args = node.args
    if node.receiver != nil && node.block == nil && args != nil && args.size() >= 1 && inline_closure_arg_iterator_method?(node.name)
      last = args[args.size() - 1]
      if last != nil && is_ast_node?(last) && ast_kind(last) == :var && last.name == name
        if !closure_binding_safe_use?(node.receiver, name)
          return false
        ai = 0
        while ai < args.size() - 1
          if !closure_binding_safe_use?(args[ai], name)
            return false
          ai += 1
        return true
  children = ast_children(node)
  i = 0
  while i < children.size()
    if !closure_binding_safe_use?(children[i], name)
      return false
    i += 1
  true

-> closure_binding_var_use_count(node, name)
  if node == nil
    return 0
  if type(node) == "Array"
    total = 0
    i = 0
    while i < node.size()
      total += closure_binding_var_use_count(node[i], name)
      i += 1
    return total
  if !is_ast_node?(node)
    return 0
  if ast_kind(node) in (:method_def :fn_def :class_def :module_def :trait_def)
    return 0
  if ast_kind(node) == :var && node.name == name
    return 1
  if ast_kind(node) == :assign
    return closure_binding_var_use_count(node.value, name)
  if ast_kind(node) == :block
    params = node.params
    if params != nil
      pi = 0
      while pi < params.size()
        pname = params[pi]
        if is_ast_node?(pname)
          pname = pname.name
        if pname == name
          return 0
        pi += 1
  total = 0
  ast_children(node).each -> (c)
    total += closure_binding_var_use_count(c, name)
  total

-> closure_binding_consumed_as_iter_arg?(node, name)
  if node == nil || !is_ast_node?(node)
    return false
  if ast_kind(node) == :call
    args = node.args
    if node.receiver != nil && node.block == nil && args != nil && args.size() >= 1 && inline_closure_arg_iterator_method?(node.name)
      last = args[args.size() - 1]
      return last != nil && is_ast_node?(last) && ast_kind(last) == :var && last.name == name
  if ast_kind(node) in (:assign :return :puts :print)
    return closure_binding_consumed_as_iter_arg?(node.value, name)
  if ast_kind(node) == :passthrough
    return closure_binding_consumed_as_iter_arg?(node.expression, name) || closure_binding_consumed_as_iter_arg?(node.value, name)
  false

-> closure_binding_consumed_by_next_stmt?(ctx, name)
  stmts = ctx[:enclosing_stmts]
  idx = ctx[:enclosing_stmt_idx]
  if stmts == nil || idx == nil || idx + 1 >= stmts.size()
    return false
  if closure_binding_assignment_count(stmts, name) != 1
    return false
  if closure_binding_var_use_count(stmts, name) != 1
    return false
  closure_binding_consumed_as_iter_arg?(stmts[idx + 1], name)

-> closure_binding_no_escape?(ctx, name)
  stmts = ctx[:enclosing_stmts]
  if stmts == nil
    return false
  if closure_binding_assignment_count(stmts, name) != 1
    return false
  closure_binding_safe_use?(stmts, name)

-> inline_block_param_name(block, ctx)
  params = block.params
  if params == nil || params.size() == 0
    params = lower_block_free_vars(block, ctx)
  if params == nil || params.size() == 0
    return nil
  param = params[0]
  if is_ast_node?(param)
    return param.name
  param

-> normalize_type_symbol(t)
  if t == nil
    return nil
  # Compare as symbols rather than strings — Tungsten symbol-derived strings
  # (`sym.to_s()`) don't compare equal to literal string constants via `==`,
  # so the previous string-based check silently failed for inferred :int /
  # :raw_int args. Keeping the if-chain at the symbol level matches what
  # callers actually pass in (Tungsten symbols are interned by content).
  if t == :int || t == :integer || t == :raw_int || t == :raw_i64
    return :i64
  if t == :float || t == :double || t == :Float
    return :f64
  if t == :String
    return :string
  if t == :StringBuffer
    return :string_buffer
  if t == :Value || t == :wvalue
    return :value
  if type(t) == "String"
    return t.to_sym()
  t

-> normalized_signature_types(types)
  if types == nil
    return nil
  out = []
  i = 0
  while i < types.size()
    out.push(normalize_type_symbol(types[i]))
    i += 1
  out

-> overload_signature_key(types)
  if types == nil
    return nil
  out = StringBuffer(types.size() * 16)
  i = 0
  while i < types.size()
    if i > 0
      out << ","
    out << canonical_signature_type(types[i]).to_s()
    i += 1
  out.to_s()

# Array types have two spellings: the declared form (`:"i64[]"`, straight
# from the parser) and the inferred form (`:typed_array_i64`, what
# infer_type produces for allocations and what definitions.w records for
# typed params). Signature keys are the one place both spellings must
# collide onto the same string — a def registered under `verify|i64[],i64`
# is unreachable from a call site that inferred `verify|typed_array_i64,i64`
# and falls through to a nonexistent `__w_verify` extern.
-> canonical_signature_type(t)
  n = normalize_type_symbol(t)
  if n == nil
    return nil
  # Plain array literals/allocations infer as :array, while an inline
  # signature such as `(Array)` reaches here as :Array.  Canonicalize only the
  # dispatch key: changing the general inferred type also changes generic
  # class lowering and the established signature-mangled symbol spelling.
  if n == :Array
    return :array
  s = n.to_s()
  sl = s.size()
  if sl >= 3 && s.slice(sl - 2, 2) == "\[]"
    return typed_array_etype_to_sym(s.slice(0, sl - 2))
  n

-> typed_call_signature_key(name, types)
  sig = overload_signature_key(types)
  if sig == nil
    return name
  name + "|" + sig

-> typed_overload_arity_key(name, arity)
  name + "/" + arity.to_s()

-> method_call_key_for_def(node)
  if node.param_types == nil
    return node.name
  typed_call_signature_key(node.name, node.param_types)

-> mangle_type_signature(types)
  out = StringBuffer(types.size() * 16)
  i = 0
  while i < types.size()
    if i > 0
      out << "_"
    s = normalize_type_symbol(types[i]).to_s()
    j = 0
    while j < s.size()
      ch = s[j]
      case ch
      when "\["
        out << "_A"
      when "\]"
        nil
      else
        out << ch
      j += 1
    i += 1
  out.to_s()

# Mark top-level fn defs that form a typed-overload set (the same name and
# arity declared more than once). function_name_for_def only signature-mangles
# when typed_overload is set, so without this flag both overloads collapse onto
# the bare `__w_NAME` symbol — two identically-named functions in mod[:functions]
# then send the content-hash topo-sort into an infinite loop. Flagging them
# yields distinct symbols (`__w_describe__i64` vs `__w_describe__f64`); the
# existing call-site resolver (calls.w) already maps a call to the right one by
# inferred argument type via known_calls[name|sig].
-> mark_fn_overload_groups(expressions)
  counts = {}
  i = 0
  while i < expressions.size()
    expr = expressions[i]
    if ast_kind(expr) in (:fn_def :method_def) && expr.param_types != nil
      key = "" + expr.name + "/" + expr.params.size().to_s()
      c = counts[key]
      if c == nil
        c = 0
      counts[key] = c + 1
    i += 1
  i = 0
  while i < expressions.size()
    expr = expressions[i]
    if ast_kind(expr) in (:fn_def :method_def) && expr.param_types != nil
      key = "" + expr.name + "/" + expr.params.size().to_s()
      if counts[key] > 1
        expr.typed_overload = true
    i += 1
  nil

# After overload marking, two top-level defs that still produce the SAME mangled
# symbol are a true duplicate — an untyped redefinition, or two typed defs with
# identical signatures. The content-hash topo-sort infinite-loops on identical
# symbols (it never retires the duplicated name), so reject them with a clear
# error instead of hanging the compiler.
-> check_duplicate_fn_defs(expressions, source_path)
  seen = {}
  i = 0
  while i < expressions.size()
    expr = expressions[i]
    if ast_kind(expr) in (:fn_def :method_def)
      sym = function_name_for_def(expr)
      if seen[sym] == true
        raise compile_error_for_node(:E_LOWER_DUP_DEF, "duplicate definition of '" + expr.name + "' — a function with this name and signature is already defined", source_path, expr)
      seen[sym] = true
    i += 1
  nil

-> function_name_for_def(node)
  # Typed-overload mangling only when the user actually has multiple
  # definitions for the same name. Single-definition typed fns keep
  # the bare `__w_NAME` symbol so call sites that haven't been taught
  # to look up by signature still resolve correctly.
  base = "__w_" + mangle_method_name(node.name)
  if node.param_types != nil
    return base + "__" + mangle_type_signature(node.param_types)
  base

-> inferred_arg_types(args, var_types, fn_return_types, infer_maps)
  out = []
  i = 0
  while i < args.size()
    out.push(normalize_type_symbol(infer_type(args[i], var_types, fn_return_types, infer_maps)))
    i += 1
  out

-> infer_type(node, var_types, fn_return_types, infer_maps = nil)
  if infer_maps == nil
    infer_maps = lowering_infer_maps
  if node == nil
    return nil
  t = ast_kind(node)
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
    if etype in ("u4" "i4")
      return typed_array_etype_to_sym(etype)
    if etype in ("u8" "i8" "u16" "i16" "u32" "i32" "u64" "i64" "f64" "f32" "bf16" "w64")
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
    # Phase 6f: SmallArray.new(:ebits, size) → :small_array_<ebits>.
    # Lets downstream call sites (s[i], s[i] = v, s.size, ...) take
    # the SmallArray inline-op fast path when the receiver was assigned
    # from this constructor.
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
        if ebits == 65
          return :small_array
    if node.name == "lchs"
      return infer_lchs_return_type(node.args)
    if node.name == "to_i" && node.args != nil && node.args.size() == 0
      return :i64
    # Math.* compiler intrinsics always yield a float: the w_math_*
    # intercepts (lowering/method_call.w) wrap their result in w_float
    # unconditionally. Without this, an expression like `Math.sin(x) + c`
    # infers nil and the `+` falls back to a boxed w_add call instead of a
    # raw fadd — the shared-inference twin of the raw libm fast path. This
    # list covers ONLY the intercepted builtins, which have no .w
    # definition to annotate; core/math.w methods (atan, tanh, hypot, …)
    # carry `f64` return-type annotations and resolve through the
    # static-receiver fn_return_types lookup above.
    if node.receiver != nil && ast_kind(node.receiver) in (:var :class_ref :call) && node.receiver.name == "Math"
      if node.name in ("exp" "log" "sin" "cos" "tan" "sqrt" "floor" "ceil" "round" "abs" "pow" "ldexp" "atan2")
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
      if recv_t in (:typed_array_f64 :typed_array_f32 :typed_array_bf16)
        return :float
      return :int
    if is_typed_array_type?(recv_t) && node.name in ("fastsum" "sumsq" "dot")
      if recv_t in (:typed_array_f64 :typed_array_f32 :typed_array_bf16)
        return :float
      if recv_t in (:typed_array_i8 :typed_array_u8) && node.name == "dot"
        return :int
    if is_typed_array_type?(recv_t) && node.name in ("cross" "scale" "scale!")
      if recv_t in (:typed_array_f64 :typed_array_f32 :typed_array_bf16)
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
    if node.op == :PERCENT && lt == :string
      return :string
    # `int ** int` is intentionally NOT typed :int. w_pow returns a *boxed*
    # WValue that promotes to a BigInt whenever the result exceeds i48 (already
    # true at 2**60). Typing it :int authorizes the inline machine-int path for
    # a following op — e.g. `2**607 - 1` lowered to `sub i64` on the unboxed
    # bigint, truncating it to garbage. Falling through to nil routes downstream
    # arithmetic through the boxed, bigint-promoting runtime path, which is the
    # same path the variable form (`2 ** x - 1`) already takes correctly.
    if is_integer_like_type(lt) && is_integer_like_type(rt)
      int_ops = infer_maps[:int_op_map]
      cmp_ops = infer_maps[:cmp_op_map]
      if int_ops[node.op] != nil
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
    return infer_type(last.value, {}, {}, infer_maps)
  infer_type(last, {}, {}, infer_maps)

-> trait_include_name(mod, node)
  if ast_kind(node) == :trait_include
    return node.name
  if ast_kind(node) == :use && mod[:known_traits][node.path] != nil
    return node.path
  nil

-> expand_class_traits(mod, body)
  if body == nil
    return []
  expanded = []
  i = 0
  while i < body.size()
    expr = body[i]
    trait_name = trait_include_name(mod, expr)
    if trait_name != nil
      trait_def = mod[:known_traits][trait_name]
      if trait_def == nil && ast_kind(expr) == :trait_include
        raise compile_error_for_node(:E_LOWER_UNKNOWN_TRAIT, "Unknown trait '" + trait_name + "'", nil, expr)
      if trait_def != nil && trait_def.body != nil
        j = 0
        while j < trait_def.body.size()
          expanded.push(trait_def.body[j])
          j += 1
    i += 1
  i = 0
  while i < body.size()
    expr = body[i]
    trait_name = trait_include_name(mod, expr)
    if trait_name == nil || mod[:known_traits][trait_name] == nil
      expanded.push(expr)
    i += 1
  expanded

# Register AST class constructor return types so infer_type can
# recognize `Tungsten:AST:X.new(...)` as producing a specific AST
# kind. This unlocks the strict-gated node.field recognizer in
# lower_call: with these entries in place, the type of a freshly-
# constructed AST node is statically pinned and downstream field
# accesses can bypass method_missing dispatch via direct ast_get.
# Two special cases override the snake_case derivation:
#   Nil  → :nil_lit (the kind in ast_schema, not :nil)
#   Self → :self_ref
# All other class names convert PascalCase → snake_case directly.
-> register_ast_constructor_return_types(mod)
  mod[:fn_return_types]["Tungsten:AST:File.new"] = :file
  mod[:fn_return_types]["Tungsten:AST:Program.new"] = :program
  mod[:fn_return_types]["Tungsten:AST:Int.new"] = :int
  mod[:fn_return_types]["Tungsten:AST:Wvalue.new"] = :wvalue
  mod[:fn_return_types]["Tungsten:AST:Float.new"] = :float
  mod[:fn_return_types]["Tungsten:AST:Decimal.new"] = :decimal
  mod[:fn_return_types]["Tungsten:AST:TypedArrayNew.new"] = :typed_array_new
  mod[:fn_return_types]["Tungsten:AST:String.new"] = :string
  mod[:fn_return_types]["Tungsten:AST:StringInterp.new"] = :string_interp
  mod[:fn_return_types]["Tungsten:AST:Regex.new"] = :regex
  mod[:fn_return_types]["Tungsten:AST:RegexCapture.new"] = :regex_capture
  mod[:fn_return_types]["Tungsten:AST:Bool.new"] = :bool
  mod[:fn_return_types]["Tungsten:AST:Nil.new"] = :nil_lit
  mod[:fn_return_types]["Tungsten:AST:Symbol.new"] = :symbol
  mod[:fn_return_types]["Tungsten:AST:MagicConstant.new"] = :magic_constant
  mod[:fn_return_types]["Tungsten:AST:Array.new"] = :array
  mod[:fn_return_types]["Tungsten:AST:ScheduleDef.new"] = :schedule_def
  mod[:fn_return_types]["Tungsten:AST:LayoutDef.new"] = :layout_def
  mod[:fn_return_types]["Tungsten:AST:HashLiteral.new"] = :hash_literal
  mod[:fn_return_types]["Tungsten:AST:ByteArray.new"] = :byte_array
  mod[:fn_return_types]["Tungsten:AST:ByteArrayInterp.new"] = :byte_array_interp
  mod[:fn_return_types]["Tungsten:AST:Currency.new"] = :currency
  mod[:fn_return_types]["Tungsten:AST:Quantity.new"] = :quantity
  mod[:fn_return_types]["Tungsten:AST:Duration.new"] = :duration
  mod[:fn_return_types]["Tungsten:AST:Uuid.new"] = :uuid
  mod[:fn_return_types]["Tungsten:AST:Date.new"] = :date
  mod[:fn_return_types]["Tungsten:AST:Datetime.new"] = :datetime
  mod[:fn_return_types]["Tungsten:AST:Time.new"] = :time
  mod[:fn_return_types]["Tungsten:AST:Month.new"] = :month
  mod[:fn_return_types]["Tungsten:AST:Ip4.new"] = :ip4
  mod[:fn_return_types]["Tungsten:AST:Cidr4.new"] = :cidr4
  mod[:fn_return_types]["Tungsten:AST:Ip6.new"] = :ip6
  mod[:fn_return_types]["Tungsten:AST:Cidr6.new"] = :cidr6
  mod[:fn_return_types]["Tungsten:AST:Rational.new"] = :rational
  mod[:fn_return_types]["Tungsten:AST:Char.new"] = :char
  mod[:fn_return_types]["Tungsten:AST:Codepoint.new"] = :codepoint
  mod[:fn_return_types]["Tungsten:AST:Key.new"] = :key
  mod[:fn_return_types]["Tungsten:AST:WordArray.new"] = :word_array
  mod[:fn_return_types]["Tungsten:AST:SymbolArray.new"] = :symbol_array
  mod[:fn_return_types]["Tungsten:AST:MapOp.new"] = :map_op
  mod[:fn_return_types]["Tungsten:AST:Map.new"] = :map
  mod[:fn_return_types]["Tungsten:AST:Calc.new"] = :calc
  mod[:fn_return_types]["Tungsten:AST:Parg.new"] = :parg
  mod[:fn_return_types]["Tungsten:AST:LambdaArity.new"] = :lambda_arity
  mod[:fn_return_types]["Tungsten:AST:Superscript.new"] = :superscript
  mod[:fn_return_types]["Tungsten:AST:Encoded.new"] = :encoded
  mod[:fn_return_types]["Tungsten:AST:Color.new"] = :color
  mod[:fn_return_types]["Tungsten:AST:ViewDecl.new"] = :view_decl
  mod[:fn_return_types]["Tungsten:AST:FieldDecl.new"] = :field_decl
  mod[:fn_return_types]["Tungsten:AST:ViewAccess.new"] = :view_access
  mod[:fn_return_types]["Tungsten:AST:ViewField.new"] = :view_field
  mod[:fn_return_types]["Tungsten:AST:ViewFieldVar.new"] = :view_field_var
  mod[:fn_return_types]["Tungsten:AST:ViewBase.new"] = :view_base
  mod[:fn_return_types]["Tungsten:AST:ViewValue.new"] = :view_value
  mod[:fn_return_types]["Tungsten:AST:Var.new"] = :var
  mod[:fn_return_types]["Tungsten:AST:ClassRef.new"] = :class_ref
  mod[:fn_return_types]["Tungsten:AST:Ivar.new"] = :ivar
  mod[:fn_return_types]["Tungsten:AST:Cvar.new"] = :cvar
  mod[:fn_return_types]["Tungsten:AST:GVar.new"] = :gvar
  mod[:fn_return_types]["Tungsten:AST:Self.new"] = :self_ref
  mod[:fn_return_types]["Tungsten:AST:Assign.new"] = :assign
  mod[:fn_return_types]["Tungsten:AST:CompoundAssign.new"] = :compound_assign
  mod[:fn_return_types]["Tungsten:AST:MultiAssign.new"] = :multi_assign
  mod[:fn_return_types]["Tungsten:AST:BinaryOp.new"] = :binary_op
  mod[:fn_return_types]["Tungsten:AST:UnaryOp.new"] = :unary_op
  mod[:fn_return_types]["Tungsten:AST:And.new"] = :and
  mod[:fn_return_types]["Tungsten:AST:Or.new"] = :or
  mod[:fn_return_types]["Tungsten:AST:Not.new"] = :not
  mod[:fn_return_types]["Tungsten:AST:InTest.new"] = :in_test
  mod[:fn_return_types]["Tungsten:AST:Passthrough.new"] = :passthrough
  mod[:fn_return_types]["Tungsten:AST:Range.new"] = :range
  mod[:fn_return_types]["Tungsten:AST:If.new"] = :if
  mod[:fn_return_types]["Tungsten:AST:While.new"] = :while
  mod[:fn_return_types]["Tungsten:AST:With.new"] = :with
  mod[:fn_return_types]["Tungsten:AST:ParallelWith.new"] = :parallel_with
  mod[:fn_return_types]["Tungsten:AST:Case.new"] = :case
  mod[:fn_return_types]["Tungsten:AST:When.new"] = :when
  mod[:fn_return_types]["Tungsten:AST:CaseValue.new"] = :case_value
  mod[:fn_return_types]["Tungsten:AST:CaseArm.new"] = :case_arm
  mod[:fn_return_types]["Tungsten:AST:SafeNav.new"] = :safe_nav
  mod[:fn_return_types]["Tungsten:AST:RescueExpr.new"] = :rescue_expr
  mod[:fn_return_types]["Tungsten:AST:Break.new"] = :break
  mod[:fn_return_types]["Tungsten:AST:Next.new"] = :next
  mod[:fn_return_types]["Tungsten:AST:Return.new"] = :return
  mod[:fn_return_types]["Tungsten:AST:Recase.new"] = :recase
  mod[:fn_return_types]["Tungsten:AST:ReturnNil.new"] = :return_nil
  mod[:fn_return_types]["Tungsten:AST:TypedArray.new"] = :typed_array
  mod[:fn_return_types]["Tungsten:AST:ClassDef.new"] = :class_def
  mod[:fn_return_types]["Tungsten:AST:ModuleDef.new"] = :module_def
  mod[:fn_return_types]["Tungsten:AST:TraitDef.new"] = :trait_def
  mod[:fn_return_types]["Tungsten:AST:TraitInclude.new"] = :trait_include
  mod[:fn_return_types]["Tungsten:AST:NamespaceDecl.new"] = :namespace_decl
  mod[:fn_return_types]["Tungsten:AST:IvarsDecl.new"] = :ivars_decl
  mod[:fn_return_types]["Tungsten:AST:MethodDef.new"] = :method_def
  mod[:fn_return_types]["Tungsten:AST:FnDef.new"] = :fn_def
  mod[:fn_return_types]["Tungsten:AST:GpuKernelDef.new"] = :gpu_kernel_def
  mod[:fn_return_types]["Tungsten:AST:Param.new"] = :param
  mod[:fn_return_types]["Tungsten:AST:Call.new"] = :call
  mod[:fn_return_types]["Tungsten:AST:Block.new"] = :block
  mod[:fn_return_types]["Tungsten:AST:Puts.new"] = :puts
  mod[:fn_return_types]["Tungsten:AST:Print.new"] = :print
  mod[:fn_return_types]["Tungsten:AST:Raise.new"] = :raise
  mod[:fn_return_types]["Tungsten:AST:Begin.new"] = :begin
  mod[:fn_return_types]["Tungsten:AST:Use.new"] = :use
  mod[:fn_return_types]["Tungsten:AST:Yield.new"] = :yield
  mod[:fn_return_types]["Tungsten:AST:Super.new"] = :super
  mod[:fn_return_types]["Tungsten:AST:ExternLib.new"] = :extern_lib
  mod[:fn_return_types]["Tungsten:AST:ExternFn.new"] = :extern_fn
  mod[:fn_return_types]["Tungsten:AST:Go.new"] = :go
  mod[:fn_return_types]["Tungsten:AST:TargetDesignator.new"] = :target_designator
  mod[:fn_return_types]["Tungsten:AST:TargetAnd.new"] = :target_and
  mod[:fn_return_types]["Tungsten:AST:TargetOr.new"] = :target_or
  mod[:fn_return_types]["Tungsten:AST:TargetNot.new"] = :target_not
  mod[:fn_return_types]["Tungsten:AST:OnGuard.new"] = :on_guard
  mod[:fn_return_types]["Tungsten:AST:RegexMatch.new"] = :regex_match
  mod[:fn_return_types]["Tungsten:AST:CidrMatch.new"] = :cidr_match

# -- Main entry point --

# True iff `s` parses cleanly as a (possibly negative) decimal integer.
# Used by lower_var to decide whether a -D value is an int literal vs
# a string literal. We can't use s.to_i directly because Tungsten's
# .to_i is forgiving ("abc".to_i = 0) — we'd silently swallow typos.
-> build_define_is_int?(s)
  if s == nil || s.size() == 0
    return false
  start = 0
  if s.slice(0, 1) == "-"
    start = 1
    if s.size() == 1
      return false
  i = start
  while i < s.size()
    c = s.slice(i, 1)
    if c < "0" || c > "9"
      return false
    i += 1
  true

# Emit a string literal for a -D define value. Mirrors lower_string but
# operates on a raw string (not an AST node) and writes into the
# current function builder.
-> lower_build_define_string(ctx, s)
  byte_len = utf8_byte_length(s)
  # SSO-5: strings ≤5 bytes encode as an i64 constant — no global needed.
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

-> parse_build_defines_env
  # Parse the TUNGSTEN_DEFINES env var, format "NAME1=VAL1;NAME2=VAL2".
  # Returns a hash mapping uppercase name → raw value string. Empty if
  # the env var is unset or malformed.
  defs = {}
  raw = env("TUNGSTEN_DEFINES")
  if raw == nil || raw == ""
    return defs
  pairs = raw.split(";")
  i = 0
  while i < pairs.size()
    pair = pairs[i]
    eq = pair.index("=")
    if eq != nil && eq > 0
      key = pair.slice(0, eq).strip()
      val = pair.slice(eq + 1, pair.size() - eq - 1).strip()
      if key != ""
        defs[key] = val
    i += 1
  defs

-> lower_ast(ast, source_path, verbose = false, fast_mode = false, build_defines = nil, math_mode = :precise)
  mod = wire_module(source_path)
  mod[:fast_mode] = fast_mode
  mod[:math_mode] = math_mode
  # Build-time defines come from two sources, in priority order:
  #   1. `build_defines` arg — populated from `-D NAME=VALUE` CLI flags
  #   2. TUNGSTEN_DEFINES env var — useful for shell scripts and tests
  # The arg wins if both are present.
  if build_defines != nil && build_defines.size() > 0
    mod[:build_defines] = build_defines
  else
    env_defs = parse_build_defines_env()
    if env_defs.size() > 0
      mod[:build_defines] = env_defs
  register_ast_constructor_return_types(mod)
  var_types = {}

  # Built-in runtime classes are available to top-level expressions; source
  # classes with the same name still take precedence.
  builtin_classes = builtin_runtime_classes
  mod[:builtin_class_order] = builtin_classes
  mod[:builtin_class_names] = {}
  mod[:used_builtin_classes] = {}

  # Phase 5: monomorphization registries.
  # - class_method_asts[Class.method] → original method_def AST node
  #   (so specialize_method can clone it without re-parsing source).
  # - specialized_methods[Class.method.variant] → mangled fn name. Stub
  #   inserted before lowering body so recursive calls resolve via the cache.
  # - small_array_consts: list of {name, ebits, size, bytes} records for
  #   compile-time const array literals (Phase 5g). Emitter writes each
  #   as a private LLVM global; lowering ptrtoint's them at the load site.
  mod[:class_method_asts] = {}
  mod[:specialized_methods] = {}
  mod[:small_array_consts] = []
  # Top-level user fns whose entire param list is `## i64:`-annotated.
  # Maps source-name → mangled fn name. Callers pass raw i64 args
  # directly (no nanbox at the call site, no nanunbox at fn entry,
  # no nanbox on return). Detected during lower_method_def.
  mod[:raw_callable_fns] = {}
  bi = 0
  while bi < builtin_classes.size()
    mod[:builtin_class_names][builtin_classes[bi]] = true
    bi += 1

  # Runtime intrinsic methods that consume their own trailing block. They are
  # implemented in C (not .w), so the def-walk that populates block_method_names
  # never records them; without this seed, method_takes_no_block? assumes they
  # take no block and mis-rewrites `sock.serve_http { }` into
  # `serve_http().each { }` — serve_http then gets 0 args and dies on its block.
  mod[:block_method_names]["serve_http"] = true

  # Register built-in runtime functions so they aren't rewritten to self.method()
  # inside class bodies. These map to __w_<name> in the C runtime.
  mod[:known_calls]["read_file"] = "__w_read_file"
  mod[:known_calls]["read_file_bytes"] = "__w_read_file_bytes"
  mod[:known_calls]["file?"] = "__w_file_exists"
  mod[:known_calls]["file_exists?"] = "__w_file_exists"
  mod[:known_calls]["file_directory?"] = "__w_file_directory"
  mod[:known_calls]["file_mtime_ns"] = "__w_file_mtime_ns"
  mod[:known_calls]["file_size"] = "__w_file_size"
  mod[:known_calls]["read_dir"] = "__w_file_read_dir"
  mod[:known_calls]["write_file"] = "__w_write_file"
  mod[:known_calls]["write_file_bytes"] = "__w_write_file"
  mod[:known_calls]["digest_bytes64"] = "__w_digest_bytes64"
  mod[:known_calls]["digest_file64"] = "__w_digest_file64"
  mod[:known_calls]["digest_string64"] = "__w_digest_string64"
  mod[:known_calls]["cache_read"] = "__w_cache_read"
  mod[:known_calls]["cache_write"] = "__w_cache_write"
  mod[:known_calls]["system"] = "__w_system"
  mod[:known_calls]["capture"] = "__w_capture"
  mod[:known_calls]["exit"] = "__w_exit"
  mod[:known_calls]["raise"] = "w_raise"
  mod[:known_calls]["type"] = "__w_type"
  mod[:known_calls]["wymix"] = "__w_wymix"  # inlined, never actually called
  mod[:known_calls]["clock"] = "__w_clock"
  mod[:known_calls]["env"] = "__w_env"
  mod[:known_calls]["runtime_identity"] = "__w_runtime_identity"
  mod[:known_calls]["print"] = "__w_print"
  mod[:known_calls]["flush"] = "w_flush"
  mod[:known_calls]["read_bytes"] = "w_read_bytes"
  mod[:known_calls]["gets"] = "w_read_line_stdin"
  mod[:known_calls]["freeze_slab"] = "w_slab_freeze_safe"
  mod[:known_calls]["no_more_interns"] = "w_slab_freeze_safe"
  mod[:known_calls]["the_internship_is_over"] = "w_slab_freeze_safe"
  mod[:known_calls]["freeze_the_slab"] = "w_slab_freeze_safe"

  # ccall target registry (populated by lower_call when ccall() is used)
  mod[:ccall_fns] = {}

  # Pre-pass: infer return types, register fn memo tables, collect classes.
  #
  # Phase 3b: return-type inference runs as a fixed-point pass. Each
  # iteration re-runs infer_return_type on every method/fn; if the
  # iteration changes any return type, we loop. This handles mutually
  # recursive methods where method A's return type depends on method B
  # (and vice versa): iteration 1 fills in whichever resolves without
  # dependencies, iteration 2 uses iteration 1's results to resolve
  # the next layer, and so on.
  #
  # Max 3 iterations per full sweep. Most call graphs converge in 1-2
  # passes because real dependency chains are shallow. If we hit 3 and
  # still have changes, bail out — the unresolved methods keep their
  # last-inferred type and a warning is emitted. Users can resolve by
  # annotating explicit return types on one method in the cycle.
  #
  # Explicit `:return_type` annotations (from Phase 3 inline signatures)
  # are LOCKED IN on iteration 0 and never overwritten. Only inferred
  # (nil-annotated) methods get updated per iteration.
  mod[:uses_argv] = ast_uses_argv(ast.expressions)
  # Generic class monomorphization runs BEFORE the main expressions walk
  # so specialized classes are visible to every downstream pass.
  monomorphize_generics(ast, mod)
  # Flag top-level typed-overload sets so they get distinct symbols (must
  # run before the registration walk below reads function_name_for_def).
  mark_fn_overload_groups(ast.expressions)
  # Reject true duplicate top-level defs (same final symbol) before the
  # content-hash topo-sort would infinite-loop on them.
  check_duplicate_fn_defs(ast.expressions, source_path)
  # Collect methods and process class/module defs in a single walk.
  inferable_methods = []
  ei = 0
  while ei < ast.expressions.size()
    expr = ast.expressions[ei]
    if ast_kind(expr) == :trait_def
      mod[:known_traits][expr.name] = expr
    if ast_kind(expr) in (:method_def :fn_def)
      call_key = method_call_key_for_def(expr)
      fn_name = function_name_for_def(expr)
      param_count = expr.params.size()
      analysis = method_lowering_analysis(expr)
      if analysis[:yield_block_name] == "__block"
        param_count += 1
      # Record every method NAME that takes a block (declares `&` or yields).
      # The call-site block-passthrough rewrite consults this set: a trailing
      # block on a name that's NOT here iterates the call's result instead.
      if analysis[:yield_block_name] != nil || explicit_block_param_name(expr.params) != nil
        mod[:block_method_names][expr.name] = true
      mod[:known_calls][call_key] = fn_name
      mod[:known_fn_param_counts][call_key] = param_count
      if expr.param_types != nil
        arity_key = typed_overload_arity_key(expr.name, expr.params.size())
        overload_count = mod[:known_typed_overload_counts][arity_key]
        if overload_count == nil
          overload_count = 0
        mod[:known_typed_overload_counts][arity_key] = overload_count + 1
        mod[:known_unique_typed_overload_keys][arity_key] = call_key
        mod[:known_unique_typed_overload_param_types][arity_key] = expr.param_types
      if expr.return_type != nil
        mod[:fn_return_types][call_key] = normalize_type_symbol(expr.return_type)
      else
        inferable_methods.push(expr)
      if ast_kind(expr) == :fn_def
        # Skip memoization for fns whose body contains a ccall to a
        # known-impure C function (Metal allocators, syscalls, etc.).
        # Memoizing those would alias every call to the same retained
        # handle / cached side-effect, which is a correctness bug —
        # see the Metal dispatch_n smoke before this check landed.
        impure_ccall = fn_body_calls_impure_ccall?(expr.body)
        expr.calls_impure_ccall = impure_ccall
        if !impure_ccall
          mod[:known_pure_calls][call_key] = fn_name
          if mod[:fn_memo_tables][call_key] == nil
            mod[:fn_memo_tables][call_key] = fn_name + ".memo"
            mod[:fn_memo_table_order].push(call_key)
    if ast_kind(expr) in (:class_def :module_def)
      # Skip generic templates from known_classes / builtin marking —
      # they're not real classes. The specialization pass synthesizes
      # concrete defs that go through this path normally.
      if ast_kind(expr) == :class_def && expr.type_params != nil
        if mod[:generic_class_templates] == nil
          mod[:generic_class_templates] = {}
        mod[:generic_class_templates][expr.name] = expr
      else
        mod[:known_classes][expr.name] = expr
        if expr.superclass != nil
          mark_builtin_class_used(mod, expr.superclass)
    ei += 1
  # Fixed-point iteration over the inferable methods.
  iter = 0
  max_iter = 3
  still_changing = true
  while still_changing && iter < max_iter
    still_changing = false
    im = 0
    while im < inferable_methods.size()
      m = inferable_methods[im]
      call_key = method_call_key_for_def(m)
      old_rt = mod[:fn_return_types][call_key]
      # Seed inference with declared param types (canonical spelling) and
      # `## i64`-style body hints. With an empty map, a typed fn whose tail
      # expression flows through hinted locals inferred nil — its callers
      # then fell off the native machine-int path, boxing every arithmetic
      # op that consumed the call result (w_int + w_add per index expression
      # in the flip-graph walkers).
      pmap = {}
      if m.param_types != nil && m.params != nil
        pts2 = m.param_types
        pi2 = 0
        while pi2 < pts2.size() && pi2 < m.params.size()
          pmap[param_runtime_name(m.params[pi2])] = canonical_signature_type(pts2[pi2])
          pi2 += 1
      new_rt = infer_return_type(m, enrich_int_locals(m.body, pmap), mod[:fn_return_types], lowering_infer_maps)
      if new_rt != nil && new_rt != old_rt
        mod[:fn_return_types][call_key] = normalize_type_symbol(new_rt)
        still_changing = true
      im += 1
    iter += 1
  if still_changing
    # Didn't converge in max_iter passes. Emit a one-line warning to
    # stderr naming the unresolved methods so the user can annotate.
    # Not a hard error: inference bail-out just means those methods
    # get their current best-effort type (may be nil).
    << "warning: return-type inference didn't converge in [max_iter] passes; consider adding explicit return type annotations on recursive methods"

  # Freeze every top-level function's boxed-vs-raw ABI before any body is
  # lowered.  Forward typed calls must use the same ABI as callees declared
  # earlier; discovering raw-callable functions incrementally made source
  # order silently change the meaning of identical LLVM i64 parameters.
  preregister_top_level_raw_abis(mod, ast.expressions)

  collect_top_level_static_types(mod, ast.expressions)

  # Build main with argc/argv only if the program actually needs argv.
  main_extra = nil
  if mod[:uses_argv]
    main_extra = [{type: "i32", name: "%argc"}, {type: "ptr", name: "%argv"}]
  main_fn = build_function("main", [], "i32", true, main_extra)
  main_fn[:source_kind] = :entry
  main_fn[:source_path] = source_path
  mod[:functions].push(main_fn)

  # Initialize argv subsystem only for programs that touch ARGV / argv().
  if mod[:uses_argv]
    emit_instruction(main_fn, {op: :argv_init})

  ctx = {
    mod: mod,
    func: main_fn,
    var_types: var_types,
    class_name: nil,
    source_path: source_path,
    bindings: {},
    unboxed_vars: {},
    raw_int_candidates: raw_int_candidate_map(ast.expressions, var_types),
    method_name: nil,
    is_class_method: false,
    is_block: false,
    verbose: verbose
  }

  mark_builtin_runtime_class_uses(ast.expressions, mod)

  # Initialize built-in runtime classes
  bci = 0
  while bci < mod[:builtin_class_order].size()
    bc_name = mod[:builtin_class_order][bci]
    if mod[:used_builtin_classes][bc_name] == true
      bc_str_id = module_string_constant(mod, bc_name)
      bc_byte_len = utf8_byte_length(bc_name) + 1
      emit_instruction(main_fn, {op: :builtin_class_init, class_name: bc_name, name_str_id: bc_str_id, name_byte_len: bc_byte_len})
    bci += 1
  # Initialize classes in source order (respects inheritance dependencies).
  #
  # A class may be re-opened by multiple `class_def` / `+ ClassName` blocks
  # across files. For each class we instantiate w_class_new ONCE on the
  # first encounter; subsequent re-opens skip class creation and add their
  # own methods, accessors, and ivars to the existing class via the
  # register_class_method / load_class helpers. Last-defined method wins
  # (backed by runtime-side replace-on-duplicate in w_class_add_method).
  #
  # First-declaration wins for structural fields (superclass, dispatch
  # key). Re-opens can only add methods/accessors and append ivars.
  # Each class_def processes its OWN body (`expr.body`), not the
  # canonical one in mod[:known_classes] (which is the last-registered).
  processed_classes = {}
  ci = 0
  while ci < ast.expressions.size()
    expr = ast.expressions[ci]
    # Skip generic templates — only specialized classes get class_init.
    is_generic_template = ast_kind(expr) == :class_def && expr.type_params != nil
    if !is_generic_template && ast_kind(expr) in (:class_def :module_def)
      cname = expr.name
      is_reopen = processed_classes[cname] != nil

      if !is_reopen
        # First encounter: create the class object.
        name_str_id = module_string_constant(mod, cname)
        name_byte_len = utf8_byte_length(cname) + 1
        cls_temp = next_temp(main_fn)
        # Resolve an unqualified superclass via the enclosing namespace
        # chain so cross-file inheritance links to the right class — e.g.
        # a `Tungsten:Bit:Commands` subclass written `< Command` finds
        # `Tungsten:Bit:Command`. Bare names that already name a class or
        # a runtime builtin (StandardError, …) pass through unchanged.
        super_name = expr.superclass
        if super_name != nil && !super_name.include?(":") && mod[:known_classes][super_name] == nil
          ns_super = resolve_class_in_namespace(mod, cname, super_name)
          if ns_super != nil
            super_name = ns_super
        super_reg = nil
        if super_name != nil
          super_reg = next_temp(main_fn)
          emit_instruction(main_fn, {op: :load_class, temp: super_reg, class_name: super_name})
        emit_instruction(main_fn, {op: :class_new, temp: cls_temp, name_str_id: name_str_id, name_byte_len: name_byte_len, super_reg: super_reg})
        emit_instruction(main_fn, {op: :class_store, value: cls_temp, class_name: cname})

        # Register type dispatch key if this class maps to a built-in type.
        dkey = type_dispatch_key(cname)
        if dkey != nil
          emit_instruction(main_fn, {op: :type_class_register, dispatch_key: dkey, class_temp: cls_temp})

        # Per-kind node dispatch: AST [slab] classes register for their
        # kind id so packed nodes route to the specialized class. The
        # kind symbol comes from the constructor-return-type map
        # (register_ast_constructor_return_types); kind_id_table turns
        # it into the integer the runtime indexes by.
        ast_kind_sym = mod[:fn_return_types][cname + ".new"]
        if ast_kind_sym != nil && kind_id_table[ast_kind_sym] != nil
          emit_instruction(main_fn, {op: :node_kind_class_register, kind_id: kind_id_table[ast_kind_sym], class_temp: cls_temp})

        # Inherit superclass ivar offsets for this class's fresh layout.
        # Use the namespace-resolved super_name so a cross-file parent's
        # ivar layout is found (bare expr.superclass may not be a key).
        ivar_offsets = {}
        offset = 0
        if super_name != nil && mod[:known_classes][super_name] != nil
          super_node = mod[:known_classes][super_name]
          super_offsets = ast_get(super_node, :ivar_offsets)
          if super_offsets != nil
            super_keys = super_offsets.keys()
            ski = 0
            while ski < super_keys.size()
              k = super_keys[ski]
              ivar_offsets[k] = super_offsets[k]
              if super_offsets[k] >= offset
                offset = super_offsets[k] + 1
              ski += 1
        processed_classes[cname] = {ivar_offsets: ivar_offsets, offset: offset}

      ivar_state = processed_classes[cname]
      ivar_offsets = ivar_state[:ivar_offsets]
      offset = ivar_state[:offset]
      class_body = expand_class_traits(mod, expr.body)
      class_body = expand_class_body_accessors(class_body)
      # Apply the same typed-overload rewrite lower_class_def uses, so the
      # synthesized worker methods (`*__ovl_Vec3`, …) and the dispatcher get
      # registered here. The transform is deterministic, so the method names
      # registered match the function names lower_class_def later defines.
      class_body = synthesize_overload_dispatchers(mod, cname, class_body)

      # Phase 6i follow-up: populate view_layouts in this pre-pass so that
      # specialize_method's clone+re-lower (which can fire from user code
      # that runs BEFORE the class_def's own lower_class_def) finds the
      # layout when resolving `$field` accesses inside cloned method bodies.
      vfields = collect_view_fields(class_body)
      if vfields != nil
        if mod[:view_layouts] == nil
          mod[:view_layouts] = {}
        mod[:view_layouts][cname] = vfields

      # Append any local ivars not already present (additive on reopen).
      local_ivars = collect_class_ivars(class_body)
      li = 0
      while li < local_ivars.size()
        iname = local_ivars[li]
        if ivar_offsets[iname] == nil
          ivar_offsets[iname] = offset
          offset = offset + 1
          ivar_str_id = module_string_constant(mod, iname)
          ivar_byte_len = utf8_byte_length(iname) + 1
          cls_reload = next_temp(main_fn)
          emit_instruction(main_fn, {op: :load_class, temp: cls_reload, class_name: cname})
          emit_instruction(main_fn, {op: :class_add_ivar, class_temp: cls_reload, ivar_str_id: ivar_str_id, ivar_byte_len: ivar_byte_len})
        li += 1
      processed_classes[cname] = {ivar_offsets: ivar_offsets, offset: offset}

      # Propagate the merged layout to the canonical class_node so later
      # lowering stages (which look up ivar offsets via known_classes) see
      # the same picture regardless of which class_def is canonical.
      canonical = mod[:known_classes][cname]
      if canonical != nil
        ast_set(canonical, :ivar_offsets, ivar_offsets)
        ast_set(canonical, :ivar_count, offset)

      # Register methods and accessors from THIS body.
      if class_body != nil
        mi2 = 0
        while mi2 < class_body.size()
          mnode = class_body[mi2]
          if ast_kind(mnode) == :method_def
            # Record class methods that take a block (declare `&` or use
            # `yield`) in the global block-method name set, exactly as the
            # top-level fn-def walk does. Without this, a trailing block on
            # an instance call to a yielding method (`box.configure -> …`)
            # was mis-routed by method_takes_no_block? into an implicit
            # `.each` on the RESULT, so the method ran with no block and
            # `yield` died with "expected closure".
            if method_lowering_analysis(mnode)[:yield_block_name] != nil || explicit_block_param_name(mnode.params) != nil
              mod[:block_method_names][mnode.name] = true
            if mnode.is_class_method == true
              register_static_method(main_fn, mod, cname, mnode)
              if mnode.return_type != nil
                static_rt = normalize_type_symbol(mnode.return_type)
                static_key = cname + "." + mnode.name
                mod[:fn_return_types][static_key] = static_rt
                mod[:known_static_methods][static_key][:return_type] = static_rt
            else
              register_class_method_def(main_fn, mod, cname, mnode)
              # `-> new(@x, @y) ro` — a bare ro/rw body statement generates
              # accessors for the @-bound params (lower_class_def emits the
              # bodies via desugar_trailing_accessors; this pre-pass makes
              # dispatch see the symbols, mirroring the class-body ro arm).
              if mnode.body != nil
                tmi = 0
                while tmi < mnode.body.size()
                  tst = mnode.body[tmi]
                  if is_ast_node?(tst) && ast_kind(tst) == :call && tst.receiver == nil && (ast_get(tst, :name) == "ro" || ast_get(tst, :name) == "rw") && (tst.args == nil || tst.args.size() == 0)
                    tpi = 0
                    while tpi < mnode.params.size()
                      tp = mnode.params[tpi]
                      if ast_get(tp, :ivar_assign) == true
                        register_class_method(main_fn, mod, cname, ast_get(tp, :name), 1)
                        if ast_get(tst, :name) == "rw"
                          register_class_method(main_fn, mod, cname, ast_get(tp, :name) + "=", 2)
                      tpi += 1
                  tmi += 1
              # Type-annotated instance methods get a static-dispatch
              # entry so `self.foo()` calls inside the same class
              # bypass w_method_call_cached. We populate the registry
              # dict directly rather than calling register_static_method
              # (which has class-method-only side effects). `fn`-defined
              # methods (mnode.from_fn == true) also get a memo table
              # — same caching behavior as top-level fn defs.
              if mnode.return_type != nil
                static_rt = normalize_type_symbol(mnode.return_type)
                static_key = cname + "." + mnode.name
                inst_fn_name = class_method_function_name(cname, mnode)
                inst_raw_abi = static_method_raw_abi?(mnode)
                mod[:fn_return_types][static_key] = static_rt
                mod[:known_static_methods][static_key] = {
                  fn_name: inst_fn_name,
                  method_fn_name: inst_fn_name,
                  arity: method_runtime_arity(mnode),
                  return_type: static_rt,
                  param_types: normalized_static_param_types(mnode),
                  raw_abi: inst_raw_abi,
                  from_fn: mnode.from_fn == true
                }
                if mnode.from_fn == true
                  impure_ccall = fn_body_calls_impure_ccall?(mnode.body)
                  mnode.calls_impure_ccall = impure_ccall
                  if !impure_ccall
                    mod[:known_pure_calls][static_key] = inst_fn_name
                    if mod[:fn_memo_tables][static_key] == nil
                      mod[:fn_memo_tables][static_key] = inst_fn_name + ".memo"
                      mod[:fn_memo_table_order].push(static_key)
          elsif ast_kind(mnode) == :call && mnode.name in ("ro" "rw")
            ai = 0
            while ai < mnode.args.size()
              field = mnode.args[ai].value
              register_class_method(main_fn, mod, cname, field, 1)
              if mnode.name == "rw"
                register_class_method(main_fn, mod, cname, field + "=", 2)
              ai += 1
          elsif ast_kind(mnode) == :view_decl && ast_get(mnode, :kind) == "struct"
            # Data block (`- data; T components[4]`) — register a method
            # per field so bare `components` resolves at dispatch time.
            # lower_class_def emits the corresponding getter body; this
            # pre-pass just ensures runtime dispatch sees the symbol.
            vd_layout = ast_get(mnode, :count)
            if vd_layout != nil && type(vd_layout) == "Hash" && vd_layout[:fields] != nil
              vdf = 0
              while vdf < vd_layout[:fields].size()
                vfname = vd_layout[:fields][vdf][:name]
                register_class_method(main_fn, mod, cname, vfname, 1)
                vdf += 1
          mi2 += 1
    ci += 1
  # Phase 5 (gap #2): pre-pass over class method ASTs to collect ivar
  # types, so dispatch on `self.@arr.method()` can specialize when
  # @arr is statically typed. Runs after all class methods are
  # registered (mod[:class_method_asts] populated) so cross-method
  # ivar writes are visible.
  collect_ivar_types(mod)

  # Phase 6e v0: AST-level escape pre-pass for SmallArray.new at top
  # level. Non-recursive (no nested-body walks); flips the # stack
  # annotation default to "on" for safe top-level patterns.
  mark_nonescaping_small_arrays(ast.expressions)

  if verbose
    << "  lowering..."
  lower_program(ctx, ast.expressions)

  # Initialize memo tables only for pure fns that are actually called.
  prepend_memo_table_initializers(main_fn, mod)

  if verbose
    << ""
    << "  done (" + mod[:functions].size().to_s() + " functions)"

  # Register custom units (if any were assigned during lowering)
  # Prepend to main function so they run before any quantity display
  if ctx[:custom_units] != nil
    cu_keys = ctx[:custom_units].keys().sort()
    reg_instructions = []
    cui = 0
    while cui < cu_keys.size()
      unit_name = cu_keys[cui]
      unit_id = ctx[:custom_units][unit_name]
      str_id = module_string_constant(mod, unit_name)
      byte_len = utf8_byte_length(unit_name) + 1
      reg_instructions.push({op: :register_unit, unit_id: unit_id, str_id: str_id, byte_len: byte_len})
      cui += 1
    main_fn[:instructions] = reg_instructions + main_fn[:instructions]

  # Drain any pending goroutines before main exits.
  # If no goroutines were spawned, the run queue is empty and this returns immediately.
  # If the HTTP server's scheduler is running (persistent mode), main never reaches here.
  if !block_terminated(main_fn)
    # Unconditional by design, not oversight: (1) language semantics — main
    # DRAINS pending goroutines before exit (unlike Go, where main's return
    # kills them); (2) servers depend on it — an http accept loop RUNS INSIDE
    # this end-of-main scheduler loop (g_scheduler_persistent), and goroutines
    # can be enqueued from C (http/channels/timers) without w_goroutine_spawn
    # appearing in this module's IR, so an IR probe could not gate it safely;
    # (3) it costs ~nothing — the first line of w_scheduler_run returns when
    # no goroutine was ever spawned (two global loads).
    emit_instruction(main_fn, {op: :call_direct_void, name: "w_scheduler_run", args: []})

  finalize_function(main_fn)
  mod

# -- Variables --

# Ruby-style namespace walk-up for an unqualified class reference.
# `enclosing` is the fully-qualified name of the class (or namespace
# path) the reference sits inside, e.g. "Tungsten:Bit:Commands:Help".
# Drop the trailing simple name to recover the namespace, then look for
# `<ns>:name`, `<parent-ns>:name`, … in mod[:known_classes], returning
# the first qualified match (nil if none). This mirrors the parser's
# same-file superclass walk-up (parser.w) but resolves ACROSS files,
# because mod[:known_classes] is module-global by the time lowering
# runs. First-declaration wins; unmatched names return nil so the
# caller falls through to its existing behavior.
-> resolve_class_in_namespace(mod, enclosing, name)
  if enclosing == nil
    return nil
  segments = enclosing.split(":")
  segments.pop()
  while segments.size() > 0
    candidate = segments.join(":") + ":" + name
    if mod[:known_classes][candidate] != nil
      return candidate
    segments.pop()
  nil

# Materialize all temp bindings to var slots. Called before control flow
# (if, while, case, etc.) and closures so that cross-block reads and
# capture analysis find values in var_slots.
-> lower_var(ctx, node)
  name = node.name
  wfn = ctx[:func]

  # Build-time defines (`bin/tungsten -D NAME=VALUE`) win over any other
  # binding. Emit the corresponding nanboxed i64 literal directly so the
  # value is a compile-time constant — `if FAST_MATH` after substitution
  # becomes `if w_true` (a literal i64), which LLVM's SimplifyCFG passes
  # fold into an unconditional branch with no global load.
  #
  # Value parsing order:
  #   "true" / "false"   → boolean (w_true / w_false)
  #   /^-?[0-9]+$/       → integer (w_int(N))
  #   "..." / '...'      → string (quotes stripped)
  #   anything else      → string (raw token, e.g. -D BACKEND=metal)
  define_val = ctx[:mod][:build_defines][name]
  if define_val != nil
    if define_val == "true"
      return typed_value(:i64, w_true.to_s())
    if define_val == "false"
      return typed_value(:i64, w_false.to_s())
    if build_define_is_int?(define_val)
      # Construct the nanboxed i64 literal directly: w_tag_int (0xFFFA...) ORed
      # with the i48 payload. No w_int() helper exists at compile time — the
      # runtime symbol is C-only. Mirrors lower_build_define_string's SSO-5
      # construction, just with the int tag instead of the string tag.
      return typed_value(:i64, wvalue_literal_text(w_tag_int + define_val.to_i()))
    # String: strip optional surrounding quotes (shell may or may not have
    # stripped them, depending on how the user quoted on the CLI).
    str_val = define_val
    if str_val.size() >= 2
      first = str_val.slice(0, 1)
      last = str_val.slice(str_val.size() - 1, 1)
      if first == "\"" && last == "\""
        str_val = str_val.slice(1, str_val.size() - 2)
      elsif first == "'" && last == "'"
        str_val = str_val.slice(1, str_val.size() - 2)
    return lower_build_define_string(ctx, str_val)

  # Bare `class` inside a method body resolves to the class, so the
  # constructor pattern `class.new(args)` produces an instance of the
  # receiver's concrete class regardless of which specialization is active
  # (Quaternion$f32, Quaternion$f64, …). In an INSTANCE method `__self` is
  # an instance, so `class` is its runtime class via w_class_of. In a CLASS
  # method `__self` IS already the class — taking w_class_of there would
  # yield the metaclass, so `class.new` (e.g. Mat3.identity / Mat3.zero)
  # would build a `Class`, not a `Mat3`. Gated on `method_name != nil` to
  # avoid clobbering top-level contexts where `class` is a dispatch target.
  if name == "class" && ctx[:class_name] != nil && ctx[:method_name] != nil
    if ctx[:is_class_method] == true
      # __self IS the class here. Reference the parameter directly rather
      # than routing through lower_var("__self"): a captured __self gets a
      # var-slot/binding whose load can land in a different basic block,
      # leaving a dangling SSA ref at the call site (seen in dead, never-
      # instantiated template static methods). The entry param dominates
      # every block, so it's always valid.
      return typed_value(:i64, "%__self")
    self_tv = lower_expression(ctx, Tungsten:AST:Var.new("__self"))
    self_reg = ensure_i64_value(wfn, self_tv)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "w_class_of", args: [self_reg]})
    return typed_value(:i64, temp)

  # Phase 6i follow-up: bare `$field` inside a class method is a view-field
  # access on `self`. The lexer emits `$<name>` as a :GLOBAL token which
  # the parser turns into `Tungsten:AST:Var.new("$field")`. Resolve here
  # by looking the bare name up in the class's view_layouts and routing
  # to lower_view_field. Without this, $size etc. fall through to method
  # dispatch and fail at runtime with "undefined method '$size'".
  if name.starts_with?("$") && ctx[:class_name] != nil
    field = name.slice(1, name.size() - 1)
    # $value is the bare 64-bit content of self — works for any class,
    # not just classes with a heap view layout. Tag the result as
    # :raw_i64 so subsequent `>>` / `&` lower to raw machine ops rather
    # than dispatch through the receiver's tag class.
    if field == "value"
      self_tv = lower_var(ctx, Tungsten:AST:Var.new("__self"))
      self_reg = ensure_i64_value(wfn, self_tv)
      return typed_value(:raw_i64, self_reg)
    info = view_field_info(ctx, field)
    if info != nil
      return lower_view_field(ctx, Tungsten:AST:ViewField.new(field))

  raw_type = ctx[:var_types][name]
  machine_int = is_raw_int_storage_type(raw_type)
  machine_float = is_machine_float_type(raw_type)
  top_level_raw_type = nil
  if ctx[:mod][:top_level_var_types] != nil
    top_level_raw_type = ctx[:mod][:top_level_var_types][name]

  # Unboxed loop variable: load raw, return as :raw_i64. Phase 2
  # (2026-04-15): must be :raw_i64, NOT :raw_int, because under
  # silent-wrap native arithmetic the accumulated value can exceed
  # the 48-bit nanbox payload range. :raw_i64 routes boundary-crossing
  # boxing through w_int (bigint-safe), while :raw_int would mask to
  # 48 bits and produce garbage for sums like 0..99999999.
  if ctx[:unboxed_vars] != nil && ctx[:unboxed_vars][name] != nil
    raw_slot = ctx[:unboxed_vars][name]
    raw = next_temp(wfn)
    emit_instruction(wfn, {op: :load_i64, temp: raw, ptr: raw_slot})
    return typed_value(:raw_i64, raw)


  # Check var slot before bindings/parameters — once a name is materialized, the slot
  # becomes the source of truth (important for reassigned params with defaults).
  ptr = wfn[:var_slots][name]
  if ptr != nil
    temp = next_temp(wfn)
    load_op = :load_i64
    if machine_int
      load_op = machine_load_op(raw_type)
    elsif machine_float
      load_op = float_load_op(raw_type)
    emit_instruction(wfn, {op: load_op, temp: temp, ptr: ptr})
    if machine_int
      return typed_value(raw_machine_value_type(raw_type), temp)
    if machine_float
      return typed_value(raw_float_value_type(raw_type), temp)
    return typed_value(:i64, temp)

  # Check temp bindings next (covers default-param overrides and register renames)
  binding = ctx[:bindings][name]
  if binding != nil
    if machine_int
      return typed_value(raw_machine_value_type(raw_type), binding)
    if machine_float
      return typed_value(raw_float_value_type(raw_type), binding)
    return typed_value(:i64, binding)

  # Check if it's a parameter (directly available as %name)
  i = 0
  while i < wfn[:params].size()
    if wfn[:params][i] == name
      if machine_int
        # Raw-ABI fns (raw_i64_signature) receive machine-int params as raw
        # bits, not nanboxed WValues. When the entry binding for such a param
        # has been dropped (e.g. materialize_bindings / loop-end binding reset
        # inside a `loop`/`while true` body), reading it must reconstruct the
        # RAW param register directly — applying w_to_i64 to a raw pointer or
        # int corrupts it ("expected int, got object"). Boxed-ABI fns keep the
        # nanunbox path below.
        if wfn[:raw_i64_signature] == true
          return typed_value(raw_machine_value_type(raw_type), cast_raw_machine_int(wfn, "%" + name, :i64, raw_type))
        return typed_value(raw_machine_value_type(raw_type), ensure_raw_machine_int(wfn, typed_value(:i64, "%" + name), raw_type, raw_type))
      if machine_float
        if raw_type in (:f32 :raw_f32)
          return typed_value(:raw_f32, ensure_raw_f32(wfn, typed_value(:i64, "%" + name)))
        return typed_value(:raw_f64, ensure_raw_f64(wfn, typed_value(:i64, "%" + name)))
      return typed_value(:i64, "%" + name)
    i += 1

  # Check if it's a built-in runtime class
  if mark_builtin_class_used(ctx[:mod], name)
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :load_class, temp: temp, class_name: name})
    return typed_value(:i64, temp)

  # Check if it's a class name (user-defined)
  if ctx[:mod][:known_classes][name] != nil
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :load_class, temp: temp, class_name: name})
    return typed_value(:i64, temp)

  # Unqualified class reference resolved via the enclosing namespace
  # chain (Ruby-style). A bare `Clean` inside a method of
  # `Tungsten:Bit:Commands:Help` resolves to
  # `Tungsten:Bit:Commands:Clean`; a bare `Bitfile` walks further up to
  # `Tungsten:Bit:Bitfile`. Only reached when the name is not a local,
  # parameter, builtin class, or exact top-level class, so it is purely
  # additive — it rescues references that would otherwise fall through to
  # implicit-self dispatch (and fail) or resolve to nil.
  if !name.include?(":") && ctx[:class_name] != nil
    ns_resolved = resolve_class_in_namespace(ctx[:mod], ctx[:class_name], name)
    if ns_resolved != nil
      temp = next_temp(wfn)
      emit_instruction(wfn, {op: :load_class, temp: temp, class_name: ns_resolved})
      return typed_value(:i64, temp)

  # Built-in constants
  if name == "ARGV"
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: "__w_argv", args: []})
    return typed_value(:i64, temp)

  # Check if it's a top-level (module-scope) variable
  if ctx[:mod][:top_level_vars][name] == true
    temp = next_temp(wfn)
    # Match the load width to the global's storage width. i128/u128
    # globals (`## u128` / `## i128`) need `load i128`; otherwise the
    # IR is a type-mismatch.
    load_type = "i64"
    if is_machine_int128_type(top_level_raw_type)
      load_type = "i128"
    emit_instruction(wfn, {op: :load_global, temp: temp, name: name, type: load_type})
    if is_raw_int_storage_type(top_level_raw_type)
      return typed_value(raw_machine_value_type(top_level_raw_type), temp)
    if machine_int
      return typed_value(raw_machine_value_type(raw_type), ensure_raw_machine_int(wfn, typed_value(:i64, temp), raw_type, raw_type))
    return typed_value(:i64, temp)

  # Zero-arg function call: bare `greet` → call __w_greet()
  call_target = ctx[:mod][:known_calls][name]
  if call_target != nil
    temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: temp, name: call_target, args: []})
    if call_target == "__w_exit"
      emit_instruction(wfn, {op: :unreachable})
    return typed_value(:i64, temp)

  # Implicit self dispatch: inside a class method, bare `foo` resolves as a
  # direct static call on the current class when such a method is known.
  if ctx[:is_class_method] == true && ctx[:class_name] != nil
    static_key = ctx[:class_name] + "." + name
    static_info = ctx[:mod][:known_static_methods][static_key]
    if static_info != nil && static_info[:arity] == 1
      return lower_direct_static_method_call(ctx, static_info, Tungsten:AST:Self.new, [])

  # Δ-prefixed identifier: an UNDEFINED `Δx` means "my x minus theirs" —
  # it desugars to `x - x'` = `x - @1.x` (prime-notation delta, README's
  # `√(Δx² + Δy² + Δz²)`). A real variable named Δx resolves through the
  # normal paths above; this must sit BEFORE the blind implicit-self
  # dispatch below, which would otherwise claim Δx as self.Δx(). The Δ
  # prefix is therefore reserved: a class method literally named Δx is
  # shadowed by the delta reading.
  if name.starts_with?("Δ") && name.size() > "Δ".size()
    dlen = "Δ".size()
    delta_base = name.slice(dlen, name.size() - dlen)
    delta_node = Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(delta_base), :MINUS, Tungsten:AST:Call.new(Tungsten:AST:Parg.new(1), delta_base, [], nil))
    return lower_expression(ctx, delta_node)

  # Implicit self dispatch: inside a class, bare `foo` resolves as self.foo().
  # This handles accessor methods (ro/rw) and any zero-arg instance method.
  if ctx[:class_name] != nil
    self_val = lower_var(ctx, Tungsten:AST:Var.new("__self"))
    self_reg = ensure_i64_value(wfn, self_val)
    method_name_tv = lower_string(ctx, Tungsten:AST:String.new(name))
    method_name_val = ensure_i64_value(wfn, method_name_tv)
    temp_args = next_temp(wfn)
    temp = next_temp(wfn)
    ic_id = ctx[:mod][:next_ic]
    ctx[:mod][:next_ic] = ic_id + 1
    emit_instruction(wfn, {
      op: :call_method_i64,
      temp: temp,
      temp_args_val: temp_args,
      receiver: self_reg,
      method_name_val: method_name_val,
      args: [],
      ic_id: ic_id
    })
    return typed_value(:i64, temp)

  # Undefined variable — treat as nil
  typed_value(:i64, w_nil.to_s())

# `$name` — always a real global read (@global.<name>), regardless of
# which function/method body it appears in. Contrast lower_var above,
# which only resolves to load_global once ctx[:mod][:top_level_vars]
# already has the name — true for a direct top-level :var assignment,
# but never for one inside a function/method body (see ast.w's GVar
# doc comment). A :gvar has no such gate: reading $foo unconditionally
# registers it as a global (idempotent — safe even if this read
# happens before any assignment ever runs) and loads it.
-> lower_gvar(ctx, node)
  name = node.name
  wfn = ctx[:func]

  # Phase 6i follow-up, preserved from lower_var's original $-prefix
  # handling (predating :gvar as a distinct AST kind): bare `$field`
  # inside a class method with a matching view-field layout is a
  # view-field access on `self`, not a global-variable read. Checked
  # first since it's the narrower case.
  if ctx[:class_name] != nil
    field = name.slice(1, name.size() - 1)
    if field == "value"
      self_tv = lower_var(ctx, Tungsten:AST:Var.new("__self"))
      self_reg = ensure_i64_value(wfn, self_tv)
      return typed_value(:raw_i64, self_reg)
    info = view_field_info(ctx, field)
    if info != nil
      return lower_view_field(ctx, Tungsten:AST:ViewField.new(field))

  ctx[:mod][:top_level_vars][name] = true
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :load_global, temp: temp, name: name, type: "i64"})
  typed_value(:i64, temp)

# Shared write-back for $name = value and $name += value alike (mirrors
# lower_ivar_set_expr's role for @ivar). Always the generic boxed
# path — see lower_gvar's doc comment for why a global never gets the
# raw-int/float storage optimizations a plain top-level :var can.
-> lower_gvar_set(ctx, name, val_tv)
  wfn = ctx[:func]
  val_reg = ensure_i64_value(wfn, val_tv)
  ctx[:mod][:top_level_vars][name] = true
  emit_store_global_unless_const(wfn, ctx, name, val_reg)
  typed_value(:i64, val_reg)

-> lower_assign_expr(ctx, node)
  wfn = ctx[:func]
  target = node.target

  # Ivar assignment: @name = value
  if ast_kind(target) == :ivar
    val = lower_expression(ctx, node.value)
    return lower_ivar_set_expr(ctx, target.name, val)

  # Class variable assignment: @@name = value
  if ast_kind(target) == :cvar
    val = lower_expression(ctx, node.value)
    return lower_cvar_set(ctx, target, val)

  # Global-variable assignment: $name = value. Unlike a bare :var (only
  # promoted to a real global when the assignment is directly at top
  # level, i.e. wfn[:name] == "main"), a :gvar assignment ALWAYS writes
  # through to @global.<name> regardless of which function/method body
  # it's in. Checked before `name = target.name` below so a $-prefixed
  # name never pollutes ctx[:var_types]/ctx[:bindings]/ctx[:unboxed_vars]
  # — those are per-function local-variable bookkeeping that a global
  # has no business appearing in.
  if ast_kind(target) == :gvar
    val = lower_expression(ctx, node.value)
    return lower_gvar_set(ctx, target.name, val)

  # Method-style assignment: recv.field = value → dispatch recv.field=(value)
  # rw accessors and any user method ending in `=` go through this path.
  if ast_kind(target) == :call && target.receiver != nil
    setter_call = Tungsten:AST:Call.new(target.receiver, target.name + "=", [node.value], nil)
    setter_call.loc = ast_get(target, :loc)
    return lower_method_call(ctx, setter_call)

  name = target.name

  # Flow compile-time quantity signatures through ordinary local bindings.
  # Reassignment to an unknown expression clears the fact conservatively.
  if ctx[:quantity_dimensions] == nil
    ctx[:quantity_dimensions] = {}
  ctx[:quantity_dimensions][name] = static_quantity_signature(ctx, node.value)

  # Range-elision (#49): stash range-literal RHS so a later `r.each ...`
  # substitutes the range expression at the call site and routes through
  # the with-loop fast path. Reassigning to a non-range value clears
  # the stash so we don't substitute a stale binding.
  if ctx[:range_bindings] == nil
    ctx[:range_bindings] = {}
  if node.value != nil && is_ast_node?(node.value) && ast_kind(node.value) == :range
    ctx[:range_bindings][name] = node.value
  else
    ctx[:range_bindings][name] = nil

  # Closure-escape Phase B (#61): stash block-literal RHS so a later
  # `arr.each(cb)` substitutes the block at the call site and inlines
  # via the existing .each handler. Same shape as range_bindings —
  # reassigning to a non-block value clears the stash. Conservative
  # escape model: we only consult this binding when the closure value
  # appears as the last arg of a known iter method and the receiver is
  # a fresh :var; the binding stays available for the closure's normal
  # call sites too (the closure allocation itself isn't elided here).
  if ctx[:closure_bindings] == nil
    ctx[:closure_bindings] = {}
  if node.value != nil && is_ast_node?(node.value) && ast_kind(node.value) == :block
    ctx[:closure_bindings][name] = node.value
    if ctx[:closure_noalloc_bindings] == nil
      ctx[:closure_noalloc_bindings] = {}
    if wfn[:name] != "main" && (closure_binding_no_escape?(ctx, name) || closure_binding_consumed_by_next_stmt?(ctx, name))
      ctx[:closure_noalloc_bindings][name] = true
  else
    ctx[:closure_bindings][name] = nil
    if ctx[:closure_noalloc_bindings] != nil
      ctx[:closure_noalloc_bindings][name] = nil

  target_type = ctx[:var_types][name]
  if node.type_hint != nil
    # Phase 4: `w64` is a synonym for the NaN-boxed WValue-int64 form.
    # Under the old semantics this was the default (unannotated) type,
    # but Phase 2 made raw i64 the unannotated default. Users who want
    # explicit boxed semantics annotate `## w64`, which maps to `:i64`
    # here (the internal symbol for boxed that pre-dates Phase 2's
    # full rename; the rename is deferred to a follow-up).
    hint_text = node.type_hint
    htl = hint_text.size()
    if hint_text == "w64"
      target_type = :i64
    elsif htl >= 3 && hint_text.slice(htl - 2, 2) == "\[]"
      # `## f32[]` / `## i32[]` / etc. — normalize the array-shaped hint
      # to the canonical :typed_array_<etype> symbol so element access
      # (`a[i]`) lowers via :typed_array_get_inline instead of
      # dispatching through generic Array#[]. Mirrors the param-hint
      # normalization in definitions.w.
      target_type = typed_array_etype_to_sym(hint_text.slice(0, htl - 2))
    elsif hint_text == "big" || hint_text == "bigint" || hint_text == "bignum"
      # Opt-in auto-promoting BigInt accumulator. Canonicalize all three
      # spellings to the single :bigint type so the value stays off the
      # native-i64 path and its arithmetic promotes (w_mul/w_add) instead
      # of wrapping. See is_bigint_type in lowering/types.w.
      target_type = :bigint
    else
      target_type = hint_text.to_sym()

  # Unboxed loop variable: store raw value directly
  if ctx[:unboxed_vars] != nil && ctx[:unboxed_vars][name] != nil
    val = lower_expression(ctx, node.value)
    raw_val = ensure_raw_int(wfn, val)
    raw_slot = ctx[:unboxed_vars][name]
    emit_instruction(wfn, {op: :store_i64, value: raw_val, ptr: raw_slot})
    return typed_value(:raw_int, raw_val)

  if ctx[:closure_noalloc_bindings] != nil && ctx[:closure_noalloc_bindings][name] == true && node.value != nil && is_ast_node?(node.value) && ast_kind(node.value) == :block
    return typed_value(:i64, w_nil.to_s())

  if is_raw_int_storage_type(target_type)
    raw_val = lower_machine_int_expression(ctx, node.value, target_type)
    ctx[:var_types][name] = target_type
    ctx[:bindings][name] = nil
    ptr = ensure_var_slot(wfn, name, machine_slot_type(target_type))
    emit_instruction(wfn, {op: machine_store_op(target_type), value: raw_val, ptr: ptr})
    if wfn[:name] == "main"
      ctx[:mod][:top_level_vars][name] = true
      ctx[:mod][:top_level_var_types][name] = target_type
      if ctx[:mod][:top_level_static_types] != nil
        ctx[:mod][:top_level_static_types][name] = target_type
      emit_store_global_unless_const(wfn, ctx, name, raw_val, machine_slot_type(target_type))
    return typed_value(raw_machine_value_type(target_type), raw_val)

  if is_machine_float_type(target_type)
    val = lower_expression(ctx, node.value)
    raw_val = nil
    if target_type in (:f32 :raw_f32)
      raw_val = ensure_raw_f32(wfn, val)
    else
      raw_val = ensure_raw_f64(wfn, val)
    ctx[:var_types][name] = target_type
    ctx[:bindings][name] = nil
    ptr = ensure_var_slot(wfn, name, float_slot_type(target_type))
    emit_instruction(wfn, {op: float_store_op(target_type), value: raw_val, ptr: ptr})
    if wfn[:name] == "main"
      ctx[:mod][:top_level_vars][name] = true
      ctx[:mod][:top_level_var_types][name] = nil
      if ctx[:mod][:top_level_static_types] != nil
        ctx[:mod][:top_level_static_types][name] = target_type
      boxed = ensure_i64_value(wfn, typed_value(raw_float_value_type(target_type), raw_val))
      emit_store_global_unless_const(wfn, ctx, name, boxed)
    return typed_value(raw_float_value_type(target_type), raw_val)

  val = lower_expression(ctx, node.value)
  inferred = nil
  if node.type_hint == nil
    inferred = infer_type(node.value, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
    machine_type = canonical_machine_int_type(inferred)
    typed_raw_machine_value = false
    raw_int_candidate = true
    if ctx[:raw_int_candidates] != nil && ctx[:raw_int_candidates][name] != true
      raw_int_candidate = false
    # Genuinely-typed raw machine values (:raw_i64/u64/i128/u128 from typed
    # sources) prove their own rawness, so they skip the conservative
    # candidate-map gate below.
    if machine_type == nil && val[:type] in (:raw_i64 :raw_u64 :raw_i128 :raw_u128)
      machine_type = raw_value_machine_type(val[:type])
      typed_raw_machine_value = true
    # :raw_int is the tag for BOTH ccall_nobox results AND plain int literals
    # (`0`). The literal case must still respect the candidate gate: an
    # escaping accumulator seeded `= 0` (e.g. `dot/1 0` summing floats via an
    # each_with_index closure) is not a raw-int candidate, so promoting it to
    # a raw :i64 slot here would make a later `acc += <float>` coerce the
    # float through w_to_i64 and die ("expected int, got numeric").
    elsif machine_type == nil && val[:type] == :raw_int && raw_int_candidate
      machine_type = raw_value_machine_type(:raw_int)
      typed_raw_machine_value = true
    if machine_type != nil && (raw_int_candidate || typed_raw_machine_value) && ctx[:bindings][name] == nil && wfn[:var_slots][name] == nil
      raw_val = ensure_raw_machine_int(wfn, val, machine_type, inferred)
      ctx[:var_types][name] = machine_type
      ctx[:bindings][name] = nil
      ptr = ensure_var_slot(wfn, name, machine_slot_type(machine_type))
      emit_instruction(wfn, {op: machine_store_op(machine_type), value: raw_val, ptr: ptr})
      if wfn[:name] == "main"
        ctx[:mod][:top_level_vars][name] = true
        ctx[:mod][:top_level_var_types][name] = machine_type
        if ctx[:mod][:top_level_static_types] != nil
          ctx[:mod][:top_level_static_types][name] = machine_type
        emit_store_global_unless_const(wfn, ctx, name, raw_val, machine_slot_type(machine_type))
      return typed_value(raw_machine_value_type(machine_type), raw_val)

    if (inferred == :float || inferred == :f64) && ctx[:bindings][name] == nil && wfn[:var_slots][name] == nil
      raw_val = ensure_raw_f64(wfn, val)
      ctx[:var_types][name] = inferred
      ctx[:bindings][name] = nil
      ptr = ensure_var_slot(wfn, name, "double")
      emit_instruction(wfn, {op: :store_double, value: raw_val, ptr: ptr})
      if wfn[:name] == "main"
        ctx[:mod][:top_level_vars][name] = true
        ctx[:mod][:top_level_var_types][name] = nil
        if ctx[:mod][:top_level_static_types] != nil
          ctx[:mod][:top_level_static_types][name] = inferred
        boxed = ensure_i64_value(wfn, typed_value(:raw_f64, raw_val))
        emit_store_global_unless_const(wfn, ctx, name, boxed)
      return typed_value(:raw_f64, raw_val)

  val_reg = ensure_i64_value(wfn, val)

  # Track type for optimization — explicit hint takes priority over inference
  if node.type_hint != nil
    ctx[:var_types][name] = target_type
  else
    if inferred != nil
      # Type tracking is function-wide rather than control-flow-sensitive.
      # Once a local has been materialized as a boxed WValue, a later integer
      # assignment in another branch must not make reads treat that boxed slot
      # as raw machine bits.
      existing_boxed_local = wfn[:var_slots][name] != nil || ctx[:bindings][name] != nil
      raw_int_candidate = true
      if ctx[:raw_int_candidates] != nil && ctx[:raw_int_candidates][name] != true
        raw_int_candidate = false
      if is_bigint_type(target_type) && !is_bigint_type(inferred)
        # Sticky BigInt: a `## big` accumulator stays :bigint across
        # reassignments (`f = f * i`) so every iteration keeps routing
        # through the promoting w_mul path. Re-narrowing it to :int here
        # would re-enable native-wrap unboxing on a later loop pass and
        # silently corrupt the running product. (Mirrors how machine-int
        # stickiness is preserved at collect_top_level_static_types.)
        nil
      elsif is_raw_int_storage_type(inferred) && !raw_int_candidate
        # Inside a `Math.promote / trap / wrap` block, a boxed integer local
        # must carry an :int type so its +/-/* reads route through the guarded
        # overflow path (promote/trap) or explicit native wrap in
        # lower_binary_op, instead of the generic polymorphic w_* fallback
        # (which would silently promote and make trap impossible). :int is a
        # BOXED integer type, so reads still box via ensure_i64_value — no
        # raw-machine-bits hazard, which is why the default (non-block) path
        # deliberately leaves it unset here.
        if ctx[:overflow_mode] != nil
          ctx[:var_types][name] = :int
      elsif existing_boxed_local && (is_raw_int_storage_type(inferred) || is_machine_float_type(inferred))
        # Once a local is a materialized boxed WValue, a later machine-int OR
        # machine-FLOAT inference (e.g. `if c: v = ~0.0` on a v already holding a
        # boxed Float) must not retype the slot — reads would `load double` the
        # boxed i64 bits and corrupt it (2.0 -> 2.125 in the NaN-box tag bits).
        nil
      else
        ctx[:var_types][name] = inferred

  # If variable already has a var slot (was materialized), store to it
  ptr = wfn[:var_slots][name]
  if ptr != nil
    emit_instruction(wfn, {op: :store_i64, value: val_reg, ptr: ptr})
    # Top-level assignments also store to globals for cross-function access
    if wfn[:name] == "main"
      ctx[:mod][:top_level_vars][name] = true
      ctx[:mod][:top_level_var_types][name] = nil
      if ctx[:mod][:top_level_static_types] != nil
        if node.type_hint != nil
          ctx[:mod][:top_level_static_types][name] = target_type
        else
          ctx[:mod][:top_level_static_types][name] = inferred
      emit_store_global_unless_const(wfn, ctx, name, val_reg)
    return typed_value(:i64, val_reg)

  # Otherwise track as a temp binding (register rename, no alloca)
  ctx[:bindings][name] = val_reg

  # Top-level assignments also store to globals for cross-function access
  if wfn[:name] == "main"
    ctx[:mod][:top_level_vars][name] = true
    ctx[:mod][:top_level_var_types][name] = nil
    if ctx[:mod][:top_level_static_types] != nil
      if node.type_hint != nil
        ctx[:mod][:top_level_static_types][name] = target_type
      else
        ctx[:mod][:top_level_static_types][name] = inferred
    emit_store_global_unless_const(wfn, ctx, name, val_reg)

  typed_value(:i64, val_reg)

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

  # Phase 6f follow-up: classes that share the W_SUBTAG_GENERIC subtag
  # (BigArray — keyed at 0x80|W_TYPE_*) embed a `type` byte at offset 0
  # of their heap struct as a secondary dispatch discriminator. The
  # .w data block describes the user-visible layout starting AFTER
  # that byte; add the implicit byte here so the gep lands on the
  # right field of the C struct. (Phase 6h: SmallArray promoted to
  # its own subtag and no longer carries this byte; its .w layout
  # starts directly at offset 0.)
  effective_offset = info[:offset]
  if class_uses_implicit_type_byte?(class_name)
    effective_offset = info[:offset] + 1

  temp = next_temp(wfn)
  emit_instruction(wfn, {
    op: :view_load_field, temp: temp, ptr: self_reg,
    offset: effective_offset, size: info[:size], field_type: info[:type]
  })
  if info[:type].starts_with?("*")
    return typed_value(:raw_i64, temp)
  typed_value(:i64, temp)

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
  emit_instruction(wfn, {
    op: :view_load_field, temp: temp, ptr: recv_reg,
    offset: effective_offset, size: info[:size], field_type: info[:type]
  })
  if info[:type].starts_with?("*")
    return typed_value(:raw_i64, temp)
  typed_value(:i64, temp)

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
# that the user-visible .w data block omits. Currently just BigArray
# (key 0x92). Subtag-promoted classes (SmallArray, Array, Atomic,
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
    emit_instruction(wfn, {op: :view_load_byte, temp: temp, ptr: self_reg, index: idx_raw})
  elsif view_name == "bits"
    emit_instruction(wfn, {op: :view_load_bit, temp: temp, ptr: self_reg, index: idx_raw})
  else
    emit_instruction(wfn, {op: :view_load_byte, temp: temp, ptr: self_reg, index: idx_raw})
  typed_value(:i64, temp)

-> lower_view_base(ctx)
  wfn = ctx[:func]
  self_tv = lower_var(ctx, Tungsten:AST:Var.new("__self"))
  self_reg = ensure_i64_value(wfn, self_tv)
  temp = next_temp(wfn)
  emit_instruction(wfn, {op: :view_base_ptr, temp: temp, value: self_reg})
  typed_value(:i64, temp)

-> lower_view_value(ctx)
  lower_var(ctx, Tungsten:AST:Var.new("__self"))

-> lower_multi_assign(ctx, node)
  wfn = ctx[:func]
  # Evaluate RHS (should produce an array)
  val = lower_expression(ctx, node.value)
  val_reg = ensure_i64_value(wfn, val)
  targets = node.targets
  i = 0
  while i < targets.size()
    target = targets[i]
    name = target.name
    # Get element i from the array
    idx_tv = lower_int(ctx, Tungsten:AST:Int.new(i))
    idx_reg = ensure_i64_value(wfn, idx_tv)
    elem_temp = next_temp(wfn)
    emit_instruction(wfn, {op: :call_direct_i64, temp: elem_temp, name: "w_array_get", args: [val_reg, idx_reg]})
    # Store to variable
    ensure_var_slot(wfn, name)
    slot = wfn[:var_slots][name]
    emit_instruction(wfn, {op: :store_i64, value: elem_temp, ptr: slot})
    i += 1
  typed_value(:i64, val_reg)

-> lower_safe_nav(ctx, node)
  wfn = ctx[:func]
  # Evaluate receiver
  recv_tv = lower_expression(ctx, node.receiver)
  recv_reg = ensure_i64_value(wfn, recv_tv)

  # Check if receiver is nil
  cmp_reg = next_temp(wfn)
  emit_instruction(wfn, {op: :icmp_ne_i64, temp: cmp_reg, lhs: recv_reg, rhs: w_nil.to_s()})

  not_nil_label = next_label(wfn, "safenav.nn")
  nil_label = next_label(wfn, "safenav.nil")
  merge_label = next_label(wfn, "safenav.mrg")

  emit_instruction(wfn, {op: :cond_br, cond: cmp_reg, then_label: not_nil_label, else_label: nil_label})

  # Not-nil branch: perform method call using the already-evaluated receiver
  start_block(wfn, not_nil_label)
  # Lower args
  arg_regs = []
  i = 0
  while i < node.args.size()
    val = lower_expression(ctx, node.args[i])
    arg_regs.push(ensure_i64_value(wfn, val))
    i += 1
  # Block if present
  sblk = node.block
  if sblk != nil && is_ast_node?(sblk)
    closure_tv = lower_block_closure(ctx, sblk)
    closure_reg = ensure_i64_value(wfn, closure_tv)
    arg_regs.push(closure_reg)
  # Emit method call — compute method name as WValue
  method_name = node.name
  method_name_tv = lower_string(ctx, Tungsten:AST:String.new(method_name))
  method_name_val = ensure_i64_value(wfn, method_name_tv)

  temp_args_val = next_temp(wfn)
  call_temp = next_temp(wfn)
  ic_id = ctx[:mod][:next_ic]
  ctx[:mod][:next_ic] = ic_id + 1

  emit_instruction(wfn, {
    op: :call_method_i64,
    temp: call_temp,
    temp_args_val: temp_args_val,
    receiver: recv_reg,
    method_name_val: method_name_val,
    args: arg_regs,
    ic_id: ic_id
  })
  call_from = wfn[:blocks][wfn[:blocks].size() - 1][:label]
  emit_instruction(wfn, {op: :br, label: merge_label})

  # Nil branch: return nil
  start_block(wfn, nil_label)
  nil_reg = w_nil.to_s()
  nil_from = nil_label
  emit_instruction(wfn, {op: :br, label: merge_label})

  # Merge with phi
  start_block(wfn, merge_label)
  result = next_temp(wfn)
  emit_instruction(wfn, {op: :phi_i64, temp: result, a_value: call_temp, a_label: call_from, b_value: nil_reg, b_label: nil_from})
  typed_value(:i64, result)

-> mangle_method_name(name)
  if name in ("[]" "\[]")
    return "_LB_RB"
  if name in ("[]=" "\[]=")
    return "_LB_RB_EQ"
  out = ""
  i = 0
  while i < name.size()
    ch = name[i]
    case ch
    when "?"
      out = out + "_Q"
    when "!"
      out = out + "_B"
    when "="
      out = out + "_EQ"
    when "<"
      out = out + "_LT"
    when ">"
      out = out + "_GT"
    when "+"
      out = out + "_PLUS"
    when "-"
      out = out + "_MINUS"
    when "*"
      out = out + "_STAR"
    when "/"
      out = out + "_SLASH"
    when "%"
      out = out + "_PERCENT"
    when "\["
      out = out + "_LB"
    when "\]"
      out = out + "_RB"
    else
      out = out + ch
    i += 1
  out

# -- Unsupported node handler --

# -- Emit WIRE flag: dump WIRE as text --

-> emit_wire_text(mod)
  out = "=== WIRE IR ===\n"
  out = out + "source: " + mod[:source_path] + "\n"
  out = out + "strings: " + mod[:strings].size().to_s() + "\n"
  out = out + "functions: " + mod[:functions].size().to_s() + "\n\n"

  i = 0
  while i < mod[:functions].size()
    wfn = mod[:functions][i]
    out = out + "function " + wfn[:name] + "("
    out = out + wfn[:params].join(", ")
    out = out + ") -> " + wfn[:return_type] + "\n"

    j = 0
    while j < wfn[:blocks].size()
      blk = wfn[:blocks][j]
      out = out + "  " + blk[:label] + ":\n"
      k = 0
      while k < blk[:instructions].size()
        inst = blk[:instructions][k]
        out = out + "    " + inst[:op].to_s()
        # Print key fields
        if inst[:temp] != nil
          out = out + " " + inst[:temp]
        if inst[:name] != nil
          out = out + " @" + inst[:name]
        if inst[:value] != nil
          out = out + " " + inst[:value].to_s()
        if inst[:label] != nil
          out = out + " %" + inst[:label]
        out = out + "\n"
        k += 1
      j += 1
    out = out + "\n"
    i += 1
  out
