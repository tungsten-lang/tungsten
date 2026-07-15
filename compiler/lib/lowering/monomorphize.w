# Lowering / monomorphize — Phase 5 typed-array specialization and the
# typed-array encoding helpers that drive method specialization.
# Depends on pass_registry.w and types.w.
#
# Includes:
#   - recv_type_variant_tag, mangled_specialized_name (name mangling)
#   - mark_nonescaping_small_arrays + the "is the array used safely?"
#     helpers (Phase 5g escape analysis)
#   - collect_ivar_types / walk_ivar_assigns (per-class ivar typing)
#   - specialize_method, specialize_method_with_inlined_block
#   - inline-yields rewrite (substitute_vars_in_ast, inline_yields_in_ast)
#   - typed_array_element_bits / signed / kernel_suffix
#   - ebits encoding (ebits_symbol_to_int, ebits_arg_to_raw,
#     ebits_const_value, small_array_payload_bytes,
#     typed_array_etype_to_sym)
#
# This file deliberately has no `use` directives — see pass_registry.w.


# Phase 5: monomorphization name mangling. Maps the receiver type symbol to
# a short, filesystem/symbol-safe variant tag used in the specialized
# function name. `:typed_array_u8` → `"u8"`, `:big_array_f32` → `"big_f32"`.
# Returns nil for non-array types (caller should bail to runtime dispatch).
-> recv_type_variant_tag(t)
  if t == nil
    return nil
  s = t.to_s()
  if s.starts_with?("typed_array_")
    return s.slice(12, s.size() - 12)
  if s == "typed_array"
    return "w64"
  if s.starts_with?("big_array_")
    return "big_" + s.slice(10, s.size() - 10)
  if s == "big_array"
    return "big_w64"
  if s.starts_with?("small_array_")
    return "small_" + s.slice(12, s.size() - 12)
  if s == "small_array"
    return "small_w64"
  nil

# Phase 5: build the mangled symbol for a specialized method instance.
# Format: __w_<Class>_<method>_<variant> (e.g. __w_Array_each_u8). Mirrors
# class_method_function_name's transformation of `::` → `__` for namespaced
# classes. `mangle_method_name` handles symbol-y characters in the name.
-> mangled_specialized_name(class_name, method_name, recv_type)
  variant = recv_type_variant_tag(recv_type)
  if variant == nil
    return nil
  "__w_" + class_name.gsub(":", "__") + "_" + mangle_method_name(method_name) + "_" + variant

# Phase 6e (v0): single-pass non-recursive escape pre-pass for SmallArray.new.
# Walks a single body (a flat list of statements), finds each assign of
# `var = SmallArray.new(:ebits, size_const)`, then scans the SAME body for
# subsequent uses of var. The classifier is intentionally minimal: each
# subsequent statement must either be a method call on var, an indexing
# of var, a print, or a statement that doesn't reference var at all.
# Anything else — return / ivar-store / call arg / block capture — is
# "unsafe" and the alloc stays on the heap. v0's safety guarantee: when
# in doubt, the alloc goes on the heap (correct).
-> mark_nonescaping_small_arrays(body)
  if body == nil
    return nil
  if type(body) != "Array"
    return nil
  i = 0
  while i < body.size()
    stmt = body[i]
    if is_small_array_new_assign?(stmt)
      var_name = stmt.target.name
      if all_subsequent_uses_safe?(body, i + 1, var_name)
        stmt.value.stack_safe = true
    i += 1
  nil

-> is_small_array_new_assign?(stmt)
  if !is_ast_node?(stmt)
    return false
  if ast_kind(stmt) != :assign
    return false
  if stmt.target == nil
    return false
  if ast_kind(stmt.target) != :var
    return false
  val = stmt.value
  if val == nil
    return false
  if ast_kind(val) != :call
    return false
  if val.name != "new"
    return false
  recv = val.receiver
  if recv == nil
    return false
  if recv.name != "SmallArray"
    return false
  if val.args == nil
    return false
  if val.args.size() != 2
    return false
  if ebits_const_value(val.args[0]) == nil
    return false
  size_arg = val.args[1]
  if ast_kind(size_arg) != :int
    return false
  if size_arg.value < 0
    return false
  if size_arg.value > 255
    return false
  true

-> all_subsequent_uses_safe?(body, start_idx, var_name)
  i = start_idx
  while i < body.size()
    if !stmt_safe_for_var?(body[i], var_name)
      return false
    i += 1
  true

-> stmt_safe_for_var?(stmt, var_name)
  if stmt == nil
    return true
  if !is_ast_node?(stmt)
    return true
  nt = ast_kind(stmt)
  if nt == :var && stmt.name == var_name
    return false
  if nt == :call
    return call_stmt_safe_for_var?(stmt, var_name)
  if nt == :puts
    return true
  if nt == :print
    return true
  if nt == :assign
    return assign_stmt_safe_for_var?(stmt, var_name)
  if nt == :return
    return !stmt_value_is_var?(stmt.value, var_name)
  if nt == :yield
    return !stmt_value_is_var?(stmt.value, var_name)
  if nt == :ivar_set
    return !stmt_value_is_var?(stmt.value, var_name)
  # Top-level class/trait/method/fn definitions get their own scope and
  # don't auto-capture sibling locals. Safe by construction.
  if nt == :class_def
    return true
  if nt == :module_def
    return true
  if nt == :trait_def
    return true
  if nt == :method_def
    return true
  if nt == :fn_def
    return true
  if nt == :use
    return true
  if nt == :require
    return true
  false

-> stmt_value_is_var?(node, var_name)
  if node == nil
    return false
  if !is_ast_node?(node)
    return false
  if ast_kind(node) != :var
    return false
  node.name == var_name

-> call_stmt_safe_for_var?(stmt, var_name)
  args = stmt.args
  if args != nil
    ai = 0
    while ai < args.size()
      if stmt_value_is_var?(args[ai], var_name)
        return false
      ai += 1
  if stmt.block != nil
    return false
  true

-> assign_stmt_safe_for_var?(stmt, var_name)
  target = stmt.target
  if target == nil
    return true
  if ast_kind(target) == :ivar
    return !stmt_value_is_var?(stmt.value, var_name)
  if ast_kind(target) == :cvar
    return !stmt_value_is_var?(stmt.value, var_name)
  if ast_kind(target) == :var
    if stmt_value_is_var?(stmt.value, var_name)
      return false
    return true
  true

# Phase 5 (gap #2): walk every method body of every class, find ivar
# assignments, and record the inferred RHS type into mod[:ivar_types]
# [class_name][ivar_name]. Conflicting types across writes mark the ivar
# unknown (recorded as nil so dispatch bails to runtime). Pre-pass: runs
# AFTER all class methods are registered, BEFORE the lowering pass starts.
-> collect_ivar_types(mod)
  ivar_types = {}
  ivar_conflicts = {}
  ast_keys = mod[:class_method_asts].keys()
  ki = 0
  while ki < ast_keys.size()
    key = ast_keys[ki]
    dot_idx = key.index(".")
    cname = key.slice(0, dot_idx)
    method_ast = mod[:class_method_asts][key]
    if ivar_types[cname] == nil
      ivar_types[cname] = {}
      ivar_conflicts[cname] = {}
    walk_ivar_assigns(method_ast.body, cname, ivar_types, ivar_conflicts, mod)
    ki += 1
  # Conflicted ivars get nil-marked so the dispatch lookup bails cleanly.
  conflict_keys = ivar_conflicts.keys()
  ck = 0
  while ck < conflict_keys.size()
    cname = conflict_keys[ck]
    inner_keys = ivar_conflicts[cname].keys()
    ik = 0
    while ik < inner_keys.size()
      ivar_types[cname][inner_keys[ik]] = nil
      ik += 1
    ck += 1
  mod[:ivar_types] = ivar_types
  collect_exact_source_ivar_types(mod)

# Return the fully-qualified class name when `node` constructs an ordinary
# source WObject whose runtime class is exact. Runtime-backed classes, packed
# AST nodes, and source classes with a static `.new` override can all return a
# non-WObject representation, so they are deliberately excluded.
-> normal_source_instance_class?(mod, cname)
  if cname == nil
    return false
  class_node = mod[:known_classes][cname]
  if class_node == nil || !is_ast_node?(class_node) || ast_kind(class_node) != :class_def
    return false
  # These names are intercepted by lower_method_call/runtime construction and
  # produce native handles or packed storage even when their interface is a
  # source class_def. Keep this list aligned with the constructor fast paths.
  if cname in ("Atomic" "Channel" "Thread" "Response" "BigArray" "SmallArray" "ByteArray" "BoolArray")
    return false
  if mod[:builtin_class_names][cname] == true || type_dispatch_key(cname) != nil
    return false
  if mod[:fn_return_types][cname + ".new"] != nil
    return false
  if mod[:known_static_methods][cname + ".new"] != nil
    return false
  true

-> resolve_exact_source_class_name(mod, enclosing, name)
  if name == nil
    return nil
  cname = name
  if mod[:known_classes][cname] == nil
    cname = resolve_class_in_namespace(mod, enclosing, name)
  if normal_source_instance_class?(mod, cname)
    return cname
  nil

-> exact_source_class_from_value(node, enclosing, mod)
  if node == nil || !is_ast_node?(node)
    return nil
  if ast_kind(node) == :call && node.name == "new" && node.receiver != nil
    recv = node.receiver
    if is_ast_node?(recv) && ast_kind(recv) in (:var :class_ref)
      return resolve_exact_source_class_name(mod, enclosing, recv.name)
  nil

# This proof is intentionally separate from the general ivar type map above.
# Every write must prove the same exact ordinary source class; an unknown,
# compound, or destructuring write invalidates the fact for the entire class.
# An existing assignment type hint is accepted as the compiler/user contract
# for values recovered from containers (for example Interpreter's own saved
# Environment snapshot).
-> collect_exact_source_ivar_types(mod)
  exact_types = {}
  conflicts = {}
  # A method compiled for a parent may execute with a subclass receiver, so a
  # subclass-only writer can invalidate the parent's ivar fact. Conversely, a
  # child method can observe writes performed by inherited parent methods.
  # Until the proof is hierarchy-aware, conservatively exclude every class on
  # either end of an inheritance edge. `class_super_names` records the
  # namespace-resolved, first-declaration relationship used to create the
  # runtime class; later reopens cannot hide it.
  inheritance_classes = {}
  super_names = mod[:class_super_names]
  if super_names != nil
    child_names = super_names.keys()
    si = 0
    while si < child_names.size()
      child_name = child_names[si]
      super_name = super_names[child_name]
      if super_name != nil
        inheritance_classes[child_name] = true
        inheritance_classes[super_name] = true
      si += 1
  ast_keys = mod[:class_method_asts].keys()
  ki = 0
  while ki < ast_keys.size()
    key = ast_keys[ki]
    dot_idx = key.index(".")
    cname = key.slice(0, dot_idx)
    if exact_types[cname] == nil
      exact_types[cname] = {}
      conflicts[cname] = {}
    if inheritance_classes[cname] != true
      method_ast = mod[:class_method_asts][key]
      # `-> new(@field)` is an implicit arbitrary caller-to-ivar write and has
      # no assignment node in the body. It must invalidate an exact-class fact
      # just like an explicit `@field = value`.
      params = method_ast.params
      if params != nil
        pi = 0
        while pi < params.size()
          param = params[pi]
          if param.ivar_assign == true
            record_exact_source_ivar_write(cname, "@" + param.name, nil, exact_types, conflicts)
          pi += 1
      walk_exact_source_ivar_writes(method_ast.body, cname, exact_types, conflicts, mod)
    ki += 1
  mod[:exact_source_ivar_types] = exact_types

-> record_exact_source_ivar_write(cname, iname, exact_class, exact_types, conflicts)
  if conflicts[cname][iname] == true
    return nil
  if exact_class == nil
    exact_types[cname][iname] = nil
    conflicts[cname][iname] = true
    return nil
  existing = exact_types[cname][iname]
  if existing != nil && existing != exact_class
    exact_types[cname][iname] = nil
    conflicts[cname][iname] = true
  else
    exact_types[cname][iname] = exact_class
  nil

-> invalidate_exact_source_ivar_targets(targets, cname, exact_types, conflicts)
  if targets == nil
    return nil
  if is_ast_node?(targets)
    if ast_kind(targets) == :ivar
      record_exact_source_ivar_write(cname, targets.name, nil, exact_types, conflicts)
      return nil
    children = ast_children(targets)
    ci = 0
    while ci < children.size()
      invalidate_exact_source_ivar_targets(children[ci], cname, exact_types, conflicts)
      ci += 1
    return nil
  if type(targets) == "Array"
    ti = 0
    while ti < targets.size()
      invalidate_exact_source_ivar_targets(targets[ti], cname, exact_types, conflicts)
      ti += 1
  nil

-> walk_exact_source_ivar_writes(node, cname, exact_types, conflicts, mod)
  if node == nil
    return nil
  if is_ast_node?(node)
    nt = ast_kind(node)
    if nt == :assign && node.target != nil && ast_kind(node.target) == :ivar
      exact_class = exact_source_class_from_value(node.value, cname, mod)
      if exact_class == nil && node.type_hint != nil
        exact_class = resolve_exact_source_class_name(mod, cname, node.type_hint)
      record_exact_source_ivar_write(cname, node.target.name, exact_class, exact_types, conflicts)
    elsif nt == :compound_assign && node.target != nil && ast_kind(node.target) == :ivar
      record_exact_source_ivar_write(cname, node.target.name, nil, exact_types, conflicts)
    elsif nt == :multi_assign
      invalidate_exact_source_ivar_targets(node.targets, cname, exact_types, conflicts)
    children = ast_children(node)
    ci = 0
    while ci < children.size()
      walk_exact_source_ivar_writes(children[ci], cname, exact_types, conflicts, mod)
      ci += 1
  elsif type(node) == "Array"
    ai = 0
    while ai < node.size()
      walk_exact_source_ivar_writes(node[ai], cname, exact_types, conflicts, mod)
      ai += 1
  nil

-> walk_ivar_assigns(node, cname, ivar_types, ivar_conflicts, mod)
  if node == nil
    return nil
  t = type(node)
  if is_ast_node?(node)
    if ast_kind(node) == :assign && node.target != nil && ast_kind(node.target) == :ivar
      iname = node.target.name
      itype = infer_type(node.value, {}, mod[:fn_return_types], lowering_infer_maps)
      if itype != nil
        existing = ivar_types[cname][iname]
        if existing != nil && existing != itype
          ivar_conflicts[cname][iname] = true
        else
          ivar_types[cname][iname] = itype
    children = ast_children(node)
    ci = 0
    while ci < children.size()
      walk_ivar_assigns(children[ci], cname, ivar_types, ivar_conflicts, mod)
      ci += 1
  elsif t == "Array"
    ai = 0
    while ai < node.size()
      walk_ivar_assigns(node[ai], cname, ivar_types, ivar_conflicts, mod)
      ai += 1
  nil

# Phase 5: build a specialized variant of a user-defined class method,
# with `__self` typed to a concrete array variant. Returns the mangled
# function name so callers can emit a direct call. nil on bail-out
# (method not registered, recv_type unrecognized).
#
# Stub-then-fill recursion: the cache is populated with the mangled name
# *before* the body is lowered. Recursive calls to (class, method, recv_type)
# during body lowering hit the cache and emit a direct call to the same
# mangled symbol — LLVM resolves it once finalization completes.
-> specialize_method(parent_ctx, class_name, method_name, recv_type, call_arity = nil)
  mod = parent_ctx[:mod]
  cache_key = class_name + "." + method_name + "." + recv_type.to_s()
  if call_arity != nil
    cache_key = cache_key + "/" + call_arity.to_s()
  cached = mod[:specialized_methods][cache_key]
  if cached != nil
    return cached
  # Resolve the overload whose param count matches the call (e.g. sum vs
  # sum(init)); fall back to the bare-name entry for non-overloaded methods.
  ast = nil
  if call_arity != nil
    ast = mod[:class_method_asts][class_name + "." + method_name + "/" + call_arity.to_s()]
  if ast == nil
    ast = mod[:class_method_asts][class_name + "." + method_name]
  if ast == nil
    return nil
  mangled = mangled_specialized_name(class_name, method_name, recv_type)
  if mangled == nil
    return nil
  if call_arity != nil
    mangled = mangled + "_a" + call_arity.to_s()
  # Cache the stub before lowering — recursive calls during body lowering
  # resolve to this same mangled name, producing a forward reference.
  mod[:specialized_methods][cache_key] = mangled
  cloned = ast_deep_clone(ast)
  override = {fn_name: mangled, self_type: recv_type, source_class: class_name}
  lower_class_method(parent_ctx, class_name, cloned, override)
  mangled

# Phase C (#61): closure-escape inlining via :yield substitution.
#
# When a trait method's body invokes its block via `:yield(args)` (i.e.
# `&(args)` in source), and the call site supplies a single-expression
# captureless block literal, we can clone the method body and replace
# every :yield node with an inlined copy of the block's body — yield
# args bound to block params via :var → AST substitution. The result
# is a specialized fn that doesn't take the block at all, so the caller
# skips the closure allocation entirely.
#
# Inline conditions (conservative — fall back to closure call on any miss):
#   - block has no captures (block_inline_safe? checks free var set)
#   - block body is a single expression (multi-statement bodies would
#     need an inline `do { ... }` wrapper Tungsten doesn't have)
#   - block has no `return`, `break`, `next` (those would jump to wrong
#     scope after inlining)
-> block_inline_safe?(block, ctx)
  if block == nil || !is_ast_node?(block) || ast_kind(block) != :block
    return false
  body = block.body
  if body == nil || type(body) != "Array" || body.size() != 1
    return false
  if find_captures(block, ctx).size() != 0
    return false
  block_has_unsafe_jumps?(body[0]) == false

-> block_has_unsafe_jumps?(node)
  if node == nil
    return false
  t = type(node)
  if !is_ast_node?(node)
    return false
  nt = ast_kind(node)
  if nt in (:return :break :next :rescue)
    return true
  # Don't descend into nested blocks/defs — their returns/breaks belong
  # to a different scope and don't affect the outer block.
  if nt in (:block :def :class_def :method_def)
    return false
  children = ast_children(node)
  i = 0
  while i < children.size()
    if block_has_unsafe_jumps?(children[i])
      return true
    i += 1
  false

# Substitute :var references in a (cloned) AST node according to mapping
# (name → replacement AST). Recursively rewrites; replacement ASTs are
# cloned per occurrence so each reference is independent.
-> substitute_vars_in_ast(node, mapping)
  if node == nil
    return nil
  t = type(node)
  if !is_ast_node?(node)
    return node
  nt = ast_kind(node)
  if nt == :var && mapping.key?(node.name)
    return ast_deep_clone(mapping[node.name])
  # Don't substitute inside nested blocks/defs — they have their own
  # parameter scope.
  if nt in (:block :def :class_def :method_def)
    return node
  kid = kind_id_table[nt]
  if kid == nil
    return node
  schema = slab_offset_table_data[kid]
  if schema == nil
    return node
  ks = schema.keys()
  i = 0
  while i < ks.size()
    k = ks[i]
    v = ast_get(node, k)
    if is_ast_node?(v)
      ast_set(node, k, substitute_vars_in_ast(v, mapping))
    elsif type(v) == "Array"
      # Child-list arrays are immutable once frozen — rebuild and
      # write the whole field back rather than index-assigning into
      # `v` in place (see metal_emitter.w's substitute_children_with_offset
      # for the same fix applied to the schedule-rewrite walkers).
      any_replaced = false
      rebuilt_arr = []
      j = 0
      while j < v.size()
        elt = v[j]
        if is_ast_node?(elt)
          replaced = substitute_vars_in_ast(elt, mapping)
          if replaced != elt
            any_replaced = true
          rebuilt_arr.push(replaced)
        else
          rebuilt_arr.push(elt)
        j += 1
      if any_replaced
        ast_set(node, k, rebuilt_arr)
    i += 1
  node

# Walk a (cloned) AST and replace each :yield node with a clone of the
# block's single-expression body, with block params substituted by the
# yield's args. Stops at nested block/def boundaries (a yield inside a
# nested block refers to the inner block's `&`, not the user's outer one).
-> inline_yields_in_ast(node, block_params, block_body_expr)
  if node == nil
    return nil
  t = type(node)
  if !is_ast_node?(node)
    return node
  nt = ast_kind(node)
  if nt == :yield
    mapping = {}
    args = node.args
    if args == nil
      args = []
    pi = 0
    while pi < block_params.size() && pi < args.size()
      pname = block_params[pi]
      if is_ast_node?(pname)
        pname = pname.name
      mapping[pname] = args[pi]
      pi += 1
    cloned_body = ast_deep_clone(block_body_expr)
    return substitute_vars_in_ast(cloned_body, mapping)
  if nt in (:block :def :class_def :method_def)
    return node
  kid = kind_id_table[nt]
  if kid == nil
    return node
  schema = slab_offset_table_data[kid]
  if schema == nil
    return node
  ks = schema.keys()
  i = 0
  while i < ks.size()
    k = ks[i]
    v = ast_get(node, k)
    if is_ast_node?(v)
      ast_set(node, k, inline_yields_in_ast(v, block_params, block_body_expr))
    elsif type(v) == "Array"
      # Child-list arrays are immutable once frozen — rebuild and
      # write the whole field back rather than index-assigning into
      # `v` in place (see substitute_vars_in_ast above for the same fix).
      any_replaced = false
      rebuilt_arr = []
      j = 0
      while j < v.size()
        elt = v[j]
        if is_ast_node?(elt)
          replaced = inline_yields_in_ast(elt, block_params, block_body_expr)
          if replaced != elt
            any_replaced = true
          rebuilt_arr.push(replaced)
        else
          rebuilt_arr.push(elt)
        j += 1
      if any_replaced
        ast_set(node, k, rebuilt_arr)
    i += 1
  node

# True if a :yield node survives anywhere reachable from this method's body
# (recursing into iteration blocks, but NOT into nested def/method/class
# scopes — a `&` there is that def's own block). Used after the inline-yields
# rewrite to detect a yield the inliner left intact (e.g. map/select's `&(item)`
# nested inside the each-call's block, which the rewrite walks past). When that
# happens, inline specialization is unsound — the block param is stripped from
# the signature but a `&` still references it — so the caller must fall back to
# the closure (non-inline) path.
-> ast_contains_yield?(node)
  if node == nil
    return false
  if !is_ast_node?(node)
    if type(node) == "Array"
      i = 0
      while i < node.size()
        if ast_contains_yield?(node[i])
          return true
        i += 1
    return false
  nt = ast_kind(node)
  if nt == :yield
    return true
  if nt in (:def :class_def :method_def)
    return false
  kid = kind_id_table[nt]
  if kid == nil
    return false
  schema = slab_offset_table_data[kid]
  if schema == nil
    return false
  ks = schema.keys()
  i = 0
  while i < ks.size()
    if ast_contains_yield?(ast_get(node, ks[i]))
      return true
    i += 1
  false

# Phase C: specialize a trait method with the call site's literal block
# inlined at every :yield. The specialized fn has the block param removed
# (the closure is no longer needed at runtime). Returns mangled name or
# nil if specialization isn't applicable.
-> specialize_method_with_inlined_block(parent_ctx, class_name, method_name, recv_type, block_node)
  mod = parent_ctx[:mod]
  if mod[:next_inline_block_id] == nil
    mod[:next_inline_block_id] = 0
  inline_id = mod[:next_inline_block_id]
  mod[:next_inline_block_id] = inline_id + 1
  ast = mod[:class_method_asts][class_name + "." + method_name]
  if ast == nil
    return nil
  # Phase C only knows how to replace :yield nodes. A method with an
  # explicit named `&block` may invoke it as a local closure (`block(item)`),
  # which is deliberately not represented as :yield. Stripping that block
  # parameter would leave the closure call reading a nonexistent argument.
  if !ast_contains_yield?(ast.body)
    return nil
  base_mangled = mangled_specialized_name(class_name, method_name, recv_type)
  if base_mangled == nil
    return nil
  mangled = base_mangled + "_inl" + inline_id.to_s()
  cloned = ast_deep_clone(ast)
  # Strip the block param from the specialized fn's signature.
  if cloned.params != nil
    new_params = []
    pi = 0
    while pi < cloned.params.size()
      p = cloned.params[pi]
      if !is_ast_node?(p) || p.block_param != true
        new_params.push(p)
      pi += 1
    cloned.params = new_params
  # Reset cached lowering analysis (yield_block_name is now stale).
  cloned.lowering_analysis = nil
  # Inline yields throughout the body.
  block_body_expr = block_node.body[0]
  block_params = block_node.params
  if block_params == nil
    block_params = []
  cloned.body = inline_yields_in_ast(cloned.body, block_params, block_body_expr)
  # If a `&` yield survived (nested inside an iteration block the rewrite walks
  # past — e.g. map/select's `each -> ... &(item)`), inlining is unsound: the
  # block param was stripped but the body still yields to it. Bail so the call
  # site falls back to the closure (non-inline) path, which passes the block.
  if ast_contains_yield?(cloned.body)
    return nil
  override = {fn_name: mangled, self_type: recv_type, source_class: class_name}
  lower_class_method(parent_ctx, class_name, cloned, override)
  mangled

-> typed_array_element_bits(t)
  case t
  when :typed_array_u4, :typed_array_i4
    4
  when :typed_array_u8, :typed_array_i8
    8
  when :typed_array_u16, :typed_array_i16, :typed_array_bf16
    16
  when :typed_array_u32, :typed_array_i32, :typed_array_f32
    32
  else
    64

-> typed_array_signed?(t)
  t in (:typed_array_i4 :typed_array_i8 :typed_array_i16 :typed_array_i32 :typed_array_i64 :typed_array :typed_array_f32 :typed_array_f64)

-> typed_array_kernel_suffix(t)
  if t in (:typed_array_f64 :typed_array_f32 :typed_array_bf16)
    return "float"
  if t in (:typed_array_i4 :typed_array_i8 :typed_array_i16 :typed_array_i32 :typed_array_i64)
    return "signed"
  "unsigned"

# Phase 3: lower an ebits argument (`:u8`, `:f32`, raw int 16, etc.) to the
# raw int code the C constructors expect. Symbol form covers the FP8/FP4/bf16
# additions cleanly without forcing a numeric encoding on the .w side.
-> ebits_symbol_to_int(name)
  case name
  when "bool", "u1" then 1   # bit-packed array; 1 bit per element
  when "u4"      then 4
  when "i4"      then -4    # negative carries the signedness convention
  when "u8"      then 8
  when "i8"      then 108   # extended signed int: 8-bit storage
  when "u16"     then 16
  when "i16"     then 116   # extended signed int: 16-bit storage
  when "u32"     then 32
  when "i32"     then 33    # distinct signed code: +100 band (132) overflows the
                            # signed ebits byte; 32 is u32, -32 is f32
  when "u64"     then 64
  when "i64"     then 66    # distinct signed code: 164 overflows, 64 is u64,
                            # 65 is w64, -64 is f64
  when "f32"     then -32   # WTypedArray uses negative bit-count for floats
  when "f64"     then -64
  when "w64"     then 65    # raw WValue slot
  when "bf16"    then -116  # extended float: 16-bit storage, f32 arithmetic
  when "f8_e4m3" then -108  # all float ebits are negative — bit width = abs(value)
  when "f8_e5m2" then -109
  when "f4_e2m1" then -104
  else
    -1                       # unknown — runtime constructor will reject
-> ebits_arg_to_raw(ctx, arg)
  wfn = ctx[:func]
  if ast_kind(arg) == :symbol
    return ebits_symbol_to_int(arg.value).to_s()
  if ast_kind(arg) == :int
    return arg.value.to_s()
  # Fallback: lower at runtime, ensure it's a raw i64.
  tv = lower_expression(ctx, arg)
  inferred = infer_type(arg, ctx[:var_types], ctx[:mod][:fn_return_types], lowering_infer_maps)
  ensure_raw_machine_int(wfn, tv, :i64, inferred)

# Phase 6d: extract compile-time ebits value from an arg node, or nil
# if it isn't a constant. Used by stack-allocation lowering to size the
# alloca correctly (only emitted when ebits is a literal).
-> ebits_const_value(arg)
  if arg == nil
    return nil
  if ast_kind(arg) == :symbol
    return ebits_symbol_to_int(arg.value)
  if ast_kind(arg) == :int
    return arg.value
  nil

# Phase 6d: bytes needed to hold `size` elements of the given ebits.
# Mirrors the C `array_byte_size` helper. 4-bit packs two-per-byte;
# wider widths are size * (bits/8). Extended ebits (>64/-64) are
# special-cased; ebits=65 (w64 polymorphic) takes 8 bytes/elt.
-> small_array_payload_bytes(ebits, size)
  if size == 0
    return 0
  abs_bits = ebits
  if abs_bits < 0
    abs_bits = 0 - abs_bits
  if abs_bits == 65
    abs_bits = 64
  if abs_bits == 116
    return size * 2
  if abs_bits == 108 || abs_bits == 109
    return size
  if abs_bits == 104
    return (size + 1) / 2
  if abs_bits == 4
    return (size + 1) / 2
  size * (abs_bits / 8)

-> typed_array_etype_to_sym(etype)
  case etype
  when "bool", "u1"
    :typed_array_bool
  when "u4"
    :typed_array_u4
  when "i4"
    :typed_array_i4
  when "u8"
    :typed_array_u8
  when "i8"
    :typed_array_i8
  when "u16"
    :typed_array_u16
  when "i16"
    :typed_array_i16
  when "u32"
    :typed_array_u32
  when "i32"
    :typed_array_i32
  when "u64"
    :typed_array_u64
  when "i64"
    :typed_array_i64
  when "f32"
    :typed_array_f32
  when "f64"
    :typed_array_f64
  when "bf16"
    :typed_array_bf16
  when "f8_e4m3"
    :typed_array_f8_e4m3
  when "f8_e5m2"
    :typed_array_f8_e5m2
  when "f4_e2m1"
    :typed_array_f4_e2m1
  when "w64"
    :typed_array_w64
  else
    :typed_array

# ============================================================================
# Generic class monomorphization (hypercomplex-tower v0)
#
# Specializes `+ Name<T> < Parent<T>` class templates into concrete
# classes per `Name<f32>.new(...)` instantiation. The template is never
# lowered as a class (lower_class_def skips it); only its specializations
# reach class_init.
#
# Pipeline:
#   1. Register templates from ast.expressions (those with :type_params).
#   2. Walk AST collecting (template_name, [type_args]) tuples — both at
#      `Name<T>.method(args)` Call sites and bare `Name<T>` ClassRef sites.
#   3. For each tuple, deep-clone the template body, substitute T-params
#      with concrete types in :type_hints / :type_args / :type_hint slots,
#      and synthesize a ClassDef with name `Name$f32`. Recurse on the
#      parametric parent.
#   4. Insert specialized defs into ast.expressions immediately before
#      the first template.
#   5. Rewrite call/ref sites: ClassRef.name → mangled name, drop
#      :type_args.
#
# v0 limitations (follow-up work):
#   - No `T components[N]` data block substitution (data blocks today
#     carry no T-dependent slot type; storage stays as opaque WValue).
#   - No `class.new(...)` rewrite inside specialized methods (the
#     existing :self_ref → __self path covers most cases).
#   - No type inference: callers MUST write `Name<f32>.new(...)`
#     explicitly; bare `Name.new(...)` falls through to runtime
#     dispatch on the bare template name (which won't resolve).
#   - No constraint validation against `with T in (...)`.
# ============================================================================

-> mangle_generic_class_name(template_name, type_args)
  # "Quaternion" + ["f32"]      → "Quaternion$f32"
  # "Mat"        + ["f32","3","3"] → "Mat$f32_3_3"
  out = "" + template_name + "$"
  i = 0
  while i < type_args.size()
    if i > 0
      out = out + "_"
    out = out + type_args[i].to_s()
    i += 1
  out

-> collect_generic_instantiations_in_node(node, out, mod)
  if node == nil
    return nil
  if !is_ast_node?(node)
    return nil
  nk = ast_kind(node)
  # Don't descend into a generic template's own body. Instantiation
  # sites there use the template's unbound type params (e.g. a Quaternion
  # swizzle body referencing `Vec3<T>`); those become concrete only when
  # the enclosing template is specialized, at which point the ClassRef
  # rewrite in substitute_type_params_in_ast handles them. Collecting
  # them here would try to specialize `Vec3<T>` with the literal "T".
  if nk == :class_def && node.type_params != nil
    return nil
  type_args = node.type_args
  if type_args != nil
    template_name = nil
    if nk == :class_ref
      template_name = node.name
    elsif nk == :call && node.receiver != nil && ast_kind(node.receiver) == :class_ref
      template_name = node.receiver.name
    if template_name != nil
      key = mangle_generic_class_name(template_name, type_args)
      if out[key] == nil
        out[key] = [template_name, type_args]
  children = ast_children(node)
  ci = 0
  while ci < children.size()
    collect_generic_instantiations_in_node(children[ci], out, mod)
    ci += 1

-> collect_generic_instantiations(expressions, out, mod)
  i = 0
  while i < expressions.size()
    collect_generic_instantiations_in_node(expressions[i], out, mod)
    i += 1

-> substitute_type_param_in_string(s, mapping)
  # "T"      → "f32" (whole-string match)
  # "T[4]"   → "f32[4]" (head before `[`)
  # "Other"  → unchanged
  if s == nil
    return nil
  lbr = "\["
  bracket = s.index(lbr)
  if bracket == nil
    repl = mapping[s]
    if repl != nil
      return repl
    return s
  head = s.slice(0, bracket)
  rest = s.slice(bracket, s.size() - bracket)
  repl = mapping[head]
  if repl != nil
    return repl + rest
  s

-> substitute_type_params_in_ast(node, mapping, mod)
  if node == nil
    return nil
  if !is_ast_node?(node)
    return nil
  th = node.type_hint
  if th != nil
    new_th = substitute_type_param_in_string(th, mapping)
    if new_th != th
      node.type_hint = new_th
  hints = node.type_hints
  if hints != nil && type(hints) == "Hash"
    hkeys = hints.keys()
    ki = 0
    while ki < hkeys.size()
      k = hkeys[ki]
      old_sym = hints[k]
      old_str = old_sym.to_s()
      new_str = substitute_type_param_in_string(old_str, mapping)
      if new_str != old_str
        hints[k] = new_str.to_sym()
      ki += 1
  inner_args = node.type_args
  if inner_args != nil && type(inner_args) == "Array"
    # Child-list arrays are immutable once frozen (:type_args is a
    # sparse field but goes through the same freeze hook) — rebuild
    # and write the whole field back rather than index-assigning.
    any_replaced = false
    new_inner_args = []
    ji = 0
    while ji < inner_args.size()
      old_arg = inner_args[ji]
      repl = mapping[old_arg]
      if repl != nil
        new_inner_args.push(repl)
        any_replaced = true
      else
        new_inner_args.push(old_arg)
      ji += 1
    if any_replaced
      node.type_args = new_inner_args
  # ClassRef rewrite: bare references to OTHER generic templates inside
  # a specialization body get :type_args set from the current mapping
  # (Octonion's `half_class` returns `Quaternion` → becomes
  # `Quaternion<f32>` → rewrite_generic_call_sites mangles to
  # `Quaternion$f32`). Only annotate; don't trigger specialization
  # recursively here — the program-level instantiation pass picks up
  # the new ClassRef sites on its next iteration.
  if ast_kind(node) == :class_ref && mod != nil && mod[:generic_class_templates] != nil
    cref_name = node.name
    if cref_name != nil && mod[:generic_class_templates][cref_name] != nil
      tmpl = mod[:generic_class_templates][cref_name]
      tmpl_params = tmpl.type_params
      if tmpl_params != nil
        existing_args = node.type_args
        if existing_args == nil
          resolved = []
          ri = 0
          all_mapped = true
          while ri < tmpl_params.size()
            mv = mapping[tmpl_params[ri]]
            if mv == nil
              all_mapped = false
            else
              resolved.push(mv)
            ri += 1
          if all_mapped && resolved.size() == tmpl_params.size()
            node.type_args = resolved
            # Eagerly specialize so the new class def lands in
            # generic_specialization_order before the program-level
            # insertion runs. Guarded by generic_specializations_done
            # to avoid loops.
            if mod[:generic_specializations_done] != nil
              spec_key = mangle_generic_class_name(cref_name, resolved)
              if mod[:generic_specializations_done][spec_key] == nil
                mod[:generic_specializations_done][spec_key] = true
                inner_spec = specialize_generic_class(cref_name, resolved, mod)
                if inner_spec != nil
                  mod[:generic_specialization_order].push(inner_spec)
  children = ast_children(node)
  ci = 0
  while ci < children.size()
    substitute_type_params_in_ast(children[ci], mapping, mod)
    ci += 1
  arr_fields = ast_array_fields(node)
  ai = 0
  while ai < arr_fields.size()
    arr = arr_fields[ai]
    aj = 0
    while aj < arr.size()
      substitute_type_params_in_ast(arr[aj], mapping, mod)
      aj += 1
    ai += 1

-> specialize_generic_class(template_name, type_args, mod)
  template = mod[:generic_class_templates][template_name]
  if template == nil
    return nil
  type_params = template.type_params
  if type_params == nil
    return nil
  if type_params.size() != type_args.size()
    raise compile_error_for_node(:E_LOWER_GENERIC_ARITY, "generic " + template_name + " expects " + type_params.size().to_s() + " type args, got " + type_args.size().to_s(), nil, template)
  # Validate type args against `with T in (...)` constraints. Each
  # constraint maps a param-name to the list of allowed concrete types;
  # numeric shape params (Mat<T,M,N>'s M and N) have no constraint and
  # pass through unchecked.
  constraints = template.type_constraints
  if constraints != nil
    pi = 0
    while pi < type_params.size()
      pname = type_params[pi]
      actual = type_args[pi]
      ci = 0
      while ci < constraints.size()
        pair = constraints[ci]
        if pair[0] == pname
          allowed = pair[1]
          found = false
          ai = 0
          while ai < allowed.size()
            if allowed[ai] == actual
              found = true
            ai += 1
          if !found
            raise compile_error_for_node(:E_LOWER_GENERIC_CONSTRAINT, "type '" + actual.to_s() + "' not allowed for parameter " + pname + " of " + template_name + " (must be one of: " + allowed.join(", ") + ")", nil, template)
        ci += 1
      pi += 1
  mapping = {}
  i = 0
  while i < type_params.size()
    mapping[type_params[i]] = type_args[i]
    i += 1
  cloned_body = ast_deep_clone(template.body)
  ci = 0
  while ci < cloned_body.size()
    substitute_type_params_in_ast(cloned_body[ci], mapping, mod)
    ci += 1
  spec_name = mangle_generic_class_name(template_name, type_args)
  spec_super = template.superclass
  parent_type_args = template.parent_type_args
  if parent_type_args != nil && template.superclass != nil
    resolved_args = []
    pj = 0
    while pj < parent_type_args.size()
      arg = parent_type_args[pj]
      repl = mapping[arg]
      if repl != nil
        resolved_args.push(repl)
      else
        resolved_args.push(arg)
      pj += 1
    if mod[:generic_class_templates][template.superclass] != nil
      spec_super = mangle_generic_class_name(template.superclass, resolved_args)
      done_key = spec_super
      if mod[:generic_specializations_done][done_key] == nil
        mod[:generic_specializations_done][done_key] = true
        parent_spec = specialize_generic_class(template.superclass, resolved_args, mod)
        if parent_spec != nil
          mod[:generic_specialization_order].push(parent_spec)
  spec_class = Tungsten:AST:ClassDef.new(spec_name, spec_super, cloned_body, nil)
  spec_class

# Rewrite a bare `Foo<T>` class_ref into its mangled specialization
# name wherever one appears in the tree — as a call receiver
# (`Foo<T>.new`), a param/return type_hint's underlying node, etc.
# class_ref is an interned leaf kind (schema sentinel 257): its :name
# is part of the WValue's identity, not a mutable slot, so a rename
# can't happen in place — this returns the replacement class_ref and
# every caller (the schema-field walk below) writes it back via
# ast_set/array-rebuild, the same return-replacement discipline every
# other kind-changing rewrite in this compiler already follows.
-> rewrite_generic_call_sites_in_node(node, mod)
  if node == nil
    return nil
  if !is_ast_node?(node)
    return nil
  nk = ast_kind(node)
  if nk == :class_ref
    ta = node.type_args
    if ta != nil && mod[:generic_class_templates][node.name] != nil
      mangled = mangle_generic_class_name(node.name, ta)
      return Tungsten:AST:ClassRef.new(mangled)
    return nil
  kid = kind_id_table[nk]
  if kid == nil
    return nil
  schema = slab_offset_table_data[kid]
  if schema == nil
    return nil
  ks = schema.keys()
  i = 0
  while i < ks.size()
    k = ks[i]
    v = ast_get(node, k)
    if is_ast_node?(v)
      replaced = rewrite_generic_call_sites_in_node(v, mod)
      if replaced != nil
        ast_set(node, k, replaced)
    elsif type(v) == "Array"
      any_replaced = false
      rebuilt_arr = []
      j = 0
      while j < v.size()
        elt = v[j]
        if is_ast_node?(elt)
          replaced = rewrite_generic_call_sites_in_node(elt, mod)
          if replaced != nil
            rebuilt_arr.push(replaced)
            any_replaced = true
          else
            rebuilt_arr.push(elt)
        else
          rebuilt_arr.push(elt)
        j += 1
      if any_replaced
        ast_set(node, k, rebuilt_arr)
    i += 1
  nil

-> rewrite_generic_call_sites(ast, mod)
  expressions = ast.expressions
  any_replaced = false
  rebuilt = []
  i = 0
  while i < expressions.size()
    expr = expressions[i]
    replaced = rewrite_generic_call_sites_in_node(expr, mod)
    if replaced != nil
      rebuilt.push(replaced)
      any_replaced = true
    else
      rebuilt.push(expr)
    i += 1
  if any_replaced
    ast.expressions = rebuilt

-> monomorphize_generics(ast, mod)
  if mod[:generic_class_templates] == nil
    mod[:generic_class_templates] = {}
  # Register templates first so discovery can identify them.
  i = 0
  while i < ast.expressions.size()
    expr = ast.expressions[i]
    if ast_kind(expr) == :class_def && expr.type_params != nil
      mod[:generic_class_templates][expr.name] = expr
    i += 1
  if mod[:generic_class_templates].keys().size() == 0
    return nil
  instantiations = {}
  collect_generic_instantiations(ast.expressions, instantiations, mod)
  if instantiations.keys().size() == 0
    return nil
  mod[:generic_specializations_done] = {}
  mod[:generic_specialization_order] = []
  inst_keys = instantiations.keys()
  ki = 0
  while ki < inst_keys.size()
    key = inst_keys[ki]
    pair = instantiations[key]
    if mod[:generic_specializations_done][key] == nil
      mod[:generic_specializations_done][key] = true
      spec = specialize_generic_class(pair[0], pair[1], mod)
      if spec != nil
        mod[:generic_specialization_order].push(spec)
    ki += 1
  if mod[:generic_specialization_order].size() > 0
    new_expressions = []
    inserted = false
    si = 0
    while si < ast.expressions.size()
      expr = ast.expressions[si]
      if !inserted && ast_kind(expr) == :class_def && expr.type_params != nil
        spi = 0
        while spi < mod[:generic_specialization_order].size()
          new_expressions.push(mod[:generic_specialization_order][spi])
          spi += 1
        inserted = true
      new_expressions.push(expr)
      si += 1
    if !inserted
      spi = 0
      while spi < mod[:generic_specialization_order].size()
        new_expressions.push(mod[:generic_specialization_order][spi])
        spi += 1
    ast.expressions = new_expressions
  rewrite_generic_call_sites(ast, mod)
  nil
