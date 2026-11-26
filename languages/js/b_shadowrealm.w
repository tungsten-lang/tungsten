# runtime/b_shadowrealm — ShadowRealm & WrappedFunction (Stage 3 / ES2026)
# and %AbstractModuleSource% intrinsic.

in JS

# Hook wired by module.w for ShadowRealm.prototype.importValue.
JS_SHADOW_IMPORT_HOOK = [nil]

# WrappedFunction exotic callable object (ShadowRealm boundary).
+ WrappedFunction < JS:Base
  rw :target, :realm

  -> new(@shape, @target, @realm)
    @ext = nil
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_EXOTIC)

  -> callable?
    true

  -> constructor?
    false

  -> call_obj(this, args)
    caller_r = @realm
    target = @target
    # Step 5: targetRealm = GetFunctionRealm(target) — errors map to callerRealm TypeError!
    target_r = nil
    begin
      target_r = js_get_function_realm(target)
    rescue ex
      prev0 = JS_REALM[0]
      JS_REALM[0] = caller_r
      err0 = js_make_error("TypeError", "Cannot call wrapped function: target realm inaccessible")
      JS_REALM[0] = prev0
      js_throw(err0)
    # Step 7-8: Wrap each argument for targetRealm (errors thrown in callerRealm!)
    wargs = []
    i = 0
    while i < args.size
      a = args[i]
      if js_object?(a)
        if !js_callable?(a)
          prev1 = JS_REALM[0]
          JS_REALM[0] = caller_r
          err1 = js_make_error("TypeError", "WrappedFunction arguments must be primitives or callable")
          JS_REALM[0] = prev1
          js_throw(err1)
        wargs.push(js_wrapped_function_create(target_r, a))
      else
        wargs.push(a)
      i += 1
    # Step 9-10: Call target with undefined receiver in targetRealm
    prev = JS_REALM[0]
    JS_REALM[0] = target_r
    res = nil
    threw = false
    begin
      res = js_call_arr(target, nil, wargs)
    rescue ex
      threw = true
    JS_REALM[0] = prev
    if threw
      prev2 = JS_REALM[0]
      JS_REALM[0] = caller_r
      err2 = js_make_error("TypeError", "WrappedFunction call threw an exception")
      JS_REALM[0] = prev2
      js_throw(err2)
    # Step 11: Wrap return value for callerRealm
    js_get_wrapped_value(caller_r, res)

-> js_wrapped_function_create(caller_r, target)
  prev = JS_REALM[0]
  JS_REALM[0] = caller_r
  wf = JS:WrappedFunction.new(js_root_shape(caller_r.function_proto, 0, 4), target, caller_r)
  # CopyNameAndLength(wf, target, "") — any abrupt completion throws a callerRealm TypeError!
  ok = true
  begin
    has_len = jget_own_property(target, "length") != nil
    len_v = ~0.0
    if has_len
      tl = jget(target, "length")
      if js_number?(tl)
        if tl == INF
          len_v = INF
        elsif tl == NEG_INF || tl != tl
          len_v = ~0.0
        else
          ti = js_to_integer(tl)
          len_v = ti < ~0.0 ? ~0.0 : ti
    wf.define("length", len_v, ATTR_C)
    tn = jget(target, "name")
    nm = js_string?(tn) ? tn : ""
    wf.define("name", nm, ATTR_C)
  rescue ex
    ok = false
  if !ok
    err = js_make_error("TypeError", "CopyNameAndLength failed for WrappedFunction")
    JS_REALM[0] = prev
    js_throw(err)
  JS_REALM[0] = prev
  wf

-> js_get_wrapped_value(caller_r, val)
  return val if !js_object?(val)
  if !js_callable?(val)
    prev = JS_REALM[0]
    JS_REALM[0] = caller_r
    err = js_make_error("TypeError", "ShadowRealm boundary does not allow non-callable objects")
    JS_REALM[0] = prev
    js_throw(err)
  js_wrapped_function_create(caller_r, val)

-> js_req_shadow_realm(v, who)
  js_throw_type(who + " called on incompatible receiver " + js_err_display(v)) if !(js_special?(v, "ShadowRealm") && v.internal.is_a?(JS:Realm))
  v.internal

-> js_shadow_realm_ctor(nt)
  js_throw_type("Constructor ShadowRealm requires 'new'") if nt == nil
  caller_r = js_realm()
  o = js_new_special(caller_r.proto_from(nt, "ShadowRealm"), "ShadowRealm")
  sr = js_create_sub_realm(caller_r)
  o.internal = sr
  o

-> js_shadow_realm_evaluate(this, source_text)
  sr = js_req_shadow_realm(this, "ShadowRealm.prototype.evaluate")
  js_throw_type("ShadowRealm.prototype.evaluate requires a string argument") if !js_string?(source_text)
  caller_r = js_realm()
  # Parse & static-check first: syntax / early errors become caller_r SyntaxError!
  p = JsParser.new(source_text, false)
  prog = nil
  begin
    prog = p.parse_program()
  rescue e
    p.release_simd_lex
    msg = p.error == nil ? e.to_s : p.error.msg
    js_throw(js_make_error("SyntaxError", msg))
  p.release_simd_lex
  an = JaAnalysis.new(prog, false)
  an.src = source_text
  an.url = "ShadowRealm.evaluate"
  an.eval_mode = true
  an.run
  an.funcs.each ->(g)
    js_throw(js_make_error("SyntaxError", g.unsupported0.to_s)) if g.unsupported0 != nil
  # Execute in sr (fresh lexical env per evaluate call, like indirect eval!); runtime error -> caller_r TypeError!
  prev = js_enter_realm(sr)
  res = nil
  threw = false
  begin
    f = an.funcs[0]
    act = wk_act(f, nil, nil, sr.global, f.nlocals)
    act.caller = nil
    JS_CUR_ACT[0] = act
    wk_hoist_script(f, act)
    wk_scope_enter(f.scope, act)
    wk_hoist_functions(prog.list, act)
    wk_stmts(prog.list, act)
    res = act.rv
    JS_CUR_ACT[0] = nil
  rescue ex
    JS_CUR_ACT[0] = nil
    threw = true
  js_leave_realm(prev)
  js_throw_type("ShadowRealm.prototype.evaluate threw an exception") if threw
  js_get_wrapped_value(caller_r, res)

-> js_shadow_realm_import_value(this, spec_v, export_name_v)
  sr = js_req_shadow_realm(this, "ShadowRealm.prototype.importValue")
  spec_str = js_to_string(spec_v)
  js_throw_type("ShadowRealm.prototype.importValue exportName must be a string") if !js_string?(export_name_v)
  caller_r = js_realm()
  if JS_SHADOW_IMPORT_HOOK[0] != nil
    return JS_SHADOW_IMPORT_HOOK[0].call(sr, caller_r, spec_str, export_name_v)
  cap = js_new_capability()
  js_call_arr(cap.reject, nil, [js_make_error("TypeError", "Module loader unavailable")])
  cap.promise

# %AbstractModuleSource% (ECMA-262 source-phase-imports)
-> js_abstract_module_source_tag(this)
  return nil if !js_object?(this)
  return this.internal if js_special?(this, "ModuleSource") && js_string?(this.internal)
  nil

js_install(->(r) js_install_shadow_realm(r))

-> js_install_shadow_realm(r)
  op = r.object_proto
  sp = js_new_object(op)
  r.constructor("ShadowRealm", 0, ->(this, args, nt) js_shadow_realm_ctor(nt), sp)
  r.method(sp, "evaluate", 1, ->(this, args, nt) js_shadow_realm_evaluate(this, js_arg(args, 0)))
  r.method(sp, "importValue", 2, ->(this, args, nt) js_shadow_realm_import_value(this, js_arg(args, 0), js_arg(args, 1)))
  sp.define(SYM_TO_STRING_TAG, "ShadowRealm", ATTR_C)
  # %AbstractModuleSource% intrinsic (not exposed as a global, accessed via $262.AbstractModuleSource / subclassing)
  amsp = js_new_object(op)
  amsc = r.native("AbstractModuleSource", 0, ->(this, args, nt) js_throw_type("AbstractModuleSource cannot be constructed directly"), true)
  amsc.define("prototype", amsp, 0)
  amsp.define("constructor", amsc, BUILTIN_ATTRS)
  r.getter(amsp, SYM_TO_STRING_TAG, ->(this, args, nt) js_abstract_module_source_tag(this))
  r.set_intrinsic("%AbstractModuleSource%", amsc)
  r.set_intrinsic("%AbstractModuleSource.prototype%", amsp)
  nil
