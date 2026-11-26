# blade/js/b_promise — Promise (ES2024 plus withResolvers / try) and the job queue glue.
#
# Reactions run as realm jobs (microtasks). Native callers (await, the host) attach
# Tungsten lambdas directly with js_promise_then_native, without allocating JS functions.

+ JsPromise < JsObject
  rw :state, :value, :reactions, :handled

+ JsCapability
  rw :promise, :resolve, :reject
  -> new(@promise, @resolve, @reject)

# A reaction: handler is a JsFunction, a Tungsten lambda ->(v), or nil (pass through).
+ JsReaction
  # keep: values the handler lambda captures (traced by js/gc.w)
  rw :cap, :kind, :handler, :keep
  -> new(@cap, @kind, @handler)
    @keep = nil

JS_UNHANDLED = JsTlsList.new

-> js_promise_alloc(proto)
  p = JsPromise.new(proto, "Promise")
  p.state = :pending
  p.value = nil
  p.reactions = []
  p.handled = false
  js_gc_eng(p)

# CreateResolvingFunctions
-> js_resolving_functions(p)
  r = JS_REALM[0]
  done = [false]
  res = js_keep(r.native("", 1, ->(this, args, nt) js_resolve_once(p, done, js_arg(args, 0))), [p, done])
  rej = js_keep(r.native("", 1, ->(this, args, nt) js_reject_once(p, done, js_arg(args, 0))), [p, done])
  [res, rej]

-> js_resolve_once(p, done, x)
  return nil if done[0]
  done[0] = true
  js_promise_resolve_with(p, x)
  nil

-> js_reject_once(p, done, x)
  return nil if done[0]
  done[0] = true
  js_promise_reject(p, x)
  nil

-> js_promise_resolve_with(p, x)
  if x == p
    js_promise_reject(p, js_type_error("Chaining cycle detected for promise"))
    return nil
  if !x.is_a?(JsObject)
    js_promise_fulfill(p, x)
    return nil
  # fast path: a native promise with the intrinsic then
  if x.is_a?(JsPromise) && x.proto == JS_REALM[0].intrinsic("Promise.prototype") && !x.has_own?("then") && js_promise_then_pristine?()
    r = JS_REALM[0]
    r.enqueue_job(->() js_gc_ctx(true, ->() js_promise_adopt(p, x)), [p, x])
    return nil
  th = nil
  dd = JS_DEPTH[0]
  begin
    th = x.get("then", x)
  rescue e
    JS_DEPTH[0] = dd
    js_promise_reject(p, js_error_value(e))
    return nil
  if !(th.is_a?(JsObject) && th.callable?)
    js_promise_fulfill(p, x)
    return nil
  JS_REALM[0].enqueue_job(->() js_gc_ctx(true, ->() js_thenable_job(p, x, th)), [p, x, th])
  nil

-> js_promise_then_pristine?
  r = JS_REALM[0]
  r.intrinsic("Promise.prototype").props["then"] == r.intrinsic("%PromiseProto_then%")

-> js_promise_adopt(p, x)
  fns = js_resolving_functions(p)
  a = js_gc_eng(JsReaction.new(nil, :fulfill, ->(v) js_call(fns[0], nil, [v])))
  a.keep = fns
  b = js_gc_eng(JsReaction.new(nil, :reject, ->(v) js_call(fns[1], nil, [v])))
  b.keep = fns
  js_perform_then(x, a, b)
  nil

-> js_thenable_job(p, x, th)
  fns = js_resolving_functions(p)
  dd = JS_DEPTH[0]
  begin
    js_call(th, x, [fns[0], fns[1]])
  rescue e
    JS_DEPTH[0] = dd
    js_call(fns[1], nil, [js_error_value(e)])
  nil

-> js_promise_fulfill(p, v)
  return nil if p.state != :pending
  rs = p.reactions
  p.state = :fulfilled
  p.value = v
  p.reactions = nil
  rs.each ->(rx) js_trigger(rx[0], v)
  nil

-> js_promise_reject(p, v)
  return nil if p.state != :pending
  rs = p.reactions
  p.state = :rejected
  p.value = v
  p.reactions = nil
  JS_UNHANDLED.push(p) if !p.handled
  rs.each ->(rx) js_trigger(rx[1], v)
  nil

-> js_trigger(rx, v)
  JS_REALM[0].enqueue_job(->() js_gc_ctx(true, ->() js_reaction_job(rx, v)), [rx, v])
  nil

-> js_reaction_job(rx, v)
  h = rx.handler
  cap = rx.cap
  result = nil
  failed = false
  if h == nil
    result = v
    failed = rx.kind == :reject
  else
    dd = JS_DEPTH[0]
    begin
      if h.is_a?(JsObject)
        result = js_call(h, nil, [v])
      else
        # a host handler (runs outside engine allocation context)
        result = js_gc_ctx(false, ->() h.call(v))
    rescue e
      JS_DEPTH[0] = dd
      result = js_error_value(e)
      failed = true
  return nil if cap == nil
  if failed
    js_cap_reject(cap, result)
  else
    js_cap_resolve(cap, result)
  nil

-> js_cap_resolve(cap, v)
  if cap.resolve.is_a?(JsObject)
    js_call(cap.resolve, nil, [v])
  else
    cap.resolve.call(v)

-> js_cap_reject(cap, v)
  if cap.reject.is_a?(JsObject)
    js_call(cap.reject, nil, [v])
  else
    cap.reject.call(v)

# PerformPromiseThen with two reactions.
-> js_perform_then(p, fr, rr)
  if p.state == :pending
    p.reactions.push([fr, rr])
  elsif p.state == :fulfilled
    js_trigger(fr, p.value)
  else
    if !p.handled
      i = JS_UNHANDLED.index(p)
      JS_UNHANDLED.delete_at(i) if i != nil
    js_trigger(rr, p.value)
  p.handled = true
  nil

# A capability for the intrinsic Promise (resolve/reject are JS functions).
-> js_new_capability
  r = JS_REALM[0]
  p = js_promise_alloc(r.intrinsic("Promise.prototype"))
  fns = js_resolving_functions(p)
  js_gc_eng(JsCapability.new(p, fns[0], fns[1]))

# NewPromiseCapability(C)
-> js_new_capability_from(c)
  r = JS_REALM[0]
  return js_new_capability() if c == r.intrinsic("Promise") || c == nil
  js_throw_type("Promise resolve or reject function is not callable") if !(c.is_a?(JsObject) && js_is_constructor?(c))
  slots = [nil, nil]
  ex = js_keep(r.native("", 2, ->(this, args, nt) js_capability_executor(slots, args)), [slots])
  p = js_construct(c, [ex], nil)
  js_throw_type("Promise resolve or reject function is not callable") if !(slots[0].is_a?(JsObject) && slots[0].callable?) || !(slots[1].is_a?(JsObject) && slots[1].callable?)
  JsCapability.new(p, slots[0], slots[1])

-> js_capability_executor(slots, args)
  js_throw_type("Promise executor has already been invoked with non-undefined arguments") if slots[0] != nil || slots[1] != nil
  slots[0] = js_arg(args, 0)
  slots[1] = js_arg(args, 1)
  nil

-> js_promise_ctor(args, nt)
  js_throw_type("Promise constructor cannot be invoked without 'new'") if nt == nil
  ex = js_arg(args, 0)
  js_throw_type("Promise resolver " + js_to_display(ex) + " is not a function") if !(ex.is_a?(JsObject) && ex.callable?)
  p = js_promise_alloc(JS_REALM[0].proto_from(nt, "Promise"))
  fns = js_resolving_functions(p)
  dd = JS_DEPTH[0]
  begin
    js_call(ex, nil, [fns[0], fns[1]])
  rescue e
    JS_DEPTH[0] = dd
    js_call(fns[1], nil, [js_error_value(e)])
  p

-> js_promise_then(p, on_f, on_r)
  js_throw_type("Method Promise.prototype.then called on incompatible receiver " + js_to_display(p)) if !p.is_a?(JsPromise)
  c = js_species_ctor(p, JS_REALM[0].intrinsic("Promise"))
  cap = js_new_capability_from(c)
  f = (on_f.is_a?(JsObject) && on_f.callable?) ? on_f : nil
  rj = (on_r.is_a?(JsObject) && on_r.callable?) ? on_r : nil
  js_perform_then(p, js_gc_eng(JsReaction.new(cap, :fulfill, f)), js_gc_eng(JsReaction.new(cap, :reject, rj)))
  cap.promise

-> js_species_ctor(o, dflt)
  c = o.get("constructor", o)
  return dflt if c == nil
  js_throw_type("object.constructor is not an object") if !c.is_a?(JsObject)
  s = c.get(SYM_SPECIES, c)
  return dflt if js_nullish?(s)
  return s if js_is_constructor?(s)
  js_throw_type("object.constructor\[Symbol.species] is not a constructor")

# PromiseResolve(%Promise%, v)
-> js_promise_resolve_value(v)
  r = JS_REALM[0]
  if v.is_a?(JsPromise) && v.get("constructor", v) == r.intrinsic("Promise")
    return v
  cap = js_new_capability()
  js_call(cap.resolve, nil, [v])
  cap.promise

-> js_promise_resolve_ctor(c, v)
  js_throw_type("PromiseResolve called on non-object") if !c.is_a?(JsObject)
  if v.is_a?(JsPromise) && v.get("constructor", v) == c
    return v
  cap = js_new_capability_from(c)
  js_call(cap.resolve, nil, [v])
  cap.promise

# Attach Tungsten lambdas to any value (resolved as a promise). Used by await and the host.
-> js_promise_then_native(v, on_ok, on_err, keep = nil)
  # PromiseResolve once (a thenable's `then` must be called only once)
  p = js_promise_resolve_value(v)
  a = JsReaction.new(nil, :fulfill, on_ok)
  a.keep = keep
  b = JsReaction.new(nil, :reject, on_err)
  b.keep = keep
  js_perform_then(p, a, b)
  nil

# p.then(f) where f is a Tungsten lambda; returns the derived promise.
-> js_promise_then_value(p, f, keep = nil)
  cap = js_new_capability()
  a = JsReaction.new(cap, :fulfill, f)
  a.keep = keep
  js_perform_then(p, a, JsReaction.new(cap, :reject, nil))
  cap.promise

-> js_promise_finally(p, on_fin)
  js_throw_type("Promise.prototype.finally called on non-object") if !p.is_a?(JsObject)
  c = js_species_ctor(p, JS_REALM[0].intrinsic("Promise"))
  return js_invoke(p, "then", [on_fin, on_fin]) if !(on_fin.is_a?(JsObject) && on_fin.callable?)
  r = JS_REALM[0]
  tf = js_keep(r.native("", 1, ->(this, args, nt) js_finally_then(c, on_fin, js_arg(args, 0), false)), [c, on_fin])
  cf = js_keep(r.native("", 1, ->(this, args, nt) js_finally_then(c, on_fin, js_arg(args, 0), true)), [c, on_fin])
  js_invoke(p, "then", [tf, cf])

-> js_finally_then(c, on_fin, v, thrown)
  res = js_call(on_fin, nil, JS_NO_ARGS)
  pr = js_promise_resolve_ctor(c, res)
  r = JS_REALM[0]
  k = js_keep(thrown ? r.native("", 0, ->(this, args, nt) js_throw_value(v)) : r.native("", 0, ->(this, args, nt) v), [v])
  js_invoke(pr, "then", [k])

-> js_invoke(o, k, args)
  js_call_named(js_getv(o, k), o, args, js_key_display(k).to_s)

# ---- combinators ----

# Promise.all / allSettled / any / race (§27.2.4): the iterable is stepped one value at a
# time; when resolve or then throws, the iterator is closed and the promise rejected.
# (Collecting it first would never finish on an endless iterator.)
-> js_promise_combinator(c, iterable, mode)
  cap = js_new_capability_from(c)
  dd = JS_DEPTH[0]
  rec = nil
  stepping = false
  begin
    resolve_fn = js_getv(c, "resolve")
    js_throw_type("Promise resolve is not a function") if !(resolve_fn.is_a?(JsObject) && resolve_fn.callable?)
    rec = js_get_iterator(iterable)
    r = JS_REALM[0]
    values = []
    remaining = [1]
    i = 0
    while true
      stepping = true
      x = js_iter_step(rec)
      stepping = false
      break if x == JS_ITER_DONE
      values.push(nil)
      remaining[0] += 1
      p = js_call(resolve_fn, c, [x])
      js_combinator_attach(c, cap, p, i, values, remaining, mode)
      i += 1
    remaining[0] -= 1
    if remaining[0] == 0 && mode != :race
      if mode == :any
        js_call(cap.reject, nil, [js_aggregate_error_ctor([r.new_array(values), "All promises were rejected"], nil)])
      else
        js_call(cap.resolve, nil, [r.new_array(values)])
  rescue e
    JS_DEPTH[0] = dd
    # an error from the iterator itself leaves it alone; any other error closes it
    js_iter_close_quiet(rec) if rec != nil && !stepping && !rec.done
    js_call(cap.reject, nil, [js_error_value(e)])
  cap.promise

-> js_combinator_attach(c, cap, p, i, values, remaining, mode)
  r = JS_REALM[0]
  done = [false]
  if mode == :all
    ok = js_keep(r.native("", 1, ->(this, args, nt) js_comb_settle(cap, values, remaining, i, done, js_arg(args, 0), :value)), [cap, values, remaining, done])
    js_invoke(p, "then", [ok, cap.reject])
  elsif mode == :all_settled
    ok = js_keep(r.native("", 1, ->(this, args, nt) js_comb_settle(cap, values, remaining, i, done, js_settled_obj("fulfilled", "value", js_arg(args, 0)), :value)), [cap, values, remaining, done])
    bad = js_keep(r.native("", 1, ->(this, args, nt) js_comb_settle(cap, values, remaining, i, done, js_settled_obj("rejected", "reason", js_arg(args, 0)), :value)), [cap, values, remaining, done])
    js_invoke(p, "then", [ok, bad])
  elsif mode == :any
    bad = js_keep(r.native("", 1, ->(this, args, nt) js_comb_settle(cap, values, remaining, i, done, js_arg(args, 0), :error)), [cap, values, remaining, done])
    js_invoke(p, "then", [cap.resolve, bad])
  else
    js_invoke(p, "then", [cap.resolve, cap.reject])
  nil

-> js_settled_obj(status, key, v)
  o = JS_REALM[0].new_object
  o.put_own("status", status)
  o.put_own(key, v)
  o

-> js_comb_settle(cap, values, remaining, i, done, v, kind)
  return nil if done[0]
  done[0] = true
  values[i] = v
  remaining[0] -= 1
  if remaining[0] == 0
    r = JS_REALM[0]
    if kind == :error
      js_call(cap.reject, nil, [js_aggregate_error_ctor([r.new_array(values), "All promises were rejected"], nil)])
    else
      js_call(cap.resolve, nil, [r.new_array(values)])
  nil

-> js_promise_with_resolvers(c)
  cap = js_new_capability_from(c)
  o = JS_REALM[0].new_object
  o.put_own("promise", cap.promise)
  o.put_own("resolve", cap.resolve)
  o.put_own("reject", cap.reject)
  o

-> js_promise_try(c, args)
  cap = js_new_capability_from(c)
  dd = JS_DEPTH[0]
  begin
    v = js_call(js_arg(args, 0), nil, args.size > 1 ? args.slice(1, args.size - 1).dup : [])
    js_call(cap.resolve, nil, [v])
  rescue e
    JS_DEPTH[0] = dd
    js_call(cap.reject, nil, [js_error_value(e)])
  cap.promise

js_install(->(r) js_install_promise(r))

-> js_install_promise(r)
  pp = JsObject.new(r.object_proto, "Object")
  pc = r.constructor("Promise", 1, ->(this, args, nt) js_promise_ctor(args, nt), pp)
  th = r.method(pp, "then", 2, ->(this, args, nt) js_promise_then(this, js_arg(args, 0), js_arg(args, 1)))
  r.set_intrinsic("%PromiseProto_then%", th)
  r.method(pp, "catch", 1, ->(this, args, nt) js_invoke(this, "then", [nil, js_arg(args, 0)]))
  r.method(pp, "finally", 1, ->(this, args, nt) js_promise_finally(this, js_arg(args, 0)))
  pp.define(SYM_TO_STRING_TAG, "Promise", ATTR_C)
  r.method(pc, "resolve", 1, ->(this, args, nt) js_promise_resolve_ctor(this, js_arg(args, 0)))
  r.method(pc, "reject", 1, ->(this, args, nt) js_promise_reject_static(this, js_arg(args, 0)))
  r.method(pc, "all", 1, ->(this, args, nt) js_promise_combinator(this, js_arg(args, 0), :all))
  r.method(pc, "allSettled", 1, ->(this, args, nt) js_promise_combinator(this, js_arg(args, 0), :all_settled))
  r.method(pc, "any", 1, ->(this, args, nt) js_promise_combinator(this, js_arg(args, 0), :any))
  r.method(pc, "race", 1, ->(this, args, nt) js_promise_combinator(this, js_arg(args, 0), :race))
  r.method(pc, "withResolvers", 0, ->(this, args, nt) js_promise_with_resolvers(this))
  r.method(pc, "try", 1, ->(this, args, nt) js_promise_try(this, args))
  r.getter(pc, SYM_SPECIES, ->(this, args, nt) this)
  nil

-> js_promise_reject_static(c, v)
  cap = js_new_capability_from(c)
  js_call(cap.reject, nil, [v])
  cap.promise
