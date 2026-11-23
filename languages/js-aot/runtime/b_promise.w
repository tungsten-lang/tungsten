# runtime/b_promise — Promise (ES2024 plus withResolvers / try) and the job queue glue.
# (Ported from blade/js/b_promise.w.)
#
# Reactions run as realm jobs (microtasks: realm.enqueue_job / run_jobs). Native callers
# (await, the host) attach Tungsten lambdas directly with js_promise_then_native, without
# allocating JS functions.

in JS

+ Promise < JS:Special
  rw :state, :value, :reactions, :handled

  -> new(@shape)
    @cls = "Promise"
    @ext = nil
    @internal = nil
    @s0 = nil
    @s1 = nil
    @s2 = nil
    @s3 = nil
    @state = :pending
    @value = nil
    @reactions = []
    @handled = false
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_OBJECT)

+ Capability
  rw :promise, :resolve, :reject
  -> new(@promise, @resolve, @reject)
    nil

# A reaction: handler is a JS function, a Tungsten lambda ->(v), or nil (pass through).
+ Reaction
  # keep: values the handler lambda captures (for a collector)
  rw :cap, :kind, :handler, :keep
  -> new(@cap, @kind, @handler)
    @keep = nil

# Rejected promises without a handler (the host reports them).
# TODO(js-aot): per thread once workers run JS.
JS_UNHANDLED = []

-> js_promise?(v)
  v.is_a?(JS:Promise)

-> js_promise_alloc(proto)
  JS:Promise.new(js_root_shape(proto, SP_INLINE, SP_IBASE))

# CreateResolvingFunctions
-> js_resolving_functions(p)
  r = js_realm()
  done = [false]
  res = r.native("", 1, ->(this, args, nt) js_resolve_once(p, done, js_arg(args, 0)))
  rej = r.native("", 1, ->(this, args, nt) js_reject_once(p, done, js_arg(args, 0)))
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
  if !js_object?(x)
    js_promise_fulfill(p, x)
    return nil
  r = js_realm()
  # fast path: a native promise with the intrinsic then
  if js_promise?(x) && x.proto == r.intrinsic("Promise.prototype") && !x.has_own?("then") && js_promise_then_pristine?()
    r.enqueue_job(->() js_promise_adopt(p, x), [p, x])
    return nil
  th = nil
  begin
    th = jget(x, "then")
  rescue e
    js_promise_reject(p, js_error_value(e))
    return nil
  if !js_callable?(th)
    js_promise_fulfill(p, x)
    return nil
  r.enqueue_job(->() js_thenable_job(p, x, th), [p, x, th])
  nil

-> js_promise_then_pristine?
  r = js_realm()
  r.intrinsic("Promise.prototype").get_own("then") == r.intrinsic("%PromiseProto_then%")

-> js_promise_adopt(p, x)
  fns = js_resolving_functions(p)
  a = JS:Reaction.new(nil, :fulfill, ->(v) js_call_arr(fns[0], nil, [v]))
  a.keep = fns
  b = JS:Reaction.new(nil, :reject, ->(v) js_call_arr(fns[1], nil, [v]))
  b.keep = fns
  js_perform_then(x, a, b)
  nil

-> js_thenable_job(p, x, th)
  fns = js_resolving_functions(p)
  begin
    js_call_arr(th, x, [fns[0], fns[1]])
  rescue e
    js_call_arr(fns[1], nil, [js_error_value(e)])
  nil

-> js_promise_fulfill(p, v)
  return nil if p.state != :pending
  rs = p.reactions
  p.state = :fulfilled
  p.value = v
  p.reactions = nil
  i = 0
  while i < rs.size
    js_trigger(rs[i][0], v)
    i += 1
  nil

-> js_promise_reject(p, v)
  return nil if p.state != :pending
  rs = p.reactions
  p.state = :rejected
  p.value = v
  p.reactions = nil
  JS_UNHANDLED.push(p) if !p.handled
  i = 0
  while i < rs.size
    js_trigger(rs[i][1], v)
    i += 1
  nil

-> js_trigger(rx, v)
  js_realm().enqueue_job(->() js_reaction_job(rx, v), [rx, v])
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
    begin
      if js_object?(h)
        result = js_call_arr(h, nil, [v])
      else
        # a host handler
        result = h.call(v)
    rescue e
      result = js_error_value(e)
      failed = true
  return nil if cap == nil
  if failed
    js_cap_reject(cap, result)
  else
    js_cap_resolve(cap, result)
  nil

-> js_cap_resolve(cap, v)
  if js_object?(cap.resolve)
    js_call_arr(cap.resolve, nil, [v])
  else
    cap.resolve.call(v)

-> js_cap_reject(cap, v)
  if js_object?(cap.reject)
    js_call_arr(cap.reject, nil, [v])
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
  p = js_promise_alloc(js_realm().intrinsic("Promise.prototype"))
  fns = js_resolving_functions(p)
  JS:Capability.new(p, fns[0], fns[1])

# NewPromiseCapability(C)
-> js_new_capability_from(c)
  r = js_realm()
  return js_new_capability() if c == r.intrinsic("Promise")
  js_throw_type(js_to_display_short(c) + " is not a constructor") if !js_is_constructor?(c)
  slots = [nil, nil]
  ex = r.native("", 2, ->(this, args, nt) js_capability_executor(slots, args))
  p = js_construct(c, [ex], nil)
  js_throw_type("Promise resolve or reject function is not callable") if !js_callable?(slots[0]) || !js_callable?(slots[1])
  JS:Capability.new(p, slots[0], slots[1])

-> js_capability_executor(slots, args)
  js_throw_type("Promise executor has already been invoked with non-undefined arguments") if slots[0] != nil || slots[1] != nil
  slots[0] = js_arg(args, 0)
  slots[1] = js_arg(args, 1)
  nil

-> js_promise_ctor(args, nt)
  js_throw_type("Promise constructor cannot be invoked without 'new'") if nt == nil
  ex = js_arg(args, 0)
  js_throw_type("Promise resolver " + js_err_display(ex) + " is not a function") if !js_callable?(ex)
  p = js_promise_alloc(js_realm().proto_from(nt, "Promise"))
  fns = js_resolving_functions(p)
  begin
    js_call_arr(ex, nil, [fns[0], fns[1]])
  rescue e
    js_call_arr(fns[1], nil, [js_error_value(e)])
  p

-> js_promise_then(p, on_f, on_r)
  js_throw_type("Method Promise.prototype.then called on incompatible receiver " + js_err_display(p)) if !js_promise?(p)
  c = js_species_ctor(p, js_realm().intrinsic("Promise"))
  cap = js_new_capability_from(c)
  f = js_callable?(on_f) ? on_f : nil
  rj = js_callable?(on_r) ? on_r : nil
  js_perform_then(p, JS:Reaction.new(cap, :fulfill, f), JS:Reaction.new(cap, :reject, rj))
  cap.promise

-> js_species_ctor(o, dflt)
  c = jget(o, "constructor")
  return dflt if c == nil
  js_throw_type("object.constructor is not an object") if !js_object?(c)
  s = jget(c, SYM_SPECIES)
  return dflt if js_nullish?(s)
  return s if js_is_constructor?(s)
  js_throw_type("object.constructor\[Symbol.species] is not a constructor")

# PromiseResolve(%Promise%, v)
-> js_promise_resolve_value(v)
  if js_promise?(v) && jget(v, "constructor") == js_realm().intrinsic("Promise")
    return v
  cap = js_new_capability()
  js_call_arr(cap.resolve, nil, [v])
  cap.promise

-> js_promise_resolve_ctor(c, v)
  js_throw_type("PromiseResolve called on non-object") if !js_object?(c)
  if js_promise?(v) && jget(v, "constructor") == c
    return v
  cap = js_new_capability_from(c)
  js_call_arr(cap.resolve, nil, [v])
  cap.promise

# Attach Tungsten lambdas to any value (resolved as a promise). Used by await and the host.
-> js_promise_then_native(v, on_ok, on_err, keep = nil)
  # PromiseResolve once (a thenable's `then` must be called only once)
  p = js_promise_resolve_value(v)
  a = JS:Reaction.new(nil, :fulfill, on_ok)
  a.keep = keep
  b = JS:Reaction.new(nil, :reject, on_err)
  b.keep = keep
  js_perform_then(p, a, b)
  nil

# p.then(f) where f is a Tungsten lambda; returns the derived promise.
-> js_promise_then_value(p, f, keep = nil)
  cap = js_new_capability()
  a = JS:Reaction.new(cap, :fulfill, f)
  a.keep = keep
  js_perform_then(p, a, JS:Reaction.new(cap, :reject, nil))
  cap.promise

-> js_promise_finally(p, on_fin)
  js_throw_type("Promise.prototype.finally called on non-object") if !js_object?(p)
  c = js_species_ctor(p, js_realm().intrinsic("Promise"))
  return js_invoke(p, "then", [on_fin, on_fin]) if !js_callable?(on_fin)
  r = js_realm()
  tf = r.native("", 1, ->(this, args, nt) js_finally_then(c, on_fin, js_arg(args, 0), false))
  cf = r.native("", 1, ->(this, args, nt) js_finally_then(c, on_fin, js_arg(args, 0), true))
  js_invoke(p, "then", [tf, cf])

-> js_finally_then(c, on_fin, v, thrown)
  res = js_call_arr(on_fin, nil, JS_NO_ARGS)
  pr = js_promise_resolve_ctor(c, res)
  r = js_realm()
  k = thrown ? r.native("", 0, ->(this, args, nt) js_throw_value(v)) : r.native("", 0, ->(this, args, nt) v)
  js_invoke(pr, "then", [k])

# ---- combinators ----

# Promise.all / allSettled / any / race (§27.2.4): the iterable is stepped one value at a
# time; when resolve or then throws, the iterator is closed and the promise rejected.
# (Collecting it first would never finish on an endless iterator.)
-> js_promise_combinator(c, iterable, mode)
  cap = js_new_capability_from(c)
  rec = nil
  begin
    resolve_fn = js_get_value(c, "resolve")
    js_throw_type("Promise resolve is not a function") if !js_callable?(resolve_fn)
    rec = js_get_iterator(iterable)
    r = js_realm()
    values = []
    remaining = [1]
    i = 0
    while true
      x = js_iter_step(rec)
      break if x == JS_ITER_DONE
      values.push(nil)
      remaining[0] += 1
      p = js_call_arr(resolve_fn, c, [x])
      js_combinator_attach(c, cap, p, i, values, remaining, mode)
      i += 1
    remaining[0] -= 1
    if remaining[0] == 0 && mode != :race
      if mode == :any
        js_call_arr(cap.reject, nil, [js_aggregate_error_ctor([r.adopt_array(values), "All promises were rejected"], nil)])
      else
        js_call_arr(cap.resolve, nil, [r.adopt_array(values)])
  rescue e
    # an error from the iterator itself leaves it alone; any other error closes it
    js_iter_close_quiet(rec) if rec != nil && !rec.done
    js_call_arr(cap.reject, nil, [js_error_value(e)])
  cap.promise

-> js_combinator_attach(c, cap, p, i, values, remaining, mode)
  r = js_realm()
  done = [false]
  if mode == :all
    ok = r.native("", 1, ->(this, args, nt) js_comb_settle(cap, values, remaining, i, done, js_arg(args, 0), :value))
    js_invoke(p, "then", [ok, cap.reject])
  elsif mode == :all_settled
    ok = r.native("", 1, ->(this, args, nt) js_comb_settle(cap, values, remaining, i, done, js_settled_obj("fulfilled", "value", js_arg(args, 0)), :value))
    bad = r.native("", 1, ->(this, args, nt) js_comb_settle(cap, values, remaining, i, done, js_settled_obj("rejected", "reason", js_arg(args, 0)), :value))
    js_invoke(p, "then", [ok, bad])
  elsif mode == :any
    bad = r.native("", 1, ->(this, args, nt) js_comb_settle(cap, values, remaining, i, done, js_arg(args, 0), :error))
    js_invoke(p, "then", [cap.resolve, bad])
  else
    js_invoke(p, "then", [cap.resolve, cap.reject])
  nil

-> js_settled_obj(status, key, v)
  o = js_realm().new_object
  o.put_own("status", status)
  o.put_own(key, v)
  o

-> js_comb_settle(cap, values, remaining, i, done, v, kind)
  return nil if done[0]
  done[0] = true
  values[i] = v
  remaining[0] -= 1
  if remaining[0] == 0
    r = js_realm()
    if kind == :error
      js_call_arr(cap.reject, nil, [js_aggregate_error_ctor([r.new_array(values), "All promises were rejected"], nil)])
    else
      js_call_arr(cap.resolve, nil, [r.new_array(values)])
  nil

-> js_promise_with_resolvers(c)
  cap = js_new_capability_from(c)
  o = js_realm().new_object
  o.put_own("promise", cap.promise)
  o.put_own("resolve", cap.resolve)
  o.put_own("reject", cap.reject)
  o

-> js_promise_try(c, args)
  cap = js_new_capability_from(c)
  begin
    v = js_call_arr(js_arg(args, 0), nil, args.size > 1 ? args.slice(1, args.size - 1).dup : [])
    js_call_arr(cap.resolve, nil, [v])
  rescue e
    js_call_arr(cap.reject, nil, [js_error_value(e)])
  cap.promise

js_install(->(r) js_install_promise(r))

-> js_install_promise(r)
  pp = js_new_object(r.object_proto)
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
  js_call_arr(cap.reject, nil, [v])
  cap.promise
