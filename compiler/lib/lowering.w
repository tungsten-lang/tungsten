# Lowering — transforms AST nodes into WIRE IR.
#
# This file is the thin orchestrator of the lowering module: its `use`
# block below merges the compiler/lib/lowering/ workers (the order is
# the worker dependency chain — `make lowering-graph` prints it), and
# lower_ast drives them in order: module setup, the top-level
# registration walk, return-type inference, class initialization, then
# body lowering through lower_program (pass_registry.w). Worker roles
# are documented in each worker's header.

use runtime_types
use wire
use target
use naming
use error_formatter
use hashing
# Cross-tower dependencies the workers reference through the flat
# namespace: unit superscripts (ops.w's quantity desugar) live in the
# lexer's unit registry, and the return-type fixed point calls
# infer_return_type. In the full compiler both are loaded long before
# this file (dedup no-ops); declared here so `use lib/lowering`
# STANDALONE (compiler unit specs) is a complete program.
use ../../languages/tungsten/lexers/known_units
use return_inference
use lowering/pass_registry
use lowering/signatures
use lowering/types
use lowering/inference
use lowering/analysis
use lowering/core_abi
use lowering/elision
use lowering/program
use lowering/monomorphize
use lowering/literals
use lowering/ops
use lowering/blocks
use lowering/control_flow
use lowering/poly_sum
use lowering/pipeline_fusion
use lowering/views
use lowering/assign
use lowering/calls
use lowering/method_call
use lowering/definitions

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


# Create and seed the WIRE module: bignum source invariants, build
# defines, monomorphization registries, builtin-class tables, and the
# known_calls registry for bare C-runtime bridges.
-> init_lowering_module(source_path, fast_mode, math_mode, no_static_slab, build_defines)
  mod = wire_module(source_path)
  # Root loading always injects native BigInt comparison and bitwise support.
  # Carry the invariants to emission so a loader/cache regression cannot
  # silently bind the runtime's weak C bootstrap implementations.
  mod[:require_bigint_compare_src] = true
  mod[:require_bigint_bitwise_src] = true
  mod[:require_bigint_bitwise_mut_src] = true
  mod[:fast_mode] = fast_mode
  mod[:math_mode] = math_mode
  # Must be set BEFORE body lowering: the slab-freeze emission below
  # reads it mid-lowering. compile() historically stamped it onto mod
  # only after lower_ast returned, so the flag never suppressed the
  # freeze — no-static-slab builds froze the intern table anyway and
  # their lazily-materialized literals paid heap-string minting.
  mod[:no_static_slab] = no_static_slab
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

  # Built-in runtime classes are available to top-level expressions; source
  # classes with the same name still take precedence.
  builtin_classes = builtin_runtime_classes
  mod[:builtin_class_order] = builtin_classes
  mod[:builtin_class_names] = {}
  mod[:used_builtin_classes] = {}
  mod[:uses_argv] = false

  # Monomorphization registries.
  # - class_method_asts[Class.method] → original method_def AST node
  #   (so specialize_method can clone it without re-parsing source).
  # - specialized_methods[Class.method.variant] → mangled fn name. Stub
  #   inserted before lowering body so recursive calls resolve via the cache.
  # - small_array_consts: list of {name, ebits, size, bytes} records for
  #   compile-time const array literals. Emitter writes each
  #   as a private LLVM global; lowering ptrtoint's them at the load site.
  mod[:class_method_asts] = {}
  mod[:class_method_fn_names] = {}
  mod[:class_constructor_fn_names] = {}
  mod[:class_static_new] = {}
  mod[:specialized_methods] = {}
  mod[:small_array_consts] = []
  # The class-registration prepass expands traits/accessors/typed overloads
  # before body lowering needs the exact same transformed body. Keep that
  # work by AST-node identity so lower_class_def can reuse it instead of
  # rebuilding arrays and synthesized nodes a second time.
  mod[:prepared_class_bodies] = {}
  # First-declaration superclass links, resolved exactly as class creation
  # resolves them.  Reopens intentionally cannot replace this structural
  # relationship.  Exact-ivar proofs use the completed map to exclude both
  # ends of every inheritance edge: a parent method can run on a child, and a
  # child can inherit a parent writer.
  mod[:class_super_names] = {}
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
  #
  # This table is now LOAD-BEARING for correctness, not just dispatch
  # hygiene: an unseeded bare call no longer falls back to a fabricated
  # `__w_<name>` symbol (which died at link time, or worse got DCE'd at
  # higher opt levels and never died) — lower_call raises
  # E_LOWER_UNKNOWN_FN instead. A new C-runtime bridge callable as a bare
  # fn MUST be seeded here. The 2026-08-08 whole-corpus sweep (compiler,
  # every spec, every bit) found exactly one unseeded bridge: argv.
  mod[:known_calls]["argv"] = "__w_argv"
  mod[:known_calls]["read_file"] = "__w_read_file"
  mod[:known_calls]["read_file_bytes"] = "__w_read_file_bytes"
  mod[:known_calls]["file?"] = "__w_file_exists"
  mod[:known_calls]["file_exists?"] = "__w_file_exists"
  mod[:known_calls]["file_directory?"] = "__w_file_directory"
  mod[:known_calls]["file_mtime_ns"] = "__w_file_mtime_ns"
  mod[:known_calls]["file_size"] = "__w_file_size"
  mod[:known_calls]["file_expand_path"] = "__w_file_expand_path"
  mod[:known_calls]["file_expand_path_base"] = "__w_file_expand_path_base"
  mod[:known_calls]["file_join"] = "__w_file_join"
  mod[:known_calls]["read_dir"] = "__w_file_read_dir"
  mod[:known_calls]["write_file"] = "__w_write_file"
  mod[:known_calls]["write_file_bytes"] = "__w_write_file"
  mod[:known_calls]["file_stat_data"] = "__w_file_stat_data"
  mod[:known_calls]["tempfile_create"] = "__w_tempfile_create"
  mod[:known_calls]["file_unlink"] = "__w_unlink"
  mod[:known_calls]["file_unlink_strict"] = "__w_file_unlink_strict"
  mod[:known_calls]["file_link"] = "__w_file_link"
  mod[:known_calls]["file_chmod"] = "__w_file_chmod"
  mod[:known_calls]["file_rename"] = "__w_rename"
  mod[:known_calls]["file_temp_for"] = "__w_temp_file_for"
  mod[:known_calls]["file_fsync"] = "__w_fsync_path"
  mod[:known_calls]["file_fsync_parent"] = "__w_fsync_parent"
  mod[:known_calls]["digest_bytes64"] = "__w_digest_bytes64"
  mod[:known_calls]["digest_file64"] = "__w_digest_file64"
  mod[:known_calls]["digest_string64"] = "__w_digest_string64"
  mod[:known_calls]["cache_read"] = "__w_cache_read"
  mod[:known_calls]["cache_write"] = "__w_cache_write"
  mod[:known_calls]["system"] = "__w_system"
  mod[:known_calls]["sleep"] = "__w_sleep"
  mod[:known_calls]["capture"] = "__w_capture"
  mod[:known_calls]["exit"] = "__w_exit"
  mod[:known_calls]["raise"] = "w_raise"
  mod[:known_calls]["type"] = "__w_type"
  mod[:known_calls]["wymix"] = "__w_wymix"  # inlined, never actually called
  mod[:known_calls]["clock"] = "__w_clock"
  mod[:known_calls]["clock_ms"] = "__w_clock_ms"
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
  mod

# Registration walk over the top-level expressions: constant aliases,
# traits, fn/method defs (call keys, param counts, typed overloads,
# math-intrinsic aliases, memo tables), and class/module defs. Returns
# the list of methods whose return types still need inference.
-> register_top_level_defs(mod, expressions, source_path)
  # Flag top-level typed-overload sets so they get distinct symbols (must
  # run before the registration walk below reads function_name_for_def).
  mark_fn_overload_groups(expressions)
  # Reject true duplicate top-level defs (same final symbol) before the
  # content-hash topo-sort would infinite-loop on them.
  check_duplicate_fn_defs(expressions, source_path)
  # Collect methods and process class/module defs in a single walk.
  inferable_methods = []
  ei = 0
  while ei < expressions.size()
    expr = expressions[ei]
    # `constant_alias "WC"` — the parser stamped the declaring file's `in`
    # namespace as a second string arg (parser.w), so registration needs no
    # file context. Collected in this prepass so aliases resolve in every
    # method body regardless of statement order; the statement itself stays
    # a no-op in lower_statement (pass_registry.w).
    if ast_kind(expr) == :call && expr.receiver == nil && expr.name == "constant_alias"
      ca_args = expr.args
      if ca_args != nil && ca_args.size() == 2 && ast_kind(ca_args[0]) == :string && ast_kind(ca_args[1]) == :string
        mod[:constant_aliases][ca_args[0].value] = ca_args[1].value
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
      splat_index = method_splat_index(expr)
      if splat_index >= 0
        mod[:known_fn_splat_info][call_key] = {
          splat_index: splat_index,
          param_count: expr.params.size(),
          block_param_index: method_block_param_index(expr)
        }
      # `use math/globals`: an untyped top-level fn that exactly delegates
      # to the same-named Math intrinsic registers as an alias, so call
      # sites can lower as the intrinsic itself — raw f64 operands reach
      # libm directly instead of boxing through the wrapper fn.
      if expr.param_types == nil && math_intrinsic_runtime_name(expr.name, expr.params.size()) != nil
        if math_global_alias_def?(expr)
          if mod[:math_alias_fns] == nil
            mod[:math_alias_fns] = {}
          mod[:math_alias_fns][expr.name] = true
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
  inferable_methods

# Infer return types over the condensed call graph. Callee SCCs are processed
# before callers, so an arbitrarily deep acyclic chain needs one pass instead
# of one whole-program sweep per edge. Recursive SCCs iterate only their own
# members and use explicit/base-case evidence to seed mutual recursion.
-> infer_return_types_fixed_point(mod, inferable_methods)
  plan = return_inference_sccs(inferable_methods)
  components = plan[:components]
  defs = plan[:definitions]
  ci = 0
  while ci < components.size()
    component = components[ci]
    iter = 0
    max_iter = component.size() + 2
    changed = true
    while changed && iter < max_iter
      changed = false
      im = 0
      while im < component.size()
        m = defs[component[im]]
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
        enriched = enrich_int_locals(m.body, pmap)
        new_rt = infer_return_type(m, enriched, mod[:fn_return_types], lowering_infer_maps)
        if new_rt == nil
          new_rt = infer_return_type_evidence(m, enriched, mod[:fn_return_types], lowering_infer_maps)
        if new_rt != nil && new_rt != old_rt
          mod[:fn_return_types][call_key] = normalize_type_symbol(new_rt)
          changed = true
        im += 1
      iter += 1
    ci += 1
  nil

# Emit startup init calls for the built-in runtime classes a program
# actually uses (mark_builtin_runtime_class_uses fills the used set).
-> emit_builtin_class_inits(main_fn, mod)
  bci = 0
  while bci < mod[:builtin_class_order].size()
    bc_name = mod[:builtin_class_order][bci]
    if mod[:used_builtin_classes][bc_name] == true
      bc_str_id = module_string_constant(mod, bc_name)
      bc_byte_len = utf8_byte_length(bc_name) + 1
      emit_instruction(main_fn, {op: :builtin_class_init, class_name: bc_name, name_str_id: bc_str_id, name_byte_len: bc_byte_len})
    bci += 1
  nil

# Initialize classes in stable dependency order. Autoload discovery order is
# demand-driven, so a thin program can contain `Int < Real` before Real's
# definition even though a wider program happens to load the same files in
# parent-first order. Build the class-only stream in passes: ready classes
# retain source order, children wait for their parent, and reopens retain
# their per-class order behind the first declaration.
-> order_class_exprs(mod, expressions)
  runtime_class_names = {}
  ci = 0
  while ci < expressions.size()
    expr = expressions[ci]
    is_generic_template = ast_kind(expr) == :class_def && expr.type_params != nil
    if !is_generic_template && ast_kind(expr) in (:class_def :module_def)
      runtime_class_names[expr.name] = true
    ci += 1

  pending_class_exprs = []
  ci = 0
  while ci < expressions.size()
    expr = expressions[ci]
    is_generic_template = ast_kind(expr) == :class_def && expr.type_params != nil
    if !is_generic_template && ast_kind(expr) in (:class_def :module_def)
      pending_class_exprs.push(expr)
    ci += 1

  ordered_class_exprs = []
  ordered_class_names = {}
  while pending_class_exprs.size() > 0
    next_pending = []
    blocked_names = {}
    progressed = false
    ci = 0
    while ci < pending_class_exprs.size()
      expr = pending_class_exprs[ci]
      cname = expr.name
      ready = blocked_names[cname] != true
      if ready && ordered_class_names[cname] == nil
        order_super = expr.superclass
        if order_super != nil && !order_super.include?(":") && mod[:known_classes][order_super] == nil
          ns_super = resolve_class_in_namespace(mod, cname, order_super)
          if ns_super != nil
            order_super = ns_super
        if order_super != nil && runtime_class_names[order_super] == true && ordered_class_names[order_super] == nil
          ready = false
          blocked_names[cname] = true
      if ready
        ordered_class_exprs.push(expr)
        ordered_class_names[cname] = true
        progressed = true
      else
        next_pending.push(expr)
      ci += 1
    if !progressed
      raise "cyclic class inheritance prevents runtime initialization"
    pending_class_exprs = next_pending
  ordered_class_exprs

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
-> register_classes(main_fn, mod, ordered_class_exprs)
  processed_classes = {}
  ci = 0
  while ci < ordered_class_exprs.size()
    expr = ordered_class_exprs[ci]
    if ast_kind(expr) in (:class_def :module_def)
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
        mod[:class_super_names][cname] = super_name
        super_reg = nil
        if super_name != nil
          super_reg = next_temp(main_fn)
          emit_instruction(main_fn, {op: :load_class, temp: super_reg, class_name: super_name})
        emit_instruction(main_fn, {op: :class_new, temp: cls_temp, name_str_id: name_str_id, name_byte_len: name_byte_len, super_reg: super_reg})
        emit_instruction(main_fn, {op: :class_store, value: cls_temp, class_name: cname})

        # Register type dispatch key if this class maps to a built-in type.
        # ByteArray/BoolArray/TypedArray are Array FACADES (same WArray
        # struct, same subtag 0x0A, distinguished only by ebits) — their
        # scaffold classes must NOT register, or they clobber the Array
        # class binding for every array in the program: dynamic dispatch
        # consults g_type_class[0x0A] and the empty facade class hides all
        # of Array's ported methods ("undefined method 'size' for Array").
        # Their `.new` is intercepted by name in runtime dispatch instead.
        dkey = type_dispatch_key(cname)
        if dkey != nil && !(cname in ("ByteArray" "BoolArray" "TypedArray"))
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
          super_offsets = ast_ivar_offsets_get(super_node)
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
      mod[:prepared_class_bodies][expr] = class_body

      # Populate view_layouts in this pre-pass so that
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
        ast_ivar_offsets_set(canonical, ivar_offsets)
        ast_ivar_count_set(canonical, offset)

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
                # Bodyless (abstract/intrinsic) statics are not in the
                # direct-dispatch registry — see register_static_method.
                static_info = known_static_method_for(mod, static_key, mnode.params.size())
                if static_info != nil
                  static_info[:return_type] = static_rt
            elsif mnode.from_fn == true && mnode.param_types != nil && embedded_body_directive(mnode) != nil
              # Embedded ll/asm kernels are raw-ABI helpers, not dispatchable
              # methods — registering one would hand the dynamic dispatcher a
              # function expecting raw machine args. lower_class_method owns
              # their raw-callable registration.
              nil
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
                info = {
                  fn_name: inst_fn_name,
                  method_fn_name: inst_fn_name,
                  arity: method_runtime_arity(mnode),
                  return_type: static_rt,
                  param_types: normalized_static_param_types(mnode),
                  raw_abi: inst_raw_abi,
                  from_fn: mnode.from_fn == true,
                  accepts_block: false,
                  param_count: mnode.params.size(),
                  splat_index: method_splat_index(mnode),
                  block_param_index: method_block_param_index(mnode)
                }
                register_known_static_method_info(mod, static_key, info, mnode.params.size(), mnode.params.size())
                if mnode.from_fn == true
                  impure_ccall = fn_body_calls_impure_ccall?(mnode.body)
                  mnode.calls_impure_ccall = impure_ccall
                  if !impure_ccall
                    mod[:known_pure_calls][static_key] = inst_fn_name
                    if mod[:fn_memo_tables][static_key] == nil
                      mod[:fn_memo_tables][static_key] = inst_fn_name + ".memo"
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
            # BigInt is excluded in BOTH places: its view is an internal
            # header mirror and synthesizes no public accessors (see
            # lower_class_def), so registering the symbols here would
            # reference getters that are never emitted.
            if cname != "BigInt"
              vd_layout = ast_get(mnode, :count)
              if vd_layout != nil && type(vd_layout) == "Hash" && vd_layout[:fields] != nil
                vdf = 0
                while vdf < vd_layout[:fields].size()
                  vfname = vd_layout[:fields][vdf][:name]
                  # Data getters are synthesized later by lower_class_def.
                  # Keep their ASTs out of class_method_asts (that registry
                  # feeds exact-ivar write analysis), but record the same
                  # plain ABI symbol in the independent devirtualization
                  # index so exact-class call sites can guard and call it.
                  register_class_method(main_fn, mod, cname, vfname, 1)
                  vgetter = Tungsten:AST:MethodDef.new(vfname, [], [])
                  mod[:class_method_fn_names][cname + "." + vfname + "/0"] = class_method_function_name(cname, vgetter)
                  vdf += 1
          mi2 += 1
    ci += 1
  nil

# Register custom units (if any were assigned during lowering).
# Prepend to main function so they run before any quantity display.
# They live on mod, not ctx — see assign_custom_unit in literals.w.
-> prepend_custom_unit_registrations(main_fn, mod)
  if mod[:custom_units] != nil && mod[:custom_units].size() > 0
    cu_keys = mod[:custom_units].keys()
    reg_instructions = []
    cui = 0
    while cui < cu_keys.size()
      unit_name = cu_keys[cui]
      unit_id = mod[:custom_units][unit_name]
      str_id = module_string_constant(mod, unit_name)
      byte_len = utf8_byte_length(unit_name) + 1
      reg_instructions.push({op: :register_unit, unit_id: unit_id, str_id: str_id, byte_len: byte_len})
      cui += 1
    # Prepend into the entry block, same shape as prepend_memo_table_initializers.
    cu_entry = main_fn[:blocks][0]
    cu_old = cu_entry[:instructions]
    cu_new = []
    cui = 0
    while cui < reg_instructions.size()
      cu_new.push(reg_instructions[cui])
      cui += 1
    cui = 0
    while cui < cu_old.size()
      cu_new.push(cu_old[cui])
      cui += 1
    cu_entry[:instructions] = cu_new
  nil

-> lowering_contract_name(node)
  if node == nil || !is_ast_node?(node) || ast_kind(node) != :call
    return nil
  receiver = node.receiver
  if receiver == nil || !is_ast_node?(receiver) || ast_kind(receiver) != :class_ref || receiver.name != "Tungsten"
    return nil
  if node.name in ("PROTECT_THE_CORE!" "LOCK_THE_DOORS!")
    return node.name
  nil

-> lowering_definition_key(node)
  kind = ast_kind(node)
  if kind in (:class_def :module_def :trait_def)
    return "type:" + node.name
  if kind in (:fn_def :method_def)
    arity = 0
    if node.params != nil
      arity = node.params.size()
    return "fn:" + node.name + "/" + arity.to_s()
  nil

# Record the contracts before any analysis consumes closed-world facts. Loader
# performs the full autoload-registry validation; this duplicate structural
# check keeps compile_to_wire safe for tests/tools that hand it an AST directly.
-> collect_lowering_contracts(mod, expressions, source_path)
  lock_seen = false
  core_keys = {}
  i = 0
  while i < expressions.size()
    node = expressions[i]
    contract = lowering_contract_name(node)
    if contract != nil
      if node.args == nil || node.args.size() != 0 || node.block != nil
        raise compile_error_for_node(:E_CONTRACT_ARITY, "Tungsten." + contract + " takes no arguments or block", source_path, node)
      if contract == "PROTECT_THE_CORE!"
        mod[:protect_core] = true
      else
        mod[:method_tables_locked] = true
        lock_seen = true
      ast_set(node, :validated_program_contract, true)
    else
      key = lowering_definition_key(node)
      if lock_seen && key != nil
        path = ast_get(node, :source_path)
        if path == nil
          path = source_path
        raise compile_error_for_node(:E_CONTRACT_LOCK_ORDER, "method and type definitions must appear before Tungsten.LOCK_THE_DOORS!", path, node)
      if key != nil && definition_from_core?(node)
        core_keys[key] = true
    i += 1

  if mod[:protect_core] == true
    i = 0
    while i < expressions.size()
      node = expressions[i]
      key = lowering_definition_key(node)
      if key != nil && !definition_from_core?(node) && core_keys[key] == true
        path = ast_get(node, :source_path)
        if path == nil
          path = source_path
        raise compile_error_for_node(:E_CONTRACT_CORE_MUTATION, "Tungsten.PROTECT_THE_CORE! forbids replacing or reopening Core definition '" + node.name + "'", path, node)
      i += 1
  nil

-> lower_ast(ast, source_path, verbose = false, fast_mode = false, build_defines = nil, math_mode = :precise, no_static_slab = false)
  mod = init_lowering_module(source_path, fast_mode, math_mode, no_static_slab, build_defines)
  collect_lowering_contracts(mod, ast.expressions, source_path)

  # Generic class monomorphization runs BEFORE the main expressions walk
  # so specialized classes are visible to every downstream pass.
  monomorphize_generics(ast, mod)
  # Desugar `SmallArray<T, N>.new` → `SmallArray.new(:T, N)`. Always runs (unlike
  # monomorphize_generics, which early-returns when no user generic templates
  # exist), so a program using SmallArray<T,N> without any user generics is still
  # rewritten. Must precede the stack-promote / escape analysis so it sees the
  # canonical constructor.
  rewrite_smallarray_generic_ctors(ast)

  # PROTECT_THE_CORE turns Core ownership into an optimization boundary. Core
  # registration and SCC return inference run before user declarations exist,
  # then user inference may consume the frozen Core facts in the forward
  # direction. This prevents a declared or inferred user return from changing
  # how a Core caller lowers while retaining Core facts for user code.
  core_expressions = nil
  user_expressions = nil
  if mod[:protect_core] == true
    partition = stable_core_partition_expressions(ast.expressions)
    core_expressions = partition[:core]
    user_expressions = partition[:user]
    prepare_stable_core_contract(mod, core_expressions, user_expressions, partition[:missing])

    core_inferable = register_top_level_defs(mod, core_expressions, source_path)
    infer_return_types_fixed_point(mod, core_inferable)
    user_inferable = register_top_level_defs(mod, user_expressions, source_path)
    infer_return_types_fixed_point(mod, user_inferable)
  else
    inferable_methods = register_top_level_defs(mod, ast.expressions, source_path)
    infer_return_types_fixed_point(mod, inferable_methods)

  # Freeze every top-level function's boxed-vs-raw ABI before any body is
  # lowered.  Forward typed calls must use the same ABI as callees declared
  # earlier; discovering raw-callable functions incrementally made source
  # order silently change the meaning of identical LLVM i64 parameters.
  if core_expressions != nil
    preregister_top_level_raw_abis(mod, core_expressions)
    preregister_top_level_raw_abis(mod, user_expressions)
    collect_top_level_static_types(mod, core_expressions)
    mod[:core_top_level_static_types] = copy_core_abi_map(mod[:top_level_static_types])
    collect_top_level_static_types(mod, user_expressions)
  else
    preregister_top_level_raw_abis(mod, ast.expressions)
    collect_top_level_static_types(mod, ast.expressions)
  collect_extern_var_refs(mod, ast.expressions)
  if core_expressions != nil
    mark_stable_core_global_exports(mod, core_expressions)

  # Tier-a call-site parameter type inference: seed unannotated top-level
  # fn params from the unanimous concrete type seen across all call sites
  # (typed arrays / floats only, no ABI change, no clone). Needs the
  # top-level static types just collected; consumed in
  # populate_definition_var_types when each body is lowered below.
  collect_param_type_observations(mod, ast.expressions, core_expressions, mod[:core_top_level_static_types])

  # ARGV use is discovered by the combined runtime-use walk below. Build the
  # function first, then attach argc/argv before emission if that walk finds a
  # use. No instructions are emitted between these points.
  main_fn = build_function("main", [], "i32", true, nil)
  main_fn[:source_kind] = :entry
  main_fn[:source_path] = source_path
  mod[:functions].push(main_fn)

  var_types = {}
  ctx = {
    mod: mod,
    func: main_fn,
    var_types: var_types,
    class_name: nil,
    source_path: source_path,
    bindings: {},
    unboxed_vars: {},
    local_assignment_counts: local_assignment_counts(ast.expressions),
    straight_line_local_assignments: straight_line_local_assignments(ast.expressions),
    raw_int_candidates: raw_int_candidate_map(ast.expressions, var_types, mod),
    mut_accumulators: mut_accumulator_candidates(ast.expressions),
    method_name: nil,
    is_class_method: false,
    is_block: false,
    verbose: verbose
  }

  mark_builtin_runtime_class_uses(ast.expressions, mod)

  # Initialize argv subsystem only for programs that touch ARGV / argv().
  if mod[:uses_argv]
    main_fn[:extra_params] = [{type: "i32", name: "%argc"}, {type: "ptr", name: "%argv"}]
    emit_instruction(main_fn, {op: :argv_init})

  emit_builtin_class_inits(main_fn, mod)
  ordered_class_exprs = order_class_exprs(mod, ast.expressions)
  register_classes(main_fn, mod, ordered_class_exprs)

  # All source definitions preceding LOCK_THE_DOORS have now been emitted as
  # startup registrations. Close both instance and static method tables before
  # any user statement executes. The runtime owns enforcement so native/FFI
  # registration paths cannot invalidate the compiler's direct-call proof.
  if mod[:method_tables_locked] == true
    method_lock_tmp = next_temp(main_fn)
    emit_instruction(main_fn, {op: :call_direct_i64, temp: method_lock_tmp, name: "w_method_tables_lock_safe", args: []})

  # Freeze the string slab once startup registration is fully emitted (every
  # class/method-name intern above precedes this point in main). The compiled
  # binary's literals all live in the STATIC slab, so post-freeze w_string_n
  # canonicalizes by lookup: content matching any literal returns the slab
  # value (bit-equality with literals, case arms, and hash keys all intact),
  # and only content no literal can match mints a mode-7 heap string. Without
  # the freeze every unique runtime string (i.to_s() in a loop!) was INSERTED
  # into the intern table — 65% of new_string's profile was w_slab_intern plus
  # table growth, and the slab grew without bound. no-static-slab builds keep
  # interning: their literals materialize lazily in USER code, after this
  # point, and must still canonicalize into the slab.
  if mod[:no_static_slab] != true
    slab_freeze_tmp = next_temp(main_fn)
    emit_instruction(main_fn, {op: :call_direct_i64, temp: slab_freeze_tmp, name: "w_slab_freeze_safe", args: []})

  # Pre-pass (gap #2) over class method ASTs to collect ivar
  # types, so dispatch on `self.@arr.method()` can specialize when
  # @arr is statically typed. Runs after all class methods are
  # registered (mod[:class_method_asts] populated) so cross-method
  # ivar writes are visible.
  collect_ivar_types(mod)

  # v0 AST-level escape pre-pass for SmallArray.new at top
  # level. Non-recursive (no nested-body walks); flips the # stack
  # annotation default to "on" for safe top-level patterns.
  mark_nonescaping_small_arrays(ast.expressions)

  # Promote non-escaping, non-resized `i32[N]` (N<=255) locals to
  # stack WSmallArrays. Recurses into every function/method body (unlike the
  # top-level-only SmallArray.new pass above). ~5.7x faster alloc + (with the
  # small-array rvalue reads routed through small_array_get_inline, lowering/ops.w)
  # vectorizing element loops — a promoted 128-elem fill+sum is ~5x faster than
  # the heap form. Always on.
  mark_stackable_typed_arrays(ast.expressions)

  if verbose
    << "  lowering..."
  lower_program(ctx, ast.expressions)

  # Initialize memo tables only for pure fns that are actually called.
  prepend_memo_table_initializers(main_fn, mod)

  if verbose
    << ""
    << "  done (" + mod[:functions].size().to_s() + " functions)"

  prepend_custom_unit_registrations(main_fn, mod)

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
  if core_expressions != nil
    finalize_stable_core_abi(mod, core_expressions)
  mod

# -- Emit WIRE flag: dump WIRE as text --

-> emit_wire_text(mod)
  out = "=== WIRE IR ===\n"
  out = out + "source: " + mod[:source_path] + "\n"
  out = out + "strings: " + mod[:strings].size().to_s() + "\n"
  out = out + "functions: " + mod[:functions].size().to_s() + "\n\n"
  if mod[:core_abi_hash] != nil
    out = out + "core abi: " + mod[:core_abi_hash] + " (" + mod[:core_abi_function_count].to_s() + " functions, " + mod[:core_abi_class_count].to_s() + " classes, " + mod[:core_abi_global_count].to_s() + " globals)\n"
    if mod[:core_reuse_contract] == :stable
      out = out + "core reuse: stable\n\n"
    else
      out = out + "core reuse: monolithic fallback (" + mod[:core_reuse_fallback_reason] + ")\n\n"

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
        if inst[:devirt_fn] != nil
          out = out + " devirt=@" + inst[:devirt_fn]
          out = out + " class=" + inst[:devirt_class]
        if inst[:construct_fn] != nil
          out = out + " construct=@" + inst[:construct_fn]
          out = out + " class=" + inst[:construct_class]
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

# `use math/globals` alias detection: true when a top-level fn def is an
# exact delegation to the same-named Math intrinsic — a single-expression
# body `Math.<name>(params...)` passing the params through in order. The
# prepass registers matches in mod[:math_alias_fns]; lower_call consults
# that to lower alias calls as the intrinsic itself.
-> math_global_alias_def?(expr)
  body = expr.body
  if body == nil || body.size() != 1
    return false
  b = body[0]
  if !is_ast_node?(b) || ast_kind(b) != :call
    return false
  if b.block != nil
    return false
  if b.name != expr.name
    return false
  recv = b.receiver
  if recv == nil || !is_ast_node?(recv) || ast_kind(recv) != :class_ref
    return false
  if recv.name != "Math"
    return false
  params = expr.params
  bargs = b.args
  if bargs == nil || params == nil
    return false
  if bargs.size() != params.size()
    return false
  i = 0
  while i < bargs.size()
    a = bargs[i]
    if !is_ast_node?(a) || ast_kind(a) != :var
      return false
    if a.name != param_runtime_name(params[i])
      return false
    i += 1
  true
