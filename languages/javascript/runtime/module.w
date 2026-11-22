# blade/js/module — ES modules: static import/export with live bindings, dynamic import(),
# import.meta. Every module-level binding lives in a JsCell, so an importing module reads
# the exporter's cell directly (live, and TDZ until the exporter initializes it).
#
# The embedder supplies JS_MODULE_HOST[0], an object with
#   resolve(specifier, base_url) -> absolute URL String (raise for a bad specifier)
#   load(url)                    -> source String

JS_MODULE_HOST = [nil]

+ JsModule
  rw :url, :exports, :stars, :status, :run, :ns, :error, :meta, :deps, :defaults

  -> new(@url)
    @exports = {}
    @stars = []
    @status = :new
    @run = nil
    @ns = nil
    @error = nil
    @meta = nil
    @deps = []

# Resolve export name in m (following export *): the JsCell, or nil.
-> js_module_resolve_export(m, name, seen)
  return nil if seen.include?(m)
  seen.push(m)
  c = m.exports[name]
  return c if c != nil
  return nil if name == "default"
  m.stars.each ->(d)
    r = js_module_resolve_export(d, name, seen)
    return r if r != nil
  nil

-> js_module_export_names(m, seen, out)
  return out if seen.include?(m)
  seen.push(m)
  m.exports.keys.each ->(k) out.push(k) if !out.include?(k)
  m.stars.each ->(d)
    js_module_export_names(d, seen, []).each ->(k) out.push(k) if k != "default" && !out.include?(k)
  out

# The module namespace object: a getter per export reading the live cell.
-> js_module_namespace(m)
  return m.ns if m.ns != nil
  r = JS_REALM[0]
  ns = JsObject.new(JS_NULL, "Module")
  names = js_module_export_names(m, [], []).sort_by(->(k) k)
  names.each ->(k)
    c = js_module_resolve_export(m, k, [])
    if c != nil
      g = r.native(k, 0, ->(this, args, nt) js_tdz_check(c.v, k))
      ns.define_accessor(k, g, nil, ATTR_E)
  ns.define(SYM_TO_STRING_TAG, "Module", 0)
  ns.extensible = false
  m.ns = ns
  ns

JS_MODULES = {}

# Get (load, link and compile) the module at url; evaluation is separate.
-> js_module_get(url)
  m = JS_MODULES[url]
  return m if m != nil
  h = JS_MODULE_HOST[0]
  js_throw_type("modules are not available here") if h == nil
  src = h.load(url)
  raise JsThrow.new(js_type_error("Failed to fetch dynamically imported module: " + url)) if src == nil
  js_module_from_source(url, src)

-> js_module_from_source(url, src)
  m = JsModule.new(url)
  JS_MODULES[url] = m
  prog = js_parse_or_throw(src, true)
  comp = JsCompiler.new(src)
  comp.url = url.to_s
  m.status = :linking
  comp.compile_module(prog, m)
  m.status = :linked
  m

# Evaluate m after its dependencies (once; cycles see partially initialized cells).
-> js_module_evaluate(m)
  return nil if m.status == :evaluating || m.status == :done
  raise JsThrow.new(m.error) if m.status == :error
  m.status = :evaluating
  begin
    m.deps.each ->(d) js_module_evaluate(d)
    m.run.call()
  rescue e
    m.status = :error
    m.error = js_error_value(e)
    raise e
  m.status = :done
  nil

-> js_module_resolve(spec, base)
  h = JS_MODULE_HOST[0]
  js_throw_type("modules are not available here") if h == nil
  h.resolve(spec, base)

-> js_dynamic_import(spec)
  cap = js_new_capability()
  begin
    base = JS_CURRENT_MODULE[0] == nil ? nil : JS_CURRENT_MODULE[0].url
    url = js_module_resolve(js_to_string(spec), base)
    m = js_module_get(url)
    js_module_evaluate(m)
    js_call(cap.resolve, nil, [js_module_namespace(m)])
  rescue e
    js_call(cap.reject, nil, [js_error_value(e)])
  cap.promise

JS_CURRENT_MODULE = [nil]

-> js_import_meta
  m = JS_CURRENT_MODULE[0]
  return JS_REALM[0].new_object if m == nil
  js_module_meta(m)

-> js_module_meta(m)
  return m.meta if m.meta != nil
  r = JS_REALM[0]
  o = JsObject.new(JS_NULL, "Object")
  o.put_own("url", m.url)
  mm = m
  o.put_own("resolve", r.native("resolve", 1, ->(this, args, nt) js_module_resolve(js_to_string(js_arg(args, 0)), mm.url)))
  m.meta = o
  o

+ JsCompiler
  # A module body: top-level bindings are cells; imports bind to the exporters' cells.
  -> compile_module(prog, m)
    sc = JsScope.new(:module, nil, true)
    sc.strict = true
    @module = m
    # own declarations first (so a cyclic importer can link to them)
    vn = var_names(prog.list, [], true, true)
    vn.each ->(nm) js_mod_cell(sc, nm, :var, false)
    fns = []
    prog.list.each ->(s0)
      s = s0
      s = s.a if (s.kind == :export_named || s.kind == :export_default) && s.a != nil && (s.a.kind == :function_decl || s.a.kind == :class_decl || s.a.kind == :var_decl)
      if s.kind == :function_decl && s.str != nil
        js_mod_cell(sc, s.str, :var, false)
        fns.push(s)
    lex_decls(prog.list, true).each ->(d) js_mod_cell(sc, d[0], d[1], true)
    has_default = false
    prog.list.each ->(s)
      if s.kind == :export_default
        has_default = true
        a = s.a
        if (a.kind == :function_decl || a.kind == :class_decl) && a.str != nil
          m.exports["default"] = sc.names[a.str].cell
        else
          b = js_mod_cell(sc, "*default*", :let, true)
          m.exports["default"] = b.cell
          if a.kind == :function_decl
            fns.push(a)
    # exports of local names
    prog.list.each ->(s)
      if s.kind == :export_named && s.b == nil
        if s.a != nil
          names = []
          if s.a.kind == :var_decl
            s.a.list.each ->(d) bound_names(d.a, names)
          elsif s.a.str != nil
            names.push(s.a.str)
          names.each ->(nm) m.exports[nm] = sc.names[nm].cell
        else
          s.list.each ->(sp)
            b = sc.names[sp.str]
            if b != nil && b.cell != nil
              m.exports[sp.a] = b.cell
    # load dependencies and bind imports / re-exports
    prog.list.each ->(s)
      if s.kind == :import_decl
        dep = js_module_get(js_module_resolve(s.str, m.url))
        m.deps.push(dep) if !m.deps.include?(dep)
        s.list.each ->(sp)
          if sp.a == "*"
            c = JsCell.new(sp.str, js_module_namespace(dep), true)
            b = JsBinding.new(sp.str, :import, sc, -1)
            b.cell = c
            b.is_const = true
            sc.names[sp.str] = b
          else
            c = js_module_resolve_export(dep, sp.a, [])
            raise JsThrow.new(js_syntax_error("The requested module '" + s.str + "' does not provide an export named '" + sp.a + "'")) if c == nil
            b = JsBinding.new(sp.str, :import, sc, -1)
            b.cell = c
            b.is_const = true
            sc.names[sp.str] = b
      elsif s.kind == :export_named && s.b != nil
        dep = js_module_get(js_module_resolve(s.b.is_a?(String) ? s.b : s.b.str, m.url))
        m.deps.push(dep) if !m.deps.include?(dep)
        s.list.each ->(sp)
          if sp.str == "*"
            m.exports[sp.a] = JsCell.new(sp.a, js_module_namespace(dep), true)
          else
            c = js_module_resolve_export(dep, sp.str, [])
            raise JsThrow.new(js_syntax_error("The requested module does not provide an export named '" + sp.str + "'")) if c == nil
            m.exports[sp.a] = c
      elsif s.kind == :export_all
        dep = js_module_get(js_module_resolve(s.str, m.url))
        m.deps.push(dep) if !m.deps.include?(dep)
        if s.a != nil
          m.exports[s.a] = JsCell.new(s.a, js_module_namespace(dep), true)
        else
          m.stars.push(dep)
    body = compile_list(prog.list, sc)
    hoist = fns.map(->(f) [f.str == nil ? "*default*" : f.str, compile_function(f, sc, f.str == nil ? "default" : f.str)])
    cells = sc.names.values.select(->(b) b.cell != nil && b.kind != :import && b.tdz).map(->(b) b.cell)
    mm = m
    run = ->() js_module_run(mm, sc, body, hoist, cells)
    m.run = run
    m

-> js_mod_cell(sc, name, kind, tdz)
  b = sc.names[name]
  return b if b != nil && b.cell != nil
  b = JsBinding.new(name, kind, sc, -1)
  b.cell = JsCell.new(name, tdz ? JS_TDZ : nil, kind == :const)
  b.tdz = tdz
  b.is_const = kind == :const
  sc.names[name] = b
  b

-> js_module_run(m, sc, body, hoist, cells)
  env = Array.new(sc.size, nil)
  env[FS_THIS] = nil
  hoist.each ->(h)
    b = sc.names[h[0]]
    b.cell.v = js_make_closure(h[1], env)
  js_tdz_fill(env, sc.lex)
  old = JS_CURRENT_MODULE[0]
  JS_CURRENT_MODULE[0] = m
  begin
    body.call(env)
  rescue e
    JS_CURRENT_MODULE[0] = old
    raise e
  JS_CURRENT_MODULE[0] = old
  nil
