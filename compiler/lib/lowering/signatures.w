# Lowering / signatures — type-signature normalization, overload keys,
# and method-name mangling shared by monomorphize, calls, and
# definitions.
#
# This file deliberately has no `use` directives — see pass_registry.w
# for the rationale (path resolution from compiler/lib/lowering/).

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

# Element name from `T[]` or fixed-size `T[N]` ascriptions. The size is a
# shape contract; the lowering type is the same typed-array family in either
# spelling. Return nil for scalars and malformed bracket text.
-> array_hint_element_type(t)
  if t == nil
    return nil
  text = t.to_s()
  open = text.index("\[")
  if open == nil || open == 0 || text.size() < open + 2
    return nil
  if text.slice(text.size() - 1, 1) != "\]"
    return nil
  text.slice(0, open)

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

# Static-method overloads are indexed by source argument count. Each value
# carries every registry key that legitimately points to it, turning a bad host
# Hash hit into a conservative miss instead of a cross-arity direct call.
-> register_known_static_method_info(mod, method_key, info, min_arg_count, max_arg_count)
  keys = [method_key]
  argc = min_arg_count
  while argc <= max_arg_count
    keys.push(method_key + "/" + argc.to_s())
    argc += 1
  info[:lookup_keys] = keys
  i = 0
  while i < keys.size()
    mod[:known_static_methods][keys[i]] = info
    i += 1
  info

-> static_info_has_lookup_key?(info, key)
  keys = info[:lookup_keys]
  if keys == nil
    legacy = info[:lookup_key]
    return legacy == nil || (legacy.size() == key.size() && legacy == key)
  i = 0
  while i < keys.size()
    if keys[i].size() == key.size() && keys[i] == key
      return true
    i += 1
  false

-> known_static_method_for(mod, key, arg_count = nil)
  if mod == nil || mod[:known_static_methods] == nil
    return nil
  registry_key = key
  if arg_count != nil
    registry_key = key + "/" + arg_count.to_s()
  info = mod[:known_static_methods][registry_key]
  # Hand-built compiler fixtures and embedders predate arity-indexed entries.
  # Accept their single legacy base-key record, but never fall back through a
  # modern overload set: those records carry lookup_keys and an argc miss must
  # remain a miss instead of selecting the last registered overload.
  if info == nil && arg_count != nil
    legacy = mod[:known_static_methods][key]
    if legacy != nil && legacy[:lookup_keys] == nil
      info = legacy
      registry_key = key
  if info != nil && !static_info_has_lookup_key?(info, registry_key)
    return nil
  info

-> mangle_method_name(name)
  if name in ("[]" "\[]")
    return "_LB_RB"
  if name in ("[]=" "\[]=")
    return "_LB_RB_EQ"
  out = ""
  chars = name.chars()
  i = 0
  while i < chars.size()
    ch = chars[i]
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
