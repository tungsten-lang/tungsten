# jsn/module — Full ECMAScript Modules (ECMA-262 §16.2):
# Source Text Module Records, JSON / Bytes / Text Synthetic Modules,
# Module Namespace Exotic Objects (ordinary & deferred), Tarjan DFS Link & Evaluate,
# Top-Level Await async execution graph, dynamic import(), import.meta, import attributes,
# and ShadowRealm.prototype.importValue.

in JS

# Host loader hook: ->(ref_url, specifier, attrs_hash, phase) returning [canon_url, kind, content_str]
# kind: :source | :json | :text | :bytes
JS_MODULE_LOADER_HOOK = [nil]

# Active script or module URL for resolving relative dynamic imports / ShadowRealm.importValue.
JS_CURRENT_URL = [""]

# Monotonic counter for [[AsyncEvaluationOrder]] (§16.2.1.5.3.1).
JS_MOD_ASYNC_ORDER = [0]

# Cached shape for null-prototype ModuleNamespace exotic objects.
JS_MOD_NS_SHAPE = [nil]

-> js_mod_ns_shape
  JS_MOD_NS_SHAPE[0] = js_root_shape(nil, 0, 4) if JS_MOD_NS_SHAPE[0] == nil
  JS_MOD_NS_SHAPE[0]

# ---- Module Namespace Exotic Object (§10.4.6 + import-defer) ----

+ ModuleNamespace < JS:Base
  rw :mod, :exports, :deferred

  -> new(@shape, @mod, @exports, @deferred)
    @ext = nil
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_EXOTIC)

  -> is_sym_like?(p)
    p.is_a?(JS:Symbol) || (@deferred && p == "then")

  -> ready_for(p)
    js_mod_evaluate_sync(@mod) if @deferred && !is_sym_like?(p)
    nil

  -> get_prototype_of
    JS_NULL

  -> proto
    nil

  -> set_prototype_of(v)
    v == JS_NULL || v == nil

  -> is_extensible?
    false

  -> prevent_extensions
    true

  -> get_own_property(p)
    if p == SYM_TO_STRING_TAG
      return JS:PropDesc.data(@deferred ? "Deferred Module" : "Module", 0)
    return nil if is_sym_like?(p)
    ready_for(p)
    return nil if !@exports.include?(p)
    v = get(p, self)
    JS:PropDesc.data(v, ATTR_W + ATTR_E)

  -> define_own_property(p, desc)
    if is_sym_like?(p)
      if p == SYM_TO_STRING_TAG
        cur = JS:PropDesc.data(@deferred ? "Deferred Module" : "Module", 0)
        return js_desc_compatible?(false, desc, cur)
      return false
    cur = get_own_property(p)
    return false if cur == nil
    return false if desc.configurable == true || desc.enumerable == false || desc.accessor? || desc.writable == false
    return js_same_value(desc.value, cur.value) if desc.has_value
    true

  -> has_property?(p)
    return true if p == SYM_TO_STRING_TAG
    return false if is_sym_like?(p)
    ready_for(p)
    @exports.include?(p)

  -> has_own?(p)
    get_own_property(p) != nil

  -> get(p, receiver = JS_HOLE)
    return (@deferred ? "Deferred Module" : "Module") if p == SYM_TO_STRING_TAG
    return nil if is_sym_like?(p)
    ready_for(p)
    return nil if !@exports.include?(p)
    rb = js_mod_resolve_export(@mod, p, [])
    return nil if rb == nil || rb == :ambiguous
    js_mod_read_resolved(rb)

  -> get_own(p)
    return (@deferred ? "Deferred Module" : "Module") if p == SYM_TO_STRING_TAG
    return JS_HOLE if is_sym_like?(p)
    ready_for(p)
    return JS_HOLE if !@exports.include?(p)
    get(p, self)

  -> set(p, v, receiver = JS_HOLE)
    false

  -> put_own(p, v)
    false

  -> delete_own(p)
    return p != SYM_TO_STRING_TAG if p.is_a?(JS:Symbol)
    return true if @deferred && p == "then"
    ready_for(p)
    !@exports.include?(p)

  -> own_keys
    js_mod_evaluate_sync(@mod) if @deferred
    @exports + [SYM_TO_STRING_TAG]

  -> enumerable?(p)
    d = get_own_property(p)
    d != nil && d.enumerable == true

  -> accessor?(p)
    false

  -> attr(p)
    return 0 if p == SYM_TO_STRING_TAG
    ATTR_W + ATTR_E

# ---- Module Record (§16.2.1) ----

+ ModuleRecord
  rw :url, :kind, :realm, :src, :ast, :analysis, :func, :status, :eval_error, :has_tla, :env
  rw :imports, :local_exports, :indirect_exports, :star_exports, :requested, :loaded_mods, :resolved_imports
  rw :namespace, :deferred_namespace, :import_meta, :synth_val
  rw :dfs_index, :dfs_ancestor_index, :cycle_root, :async_eval, :async_eval_order, :pending_async_deps, :async_parents, :top_level_cap

  -> new(@url, @kind, @realm)
    @src = nil
    @ast = nil
    @analysis = nil
    @func = nil
    @status = :new
    @eval_error = JS_HOLE
    @has_tla = false
    @env = nil
    @imports = []
    @local_exports = {}
    @indirect_exports = []
    @star_exports = []
    @requested = []
    @loaded_mods = {}
    @resolved_imports = {}
    @namespace = nil
    @deferred_namespace = nil
    @import_meta = nil
    @synth_val = nil
    @dfs_index = -1
    @dfs_ancestor_index = -1
    @cycle_root = nil
    @async_eval = false
    @async_eval_order = 0
    @pending_async_deps = 0
    @async_parents = []
    @top_level_cap = nil

# ---- Helpers ----

-> js_mod_req_key(spec, attrs)
  return spec if attrs == nil || attrs.size == 0
  ks = attrs.keys.sort
  sb = StringBuffer()
  sb.append(spec)
  i = 0
  while i < ks.size
    sb.append("\0")
    sb.append(ks[i])
    sb.append("=")
    sb.append(attrs[ks[i]])
    i += 1
  sb.to_s

-> js_mod_attrs_hash(attr_node)
  return nil if attr_node == nil
  h = {}
  i = 0
  while i < attr_node.list.size
    p = attr_node.list[i]
    h[p.a.str] = p.b.str
    i += 1
  h

-> js_mod_well_formed_str?(s)
  # Reject lone UTF-16 surrogates encoded as 3-byte WTF-8 sequences (ED A0 80 .. ED BF BF).
  n = s.size
  i = 0
  while i < n
    b = s.byte_at(i)
    if b == 0xED && i + 2 < n
      b1 = s.byte_at(i + 1)
      if b1 >= 0xA0 && b1 <= 0xBF
        return false
    i += 1
  true

# Does a module statement list contain a top-level `await`, `for await`, or `await using`?
-> js_mod_has_tla_list?(list)
  return false if list == nil
  i = 0
  while i < list.size
    return true if js_mod_has_tla_node?(list[i])
    i += 1
  false

-> js_mod_has_tla_node?(n)
  return false if n == nil || !n.is_a?(JsNode)
  k = n.kind
  return false if k == :function || k == :arrow || k == :function_decl
  return true if k == :await
  return true if k == :for_of && n.has?(F_AWAIT)
  return true if k == :var_decl && n.str == "await using"
  if k == :class || k == :class_decl
    return true if js_mod_has_tla_node?(n.a)
    if n.b.is_a?(Array)
      return true if js_mod_has_tla_list?(n.b)
    if n.list.is_a?(Array)
      i = 0
      while i < n.list.size
        m = n.list[i]
        return true if m != nil && m.has?(F_COMPUTED) && js_mod_has_tla_node?(m.a)
        return true if m != nil && m.c.is_a?(Array) && js_mod_has_tla_list?(m.c)
        i += 1
    return false
  return true if js_mod_has_tla_node?(n.a) || js_mod_has_tla_node?(n.b) || js_mod_has_tla_node?(n.c) || js_mod_has_tla_node?(n.d)
  if n.list.is_a?(Array)
    return true if js_mod_has_tla_list?(n.list)
  if n.a.is_a?(Array)
    return true if js_mod_has_tla_list?(n.a)
  false

# ---- Parsing & Static Validation (§16.2.1.6.1 ParseModule) ----

-> js_mod_add_req(mod, spec, attrs, phase)
  # RequestedModules preserves source order (duplicate spec+attrs+phase still tracked cleanly)
  mod.requested.push([spec, attrs, phase])
  nil

-> js_mod_parse(src, url, realm)
  p = JsParser.new(src, true)
  prog = nil
  begin
    prog = p.parse_program()
  rescue e
    p.release_simd_lex
    js_throw(js_make_error("SyntaxError", p.error == nil ? e.to_s : p.error.msg + " (line " + p.error.line.to_s + ", column " + p.error.col.to_s + ")"))
  p.release_simd_lex
  mod = JS:ModuleRecord.new(url, :source, realm)
  mod.src = src
  mod.ast = prog
  mod.status = :unlinked
  exported_names = {}
  imported_locals = {}
  source_imports = {}
  # Collect import & export entries and validate static early errors!
  i = 0
  while i < prog.list.size
    st = prog.list[i]
    k = st.kind
    if k == :import_decl
      spec = st.str
      attrs = js_mod_attrs_hash(st.b)
      phase = st.a == "defer" ? :defer : (st.a == "source" ? :source : :evaluation)
      js_mod_add_req(mod, spec, attrs, phase)
      j = 0
      while j < st.list.size
        sp = st.list[j]
        local = sp.str
        imp = sp.a
        js_throw(js_make_error("SyntaxError", "Invalid surrogate in import name")) if js_string?(imp) && !js_mod_well_formed_str?(imp)
        js_throw(js_make_error("SyntaxError", "Identifier '" + local + "' has already been declared")) if imported_locals.has_key?(local)
        imported_locals[local] = true
        source_imports[local] = [spec, attrs] if phase == :source
        mod.imports.push([local, spec, imp, attrs, phase])
        j += 1
    elsif k == :export_all
      spec = st.str
      attrs = js_mod_attrs_hash(st.b)
      js_mod_add_req(mod, spec, attrs, :evaluation)
      if st.a != nil
        ex = st.a
        js_throw(js_make_error("SyntaxError", "Invalid surrogate in export name")) if !js_mod_well_formed_str?(ex)
        js_throw(js_make_error("SyntaxError", "Duplicate export of '" + ex + "'")) if exported_names.has_key?(ex)
        exported_names[ex] = true
        mod.indirect_exports.push([ex, spec, :namespace, attrs])
      else
        mod.star_exports.push([spec, attrs])
    elsif k == :export_default
      js_throw(js_make_error("SyntaxError", "Duplicate export of 'default'")) if exported_names.has_key?("default")
      exported_names["default"] = true
      d = st.a
      if (d.kind == :function_decl || d.kind == :class_decl) && d.str != nil
        mod.local_exports["default"] = d.str
      else
        mod.local_exports["default"] = "*default*"
    elsif k == :export_named
      if st.b != nil
        # Re-export from module
        spec = st.b
        attrs = js_mod_attrs_hash(st.c)
        js_mod_add_req(mod, spec, attrs, :evaluation)
        j = 0
        while j < st.list.size
          sp = st.list[j]
          imp = sp.str
          ex = sp.a
          js_throw(js_make_error("SyntaxError", "Invalid surrogate in export name")) if !js_mod_well_formed_str?(imp) || !js_mod_well_formed_str?(ex)
          js_throw(js_make_error("SyntaxError", "Duplicate export of '" + ex + "'")) if exported_names.has_key?(ex)
          exported_names[ex] = true
          mod.indirect_exports.push([ex, spec, imp, attrs])
          j += 1
      elsif st.a != nil
        # Exported declaration
        d = st.a
        names = []
        if d.kind == :var_decl
          ta = JaAnalysis.new(nil, true)
          d.list.each ->(dec) ta.bound_names(dec.a, names)
        elsif (d.kind == :function_decl || d.kind == :class_decl) && d.str != nil
          names.push(d.str)
        names.each ->(nm)
          js_throw(js_make_error("SyntaxError", "Duplicate export of '" + nm + "'")) if exported_names.has_key?(nm)
          exported_names[nm] = true
          mod.local_exports[nm] = nm
      else
        # Local export clause `export { a, b as c }`
        j = 0
        while j < st.list.size
          sp = st.list[j]
          local = sp.str
          ex = sp.a
          js_throw(js_make_error("SyntaxError", "Invalid surrogate in export name")) if !js_mod_well_formed_str?(ex)
          js_throw(js_make_error("SyntaxError", "Duplicate export of '" + ex + "'")) if exported_names.has_key?(ex)
          exported_names[ex] = true
          if source_imports.has_key?(local)
            # Re-exported source-phase binding becomes indirect export with importName = :source
            si = source_imports[local]
            mod.indirect_exports.push([ex, si[0], :source, si[1]])
          else
            mod.local_exports[ex] = local
          j += 1
    i += 1
  # Run scope analysis in module mode!
  an = JaAnalysis.new(prog, true)
  an.src = src
  an.url = url
  an.run_module(mod)
  realm.analyses.push(an) if !JS_GC_ON[0] && realm != nil && realm.analyses != nil
  an.funcs.each ->(g)
    js_throw(js_make_error("SyntaxError", g.unsupported0.to_s)) if g.unsupported0 != nil
  mod.analysis = an
  mod.func = an.funcs[0]
  # Validate all local exports refer to declared module bindings (not undeclared globals)!
  sc = mod.func.scope
  mod.local_exports.each ->(ex, local)
    b = sc.names[local]
    if b == nil || b.kind == :global
      js_throw(js_make_error("SyntaxError", "Export '" + local + "' is not defined in module"))
  mod.has_tla = js_mod_has_tla_list?(prog.list)
  mod

-> js_mod_parse_json(src, url, realm)
  prev = JS_REALM[0]
  JS_REALM[0] = realm
  val = nil
  begin
    val = js_json_parse(src, nil)
  rescue ex
    JS_REALM[0] = prev
    raise ex
  JS_REALM[0] = prev
  mod = JS:ModuleRecord.new(url, :json, realm)
  mod.synth_val = val
  mod.local_exports["default"] = "default"
  mod.status = :unlinked
  mod

-> js_mod_parse_text(src, url, realm)
  mod = JS:ModuleRecord.new(url, :text, realm)
  mod.synth_val = src
  mod.local_exports["default"] = "default"
  mod.status = :unlinked
  mod

-> js_mod_parse_bytes(raw_str, url, realm)
  prev = JS_REALM[0]
  JS_REALM[0] = realm
  ta = nil
  begin
    n = raw_str.size
    ab = JS:ArrayBuffer.new(js_root_shape(realm.intrinsic("ArrayBuffer.prototype"), SP_INLINE, SP_IBASE), "ArrayBuffer")
    ab.data = ByteArray.new(n)
    ab.blen = n
    ab.immutable = true
    i = 0
    while i < n
      ab.data.set(i, raw_str.byte_at(i))
      i += 1
    ta = JS:TypedArray.new(js_root_shape(realm.intrinsic("Uint8Array.prototype"), SP_INLINE, SP_IBASE), "Uint8Array")
    ta.buffer = ab
    ta.offset = 0
    ta.len = n
    ta.kind = 1
  rescue ex
    JS_REALM[0] = prev
    raise ex
  JS_REALM[0] = prev
  mod = JS:ModuleRecord.new(url, :bytes, realm)
  mod.synth_val = ta
  mod.local_exports["default"] = "default"
  mod.status = :unlinked
  mod

# ---- Loading Dependencies ----

-> js_mod_get_host_source(realm)
  key = "<module source>\0module_source"
  existing = realm.modules[key]
  return existing if existing != nil
  prev = JS_REALM[0]
  JS_REALM[0] = realm
  sub_proto = js_new_object(realm.intrinsic("%AbstractModuleSource.prototype%"))
  ms = js_new_special(sub_proto, "ModuleSource")
  ms.internal = "ModuleSource"
  JS_REALM[0] = prev
  mod = JS:ModuleRecord.new("<module source>", :module_source, realm)
  mod.synth_val = ms
  mod.status = :evaluated
  realm.modules[key] = mod
  mod

-> js_mod_load_dep(ref_mod, ref_url, spec, attrs, phase, realm)
  return js_mod_get_host_source(realm) if spec == "<module source>"
  js_throw_type("No module loader configured") if JS_MODULE_LOADER_HOOK[0] == nil
  loaded = JS_MODULE_LOADER_HOOK[0].call(ref_url, spec, attrs, phase)
  # loaded = [canon_url, kind, content_str]
  canon_url = loaded[0]
  kind = loaded[1]
  content = loaded[2]
  if phase == :source
    # GetModuleSource of SourceTextModule always throws SyntaxError (§16.2.1.7.2)!
    js_throw(js_make_error("SyntaxError", "Source phase import is not supported for module '" + spec + "'"))
  cache_key = canon_url + "\0" + kind.to_s
  existing = realm.modules[cache_key]
  return existing if existing != nil
  m = nil
  if kind == :json
    m = js_mod_parse_json(content, canon_url, realm)
  elsif kind == :text
    m = js_mod_parse_text(content, canon_url, realm)
  elsif kind == :bytes
    m = js_mod_parse_bytes(content, canon_url, realm)
  else
    m = js_mod_parse(content, canon_url, realm)
  realm.modules[cache_key] = m
  m

-> js_mod_load_graph(mod, visited)
  return nil if visited.has_key?(mod)
  visited[mod] = true
  i = 0
  while i < mod.requested.size
    req = mod.requested[i]
    spec = req[0]
    attrs = req[1]
    phase = req[2]
    rk = js_mod_req_key(spec, attrs)
    dep = mod.loaded_mods[rk]
    if dep == nil
      dep = js_mod_load_dep(mod, mod.url, spec, attrs, phase, mod.realm)
      mod.loaded_mods[rk] = dep
    js_mod_load_graph(dep, visited) if phase != :source
    i += 1
  nil

# ---- ResolveExport & GetExportedNames & GetModuleNamespace (§16.2.1.6) ----

-> js_mod_resolve_export(mod, export_name, resolve_set)
  i = 0
  while i < resolve_set.size
    rs = resolve_set[i]
    return nil if rs[0] == mod && rs[1] == export_name
    i += 1
  resolve_set.push([mod, export_name])
  if mod.kind != :source
    return export_name == "default" ? [:synth, mod] : nil
  if mod.local_exports.has_key?(export_name)
    local = mod.local_exports[export_name]
    # Check if local is itself an import binding (re-exported import!)
    imp = mod.resolved_imports[local]
    return imp if imp != nil
    # During linking before resolved_imports populated, check mod.imports!
    j = 0
    while j < mod.imports.size
      ie = mod.imports[j]
      if ie[0] == local
        dep = mod.loaded_mods[js_mod_req_key(ie[1], ie[3])]
        return nil if dep == nil
        return [:namespace, dep, ie[4] == :defer] if ie[2] == :namespace
        return [:source, dep] if ie[4] == :source
        return js_mod_resolve_export(dep, ie[2], resolve_set)
      j += 1
    return [:local, mod, local]
  j = 0
  while j < mod.indirect_exports.size
    ie = mod.indirect_exports[j]
    if ie[0] == export_name
      dep = mod.loaded_mods[js_mod_req_key(ie[1], ie[3])]
      return nil if dep == nil
      return [:namespace, dep, false] if ie[2] == :namespace
      return [:source, dep] if ie[2] == :source
      return js_mod_resolve_export(dep, ie[2], resolve_set)
    j += 1
  return nil if export_name == "default"
  star_res = nil
  j = 0
  while j < mod.star_exports.size
    se = mod.star_exports[j]
    dep = mod.loaded_mods[js_mod_req_key(se[0], se[1])]
    if dep != nil
      res = js_mod_resolve_export(dep, export_name, resolve_set)
      return :ambiguous if res == :ambiguous
      if res != nil
        if star_res == nil
          star_res = res
        elsif !js_mod_same_resolved?(star_res, res)
          return :ambiguous
    j += 1
  star_res

-> js_mod_same_resolved?(a, b)
  return false if a[0] != b[0] || a[1] != b[1]
  return a[2] == b[2] if a.size > 2 && b.size > 2
  true

-> js_mod_get_exported_names(mod, export_star_set)
  return [] if export_star_set.include?(mod)
  export_star_set.push(mod)
  names = []
  if mod.kind != :source
    return ["default"]
  mod.local_exports.keys.each ->(k) names.push(k) if !names.include?(k)
  mod.indirect_exports.each ->(ie) names.push(ie[0]) if !names.include?(ie[0])
  mod.star_exports.each ->(se)
    dep = mod.loaded_mods[js_mod_req_key(se[0], se[1])]
    if dep != nil
      sub = js_mod_get_exported_names(dep, export_star_set)
      sub.each ->(nm)
        names.push(nm) if nm != "default" && !names.include?(nm)
  names

-> js_mod_sort_names(names)
  # Sort exported names by UTF-16 code unit order (ECMA-262 §16.2.1.10 step 4)
  out = names.dup
  n = out.size
  i = 1
  while i < n
    cur = out[i]
    j = i - 1
    while j >= 0 && js_lt(cur, out[j])
      out[j + 1] = out[j]
      j -= 1
    out[j + 1] = cur
    i += 1
  out

-> js_mod_get_namespace(mod, deferred = false)
  if deferred
    return mod.deferred_namespace if mod.deferred_namespace != nil
  else
    return mod.namespace if mod.namespace != nil
  raw = js_mod_get_exported_names(mod, [])
  unambig = []
  i = 0
  while i < raw.size
    nm = raw[i]
    res = js_mod_resolve_export(mod, nm, [])
    unambig.push(nm) if res != nil && res != :ambiguous
    i += 1
  sorted = js_mod_sort_names(unambig)
  ns = JS:ModuleNamespace.new(js_mod_ns_shape(), mod, sorted, deferred)
  if deferred
    mod.deferred_namespace = ns
  else
    mod.namespace = ns
  ns

# Read a live resolved binding (throws ReferenceError if TDZ!).
-> js_mod_read_resolved(rb)
  kind = rb[0]
  m = rb[1]
  return m.synth_val if kind == :synth || kind == :source
  return js_mod_get_namespace(m, rb[2]) if kind == :namespace
  local = rb[2]
  b = m.func.scope.names[local]
  js_throw_reference("Cannot access '" + local + "' before initialization") if b == nil || m.env == nil
  v = js_env_get(m.env, b.slot)
  js_throw_reference("Cannot access '" + local + "' before initialization") if v == JS_TDZ
  v

-> js_mod_read_import(mod, local_name)
  rb = mod.resolved_imports[local_name]
  js_throw_reference("Cannot access '" + local_name + "' before initialization") if rb == nil
  js_mod_read_resolved(rb)

-> js_mod_get_meta(mod)
  if mod.import_meta == nil
    o = js_new_object(nil)
    o.define("url", mod.url.to_s, ATTR_DEFAULT)
    mod.import_meta = o
  mod.import_meta

# ---- Tarjan DFS Linking (§16.2.1.5.2) ----

-> js_mod_link(mod)
  js_mod_load_graph(mod, {})
  return nil if mod.status == :linked || mod.status == :evaluating || mod.status == :evaluating_async || mod.status == :evaluated
  stack = []
  begin
    js_mod_inner_link(mod, stack, 0)
  rescue ex
    i = 0
    while i < stack.size
      m = stack[i]
      if m.status == :linking
        m.status = :unlinked
        m.dfs_index = -1
        m.dfs_ancestor_index = -1
        m.env = nil
      i += 1
    raise ex
  nil

-> js_mod_inner_link(mod, stack, index)
  if mod.kind != :source
    mod.status = :linked if mod.status == :unlinked
    return index
  return index if mod.status == :linking || mod.status == :linked || mod.status == :evaluating || mod.status == :evaluating_async || mod.status == :evaluated
  mod.status = :linking
  mod.dfs_index = index
  mod.dfs_ancestor_index = index
  index += 1
  stack.push(mod)
  i = 0
  while i < mod.requested.size
    req = mod.requested[i]
    if req[2] != :source
      dep = mod.loaded_mods[js_mod_req_key(req[0], req[1])]
      index = js_mod_inner_link(dep, stack, index)
      if dep.status == :linking
        mod.dfs_ancestor_index = dep.dfs_ancestor_index if dep.dfs_ancestor_index < mod.dfs_ancestor_index
    i += 1
  js_mod_init_env(mod)
  if mod.dfs_ancestor_index == mod.dfs_index
    while true
      m = stack.pop
      m.status = :linked
      break if m == mod
  index

-> js_mod_init_env(mod)
  # 1. Verify all indirect exports resolve unambiguously
  i = 0
  while i < mod.indirect_exports.size
    ie = mod.indirect_exports[i]
    res = js_mod_resolve_export(mod, ie[0], [])
    js_throw(js_make_error("SyntaxError", "The requested module '" + ie[1] + "' does not provide an export named '" + ie[2].to_s + "'")) if res == nil || res == :ambiguous
    i += 1
  # 2. Allocate module environment record (all bindings live in mod.env!)
  sc = mod.func.scope
  env = JS:EnvN.new(nil, sc.env_count)
  js_gc_reg(env) if JS_GC_ON[0]
  mod.env = env
  # Initialize TDZ for lexical/class/default bindings
  if sc.tdz_bindings != nil
    sc.tdz_bindings.each ->(b)
      js_env_set(env, b.slot, JS_TDZ) if b.slot >= 0
  # 3. Resolve all import bindings
  i = 0
  while i < mod.imports.size
    ie = mod.imports[i]
    local = ie[0]
    spec = ie[1]
    imp_name = ie[2]
    attrs = ie[3]
    phase = ie[4]
    dep = mod.loaded_mods[js_mod_req_key(spec, attrs)]
    if imp_name == :namespace
      ns = js_mod_get_namespace(dep, phase == :defer)
      mod.resolved_imports[local] = [:namespace, dep, phase == :defer]
      b = sc.names[local]
      js_env_set(env, b.slot, ns) if b != nil && b.slot >= 0
    elsif phase == :source
      js_throw(js_make_error("SyntaxError", "Module '" + spec + "' does not support source-phase import")) if dep.kind != :module_source
      mod.resolved_imports[local] = [:source, dep]
      b = sc.names[local]
      js_env_set(env, b.slot, dep.synth_val) if b != nil && b.slot >= 0
    else
      rb = js_mod_resolve_export(dep, imp_name, [])
      js_throw(js_make_error("SyntaxError", "The requested module '" + spec + "' does not provide an export named '" + imp_name.to_s + "'")) if rb == nil || rb == :ambiguous
      mod.resolved_imports[local] = rb
    i += 1
  # 4. Hoist all top-level function declarations (including `export function` and `export default function`)!
  prev = JS_REALM[0]
  JS_REALM[0] = mod.realm
  act = wk_act(mod.func, nil, env, nil, mod.func.nlocals)
  act.env = env
  act.env_at_entry = env
  begin
    list = mod.ast.list
    i = 0
    while i < list.size
      st = list[i]
      fn_node = nil
      target_b = nil
      if st.kind == :function_decl
        fn_node = st
        target_b = sc.names[st.str]
      elsif st.kind == :export_named && st.a != nil && st.a.kind == :function_decl
        fn_node = st.a
        target_b = sc.names[fn_node.str]
      elsif st.kind == :export_default && st.a != nil && st.a.kind == :function_decl
        fn_node = st.a
        target_b = sc.names[fn_node.str != nil ? fn_node.str : "*default*"]
      if fn_node != nil && target_b != nil
        jf = fn_node.x
        fo = js_closure(wk_code(jf), wk_env_for(jf, act))
        js_env_set(env, target_b.slot, fo) if target_b.slot >= 0
      i += 1
  rescue ex
    wk_release(act)
    JS_REALM[0] = prev
    raise ex
  wk_release(act)
  JS_REALM[0] = prev
  nil

# ---- Tarjan DFS Evaluation + Top-Level Await (§16.2.1.5.3) ----

# IsModuleSCCEvaluated ( module ) — ECMA-262 import-defer
-> js_mod_scc_evaluated?(mod)
  if mod.cycle_root != nil
    return mod.cycle_root.status == :evaluated
  mod.status == :evaluated

-> js_mod_gather_async_deps(mod, seen, out)
  return nil if seen.has_key?(mod)
  seen[mod] = true
  return nil if mod.kind != :source
  return nil if mod.status == :evaluating
  return nil if js_mod_scc_evaluated?(mod) && mod.eval_error == JS_HOLE
  if mod.has_tla || mod.async_eval
    out.push(mod) if !out.include?(mod)
    return nil
  i = 0
  while i < mod.requested.size
    req = mod.requested[i]
    if req[2] != :source
      dep = mod.loaded_mods[js_mod_req_key(req[0], req[1])]
      js_mod_gather_async_deps(dep, seen, out) if dep != nil
    i += 1
  nil

-> js_mod_evaluate(mod)
  r = mod.realm
  prev = JS_REALM[0]
  JS_REALM[0] = r
  m = mod
  if (m.status == :evaluating_async || m.status == :evaluated) && m.cycle_root != nil
    m = m.cycle_root
  if m.top_level_cap != nil
    JS_REALM[0] = prev
    return m.top_level_cap.promise
  stack = []
  cap = js_new_capability()
  m.top_level_cap = cap
  begin
    js_mod_inner_eval(m, stack, 0)
  rescue ex
    ev = js_error_value(ex)
    i = 0
    while i < stack.size
      sm = stack[i]
      sm.status = :evaluated
      sm.eval_error = ev
      i += 1
    m.status = :evaluated
    m.eval_error = ev
    js_call_arr(cap.reject, nil, [ev])
    JS_REALM[0] = prev
    return cap.promise
  if !m.async_eval
    js_call_arr(cap.resolve, nil, [nil])
  JS_REALM[0] = prev
  cap.promise

-> js_mod_inner_eval(mod, stack, index)
  if mod.kind != :source
    mod.status = :evaluated
    return index
  if mod.status == :evaluating_async || mod.status == :evaluated
    if mod.eval_error != JS_HOLE
      js_throw(mod.eval_error)
    return index
  return index if mod.status == :evaluating
  mod.status = :evaluating
  mod.dfs_index = index
  mod.dfs_ancestor_index = index
  mod.pending_async_deps = 0
  index += 1
  stack.push(mod)
  # Build evaluationList (handles import-defer: deferred imports only evaluate transitive async deps!)
  eval_list = []
  i = 0
  while i < mod.requested.size
    req = mod.requested[i]
    phase = req[2]
    if phase != :source
      dep = mod.loaded_mods[js_mod_req_key(req[0], req[1])]
      if phase == :defer
        js_mod_gather_async_deps(dep, {}, eval_list)
      else
        eval_list.push(dep) if !eval_list.include?(dep)
    i += 1
  i = 0
  while i < eval_list.size
    dep = eval_list[i]
    index = js_mod_inner_eval(dep, stack, index)
    if dep.status == :evaluating
      mod.dfs_ancestor_index = dep.dfs_ancestor_index if dep.dfs_ancestor_index < mod.dfs_ancestor_index
    else
      dep = dep.cycle_root if dep.cycle_root != nil
      if dep.status == :evaluated && dep.eval_error != JS_HOLE
        js_throw(dep.eval_error)
    if dep.async_eval
      mod.pending_async_deps += 1
      dep.async_parents.push(mod)
    i += 1
  if mod.pending_async_deps > 0 || mod.has_tla
    mod.async_eval = true
    JS_MOD_ASYNC_ORDER[0] = JS_MOD_ASYNC_ORDER[0] + 1
    mod.async_eval_order = JS_MOD_ASYNC_ORDER[0]
    if mod.pending_async_deps == 0
      js_mod_exec_async(mod)
  else
    js_mod_exec_sync(mod)
  if mod.dfs_ancestor_index == mod.dfs_index
    while true
      m = stack.pop
      m.cycle_root = mod
      if !m.async_eval
        m.status = :evaluated
      else
        m.status = :evaluating_async
      break if m == mod
  index

-> js_mod_exec_sync(mod)
  return nil if mod.kind != :source
  prev_r = JS_REALM[0]
  prev_url = JS_CURRENT_URL[0]
  JS_REALM[0] = mod.realm
  JS_CURRENT_URL[0] = mod.url
  f = mod.func
  act = wk_act(f, nil, mod.env, nil, f.nlocals)
  act.env = mod.env
  act.env_at_entry = mod.env
  act.caller = JS_CUR_ACT[0]
  JS_CUR_ACT[0] = act
  has_disp = f.body_scope != nil && f.body_scope.has_dispose
  my_cap = has_disp ? JS:DisposeCap.new : nil
  act.disp = my_cap if has_disp
  begin
    wk_stmts(mod.ast.list, act)
  rescue ex
    JS_CUR_ACT[0] = act.caller
    wk_release(act)
    JS_CURRENT_URL[0] = prev_url
    if has_disp
      begin
        js_dispose_resources_sync(my_cap, true, js_error_value(ex))
      rescue ex2
        JS_REALM[0] = prev_r
        raise ex2
    JS_REALM[0] = prev_r
    raise ex
  JS_CUR_ACT[0] = act.caller
  wk_release(act)
  JS_CURRENT_URL[0] = prev_url
  if has_disp
    begin
      js_dispose_resources_sync(my_cap, false, nil)
    rescue ex3
      JS_REALM[0] = prev_r
      raise ex3
  JS_REALM[0] = prev_r
  nil

-> js_mod_exec_async(mod)
  r = mod.realm
  prev_r = JS_REALM[0]
  prev_url = JS_CURRENT_URL[0]
  JS_REALM[0] = r
  JS_CURRENT_URL[0] = mod.url
  cap = js_new_capability()
  on_f = ->(v)
    js_mod_async_fulfilled(mod)
    nil
  on_r = ->(err)
    js_mod_async_rejected(mod, err)
    nil
  js_perform_then(cap.promise, JS:Reaction.new(nil, :fulfill, on_f), JS:Reaction.new(nil, :reject, on_r))
  if !mod.has_tla
    # Sync module waiting on async dependencies: execute synchronously and settle cap!
    begin
      js_mod_exec_sync(mod)
      js_call_arr(cap.resolve, nil, [nil])
    rescue ex
      js_call_arr(cap.reject, nil, [js_error_value(ex)])
    JS_CURRENT_URL[0] = prev_url
    JS_REALM[0] = prev_r
    return nil
  # Top-level await module: run via stackless coroutine SM!
  f = mod.func
  act = WkAct.new(f, nil, mod.env, nil, f.nlocals)
  act.env = mod.env
  act.env_at_entry = mod.env
  sc = js_sm_compile_module(f)
  frame = JS:SmFrame.new(sc, act)
  frame.promise = cap.promise
  frame.state = :running
  js_sm_run(frame, nil, nil, r.jobs)
  js_sm_async_after(frame, r.jobs)
  JS_CURRENT_URL[0] = prev_url
  JS_REALM[0] = prev_r
  nil

-> js_mod_gather_parents(mod, exec_list)
  i = 0
  while i < mod.async_parents.size
    m = mod.async_parents[i]
    if !exec_list.include?(m) && (m.cycle_root == nil || m.cycle_root.eval_error == JS_HOLE)
      if m.pending_async_deps > 0
        m.pending_async_deps -= 1
      if m.pending_async_deps == 0
        exec_list.push(m)
        js_mod_gather_parents(m, exec_list) if !m.has_tla
    i += 1
  nil

-> js_mod_async_fulfilled(mod)
  return nil if mod.status == :evaluated
  mod.async_eval = false
  mod.status = :evaluated
  if mod.top_level_cap != nil
    js_call_arr(mod.top_level_cap.resolve, nil, [nil])
  exec_list = []
  js_mod_gather_parents(mod, exec_list)
  # Sort exec_list by [[AsyncEvaluationOrder]] (DFS invariant!)
  i = 1
  while i < exec_list.size
    cur = exec_list[i]
    j = i - 1
    while j >= 0 && cur.async_eval_order < exec_list[j].async_eval_order
      exec_list[j + 1] = exec_list[j]
      j -= 1
    exec_list[j + 1] = cur
    i += 1
  i = 0
  while i < exec_list.size
    m = exec_list[i]
    if m.status == :evaluated
      nil
    elsif m.has_tla
      js_mod_exec_async(m)
    else
      begin
        js_mod_exec_sync(m)
        m.async_eval = false
        m.status = :evaluated
        if m.top_level_cap != nil
          js_call_arr(m.top_level_cap.resolve, nil, [nil])
      rescue ex
        js_mod_async_rejected(m, js_error_value(ex))
    i += 1
  nil

-> js_mod_async_rejected(mod, err)
  return nil if mod.status == :evaluated
  mod.async_eval = false
  mod.status = :evaluated
  mod.eval_error = err
  if mod.top_level_cap != nil
    js_call_arr(mod.top_level_cap.reject, nil, [err])
  i = 0
  while i < mod.async_parents.size
    js_mod_async_rejected(mod.async_parents[i], err)
    i += 1
  nil

# ReadyForSyncExecution ( module, seen ) — ECMA-262 import-defer
-> js_mod_ready_for_sync?(mod, seen)
  return true if seen.has_key?(mod)
  seen[mod] = true
  return true if mod.kind != :source
  return true if js_mod_scc_evaluated?(mod)
  return false if mod.status == :evaluating || mod.status == :evaluating_async
  return false if mod.cycle_root != nil
  return false if mod.has_tla
  i = 0
  while i < mod.requested.size
    req = mod.requested[i]
    if req[2] != :source
      dep = mod.loaded_mods[js_mod_req_key(req[0], req[1])]
      if dep != nil && !js_mod_ready_for_sync?(dep, seen)
        return false
    i += 1
  true

# Synchronous evaluation for deferred namespace triggering (§10.4.6 EnsureDeferredNamespaceEvaluation)
-> js_mod_evaluate_sync(mod)
  return nil if mod.kind != :source
  if mod.status == :evaluated
    js_throw(mod.eval_error) if mod.eval_error != JS_HOLE
    return nil
  js_throw_type("Cannot synchronously evaluate deferred module while evaluating or async") if !js_mod_ready_for_sync?(mod, {})
  stack = []
  begin
    js_mod_inner_eval(mod, stack, 0)
  rescue ex
    ev = js_error_value(ex)
    stack.each ->(sm)
      sm.status = :evaluated
      sm.eval_error = ev
    mod.status = :evaluated
    mod.eval_error = ev
    js_throw(ev)
  js_throw_type("Cannot synchronously evaluate a module with asynchronous dependencies") if mod.async_eval
  nil

# ---- Dynamic import(), import.defer(), import.source() ----

-> js_mod_dynamic_import_run(r, cap, ref_url, spec, attrs, phase)
  prev = JS_REALM[0]
  JS_REALM[0] = r
  begin
    dep = js_mod_load_dep(nil, ref_url, spec, attrs, phase, r)
    if phase == :source
      if dep.kind == :module_source
        js_call_arr(cap.resolve, nil, [dep.synth_val])
      else
        js_call_arr(cap.reject, nil, [js_make_error("SyntaxError", "Source phase import is not supported for this module")])
      JS_REALM[0] = prev
      return nil
    js_mod_link(dep)
    if phase == :defer
      adeps = []
      js_mod_gather_async_deps(dep, {}, adeps)
      if adeps.size == 0
        js_call_arr(cap.resolve, nil, [js_mod_get_namespace(dep, true)])
        JS_REALM[0] = prev
        return nil
      rem = [adeps.size]
      failed = [false]
      ai = 0
      while ai < adeps.size
        ep = js_mod_evaluate(adeps[ai])
        on_f = ->(v)
          if !failed[0]
            rem[0] -= 1
            js_call_arr(cap.resolve, nil, [js_mod_get_namespace(dep, true)]) if rem[0] == 0
          nil
        on_r = ->(err)
          if !failed[0]
            failed[0] = true
            js_call_arr(cap.reject, nil, [err])
          nil
        js_perform_then(ep, JS:Reaction.new(nil, :fulfill, on_f), JS:Reaction.new(nil, :reject, on_r))
        ai += 1
      JS_REALM[0] = prev
      return nil
    ep = js_mod_evaluate(dep)
    on_f = ->(v)
      js_call_arr(cap.resolve, nil, [js_mod_get_namespace(dep, false)])
      nil
    on_r = ->(err)
      js_call_arr(cap.reject, nil, [err])
      nil
    js_perform_then(ep, JS:Reaction.new(nil, :fulfill, on_f), JS:Reaction.new(nil, :reject, on_r))
  rescue ex
    js_call_arr(cap.reject, nil, [js_error_value(ex)])
  JS_REALM[0] = prev
  nil

-> js_mod_dynamic_import(ref_url, spec_val, opts_val, phase)
  r = js_realm()
  cap = js_new_capability()
  spec = nil
  attrs = nil
  begin
    spec = js_to_string(spec_val)
    if opts_val != nil
      js_throw_type("import() options must be an object") if !js_object?(opts_val)
      with_obj = jget(opts_val, "with")
      if with_obj != nil
        js_throw_type("import() options.with must be an object") if !js_object?(with_obj)
        attrs = {}
        ks = jown_keys(with_obj)
        ki = 0
        while ki < ks.size
          k = ks[ki]
          if js_string?(k)
            d = jget_own_property(with_obj, k)
            if d != nil && d.enumerable == true
              val = jget(with_obj, k)
              js_throw_type("Import attribute value must be a string") if !js_string?(val)
              attrs[k] = val
          ki += 1
  rescue ex
    js_call_arr(cap.reject, nil, [js_error_value(ex)])
    return cap.promise
  # Enqueue ContinueDynamicImport asynchronously so it never preempts active DFS module evaluation!
  job = ->() js_mod_dynamic_import_run(r, cap, ref_url, spec, attrs, phase)
  r.enqueue_job(job)
  cap.promise

# ---- ShadowRealm.prototype.importValue wiring ----

-> js_mod_shadow_import_value(sr, caller_r, spec_str, export_name)
  ref_url = JS_CURRENT_URL[0]
  prev = JS_REALM[0]
  JS_REALM[0] = caller_r
  cap = js_new_capability()
  JS_REALM[0] = sr
  begin
    dep = js_mod_load_dep(nil, ref_url, spec_str, nil, :evaluation, sr)
    js_mod_link(dep)
    ep = js_mod_evaluate(dep)
    on_f = ->(v)
      p2 = JS_REALM[0]
      JS_REALM[0] = caller_r
      begin
        ns = js_mod_get_namespace(dep, false)
        if !ns.exports.include?(export_name)
          js_call_arr(cap.reject, nil, [js_make_error("TypeError", "Export '" + export_name + "' not found")])
        else
          ev_val = ns.get(export_name, ns)
          wval = js_get_wrapped_value(caller_r, ev_val)
          js_call_arr(cap.resolve, nil, [wval])
      rescue ex2
        js_call_arr(cap.reject, nil, [js_make_error("TypeError", "ShadowRealm.importValue failed")])
      JS_REALM[0] = p2
      nil
    on_r = ->(err)
      p2 = JS_REALM[0]
      JS_REALM[0] = caller_r
      js_call_arr(cap.reject, nil, [js_make_error("TypeError", "ShadowRealm.importValue module evaluation failed")])
      JS_REALM[0] = p2
      nil
    js_perform_then(ep, JS:Reaction.new(nil, :fulfill, on_f), JS:Reaction.new(nil, :reject, on_r))
  rescue ex
    JS_REALM[0] = caller_r
    js_call_arr(cap.reject, nil, [js_make_error("TypeError", "ShadowRealm.importValue module load failed")])
  JS_REALM[0] = prev
  cap.promise

JS_SHADOW_IMPORT_HOOK[0] = ->(sr, caller_r, spec_str, export_name) js_mod_shadow_import_value(sr, caller_r, spec_str, export_name)

# ---- Top-level Module Entry Points ----

-> js_run_module(src, url)
  r = js_realm()
  mod = js_mod_parse(src, url, r)
  r.modules[url + "\0source"] = mod
  js_mod_link(mod)
  js_mod_evaluate(mod)

-> js_check_module(src, url)
  js_mod_parse(src, url, js_realm())
  nil
