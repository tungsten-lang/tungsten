# Lowering / program_index — one schema-guided discovery pass over the final
# source AST. It records program-wide facts that used to require independent
# recursive walks: nested-scope global references, builtin class references,
# and ARGV use. It also retains the cheap top-level subsets consumed by later
# registration/summary passes.

-> program_index_walk_value(value, index, mod, in_nested)
  if value == nil
    return nil
  if type(value) == "Array"
    i = 0
    while i < value.size()
      program_index_walk_value(value[i], index, mod, in_nested)
      i += 1
    return nil
  if !is_ast_node?(value)
    return nil

  kind = ast_kind(value)
  nested = in_nested
  if kind in (:fn_def :method_def :class_def :module_def :trait_def :block)
    nested = true

  if kind in (:var :class_ref)
    name = value.name
    if kind == :var
      if nested && name != nil
        index[:extern_var_refs][name] = true
      if name == "ARGV"
        index[:uses_argv] = true
    if name != nil && mod[:builtin_class_names][name] == true
      index[:builtin_class_names][name] = true
  elsif kind == :call && value.receiver == nil && value.name == "argv"
    index[:uses_argv] = true

  kid = kind_id_table[kind]
  if kid == nil
    # Math/overflow mode blocks are intentionally lightweight Hash ASTs rather
    # than schema kinds. Their body is still ordinary source and participates
    # in both global-reference and runtime-use discovery.
    if kind in (:fastmath_block :strictmath_block :overflow_block)
      program_index_walk_value(value[:body], index, mod, nested)
    return nil
  child_keys = slab_child_keys_table[kid]
  if child_keys == nil
    return nil
  i = 0
  while i < child_keys.size()
    program_index_walk_value(ast_get(value, child_keys[i]), index, mod, nested)
    i += 1
  nil

-> build_program_index(expressions, mod)
  index = {
    expressions: expressions,
    top_level_functions: [],
    runtime_class_exprs: [],
    runtime_class_names: {},
    extern_var_refs: {},
    builtin_class_names: {},
    uses_argv: false
  }
  i = 0
  while i < expressions.size()
    node = expressions[i]
    kind = ast_kind(node)
    if kind in (:fn_def :method_def)
      index[:top_level_functions].push(node)
    if kind in (:class_def :module_def) && !(kind == :class_def && node.type_params != nil)
      index[:runtime_class_exprs].push(node)
      index[:runtime_class_names][node.name] = true
    program_index_walk_value(node, index, mod, false)
    i += 1
  index

-> apply_program_index_extern_refs(mod, index)
  if env("TUNGSTEN_DEMOTE_TOP_LEVEL") == "0"
    mod[:extern_var_refs] = nil
  else
    mod[:extern_var_refs] = index[:extern_var_refs]
  nil

-> apply_program_index_runtime_uses(mod, index)
  if index[:uses_argv] == true
    mod[:uses_argv] = true
  names = index[:builtin_class_names].keys()
  i = 0
  while i < names.size()
    mark_builtin_class_used(mod, names[i])
    i += 1
  nil
