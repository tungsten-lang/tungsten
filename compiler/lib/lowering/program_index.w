# Lowering / program_index — one schema-guided discovery pass over the final
# source AST. It records program-wide facts that used to require independent
# recursive walks: nested-scope global references, builtin class references,
# and ARGV use. It also retains the cheap top-level subsets consumed by later
# registration/summary passes.

program_index_leaf_kids = build_program_index_leaf_kids()

-> build_program_index_leaf_kids
  tbl = Array.new(KIND_MAX + 1)
  leafs = [KIND_INT, KIND_STRING, KIND_SYMBOL, KIND_BOOL, KIND_NIL_LIT, KIND_RETURN_NIL, KIND_FLOAT, KIND_CHAR, KIND_IVAR, KIND_CVAR, KIND_GVAR, KIND_SELF_REF, KIND_BREAK, KIND_NEXT, KIND_PARAM]
  i = 0
  while i < leafs.size()
    k = leafs[i]
    if k != nil && k >= 0 && k <= KIND_MAX
      tbl[k] = true
    i += 1
  tbl

-> program_index_walk_value(value, index, mod, in_nested)
  if value == nil
    return nil
  if ccall_nobox("w_is_node_extern", value) == 1
    kid = ccall_nobox("w_node_kind_extern", value)
    if kid == nil || kid < 1 || kid > KIND_MAX
      return nil
    if program_index_leaf_kids[kid] == true
      return nil
    if kid == KIND_VAR
      name = ccall_nobox("w_ast_intern_str_of", value)
      if in_nested && name != nil
        index[:extern_var_refs][name] = true
      if name == "ARGV"
        index[:uses_argv] = true
      if name != nil && mod[:builtin_class_names][name] == true
        index[:builtin_class_names][name] = true
      return nil
    if kid == KIND_CLASS_REF
      name = ccall_nobox("w_ast_intern_str_of", value)
      if name != nil && mod[:builtin_class_names][name] == true
        index[:builtin_class_names][name] = true
      return nil
    nested = in_nested
    if kid == KIND_FN_DEF || kid == KIND_METHOD_DEF || kid == KIND_CLASS_DEF || kid == KIND_MODULE_DEF || kid == KIND_TRAIT_DEF || kid == KIND_BLOCK
      nested = true
    elsif kid == KIND_CALL
      crecv = ccall_nobox("w_node_field_load", value, 0)
      cname = ccall_nobox("w_node_field_load", value, 1)
      if crecv == nil
        if cname == "argv"
          index[:uses_argv] = true
      elsif cname == "new" && ccall_nobox("w_ast_sparse_get", value, :type_args) != nil && ccall_nobox("w_is_node_extern", crecv) == 1 && ccall_nobox("w_node_kind_extern", crecv) == KIND_CLASS_REF && ccall_nobox("w_ast_intern_str_of", crecv) == "SmallArray"
        index[:has_smallarray_generic] = true
    offsets = slab_child_offsets_table[kid]
    if offsets == nil
      return nil
    n_off = offsets.size()
    i = 0
    while i < n_off
      program_index_walk_value(ccall_nobox("w_node_field_load", value, offsets[i]), index, mod, nested)
      i += 1
    return nil

  if type(value) == "Array"
    n_val = value.size()
    i = 0
    while i < n_val
      program_index_walk_value(value[i], index, mod, in_nested)
      i += 1
    return nil
  if !is_ast_node?(value)
    return nil

  kind = ast_kind(value)
  if kind in (:int :string :symbol :bool :nil_val :nil_lit :return_nil :float :char :ivar :cvar :gvar :self_ref :break :next :param)
    return nil
  if kind in (:var :class_ref)
    name = value.name
    if kind == :var
      if in_nested && name != nil
        index[:extern_var_refs][name] = true
      if name == "ARGV"
        index[:uses_argv] = true
    if name != nil && mod[:builtin_class_names][name] == true
      index[:builtin_class_names][name] = true
    return nil

  nested = in_nested
  if kind in (:fn_def :method_def :class_def :module_def :trait_def :block)
    nested = true
  elsif kind == :call
    if value.receiver == nil
      if value.name == "argv"
        index[:uses_argv] = true
    elsif value.name == "new" && value.type_args != nil && ast_kind(value.receiver) == :class_ref && value.receiver.name == "SmallArray"
      index[:has_smallarray_generic] = true

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
    uses_argv: false,
    has_smallarray_generic: false
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
