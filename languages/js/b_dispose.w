# runtime/b_dispose — Explicit Resource Management (ES2026):
# DisposeCapability, DisposableStack, AsyncDisposableStack, and disposal helpers.

in JS

+ DisposableResource
  rw :value, :hint, :method
  -> new(@value, @hint, @method)
    nil

+ DisposeCap
  rw :stack
  -> new
    @stack = []

+ DispStackState
  rw :state, :cap
  -> new
    @state = :pending
    @cap = JS:DisposeCap.new

# GetDisposeMethod ( V, hint )
-> js_get_dispose_method(v, hint)
  if hint == :async
    m = js_get_method(v, SYM_ASYNC_DISPOSE)
    if m == nil
      sm = js_get_method(v, SYM_DISPOSE)
      return nil if sm == nil
      # Wrap sync method so its return value is ignored (even if it returns a Promise!)
      # and exceptions propagate into an async rejection / SuppressedError.
      fn = ->(this, args, nt)
        js_call_arr(sm, this, JS_NO_ARGS)
        nil
      return js_native("", 0, fn)
    return m
  js_get_method(v, SYM_DISPOSE)

# CreateDisposableResource ( V, hint [, method] )
-> js_create_disposable_resource(v, hint, has_method = false, method = nil)
  if !has_method
    if v == nil || v == JS_NULL
      return JS:DisposableResource.new(nil, hint, nil)
    js_throw_type("Disposable resource must be an object") if !js_object?(v)
    method = js_get_dispose_method(v, hint)
    js_throw_type("Object is not disposable") if method == nil
  else
    js_throw_type("Dispose callback is not callable") if !js_callable?(method)
  JS:DisposableResource.new(v, hint, method)

# AddDisposableResource ( disposeCapability, V, hint [, method] )
-> js_add_disposable_resource(cap, v, hint, has_method = false, method = nil)
  res = nil
  if !has_method
    return nil if (v == nil || v == JS_NULL) && hint == :sync
    res = js_create_disposable_resource(v, hint, false, nil)
  else
    res = js_create_disposable_resource(v, hint, true, method)
  cap.stack.push(res)
  nil

# DisposeResources ( disposeCapability, completion ) — synchronous path.
-> js_dispose_resources_sync(cap, has_err, err_val)
  st = cap.stack
  cap.stack = []
  i = st.size - 1
  while i >= 0
    res = st[i]
    if res.method != nil
      begin
        js_call_arr(res.method, res.value, JS_NO_ARGS)
      rescue ex
        ev = js_error_value(ex)
        if has_err
          err_val = js_suppressed_error_new(ev, err_val)
        else
          has_err = true
          err_val = ev
    i -= 1
  js_throw(err_val) if has_err
  nil

# DisposeResources ( disposeCapability, NormalCompletion(undefined) ) — asynchronous Promise path
# (used by AsyncDisposableStack.prototype.disposeAsync).
-> js_dispose_resources_async_step(items, idx, has_err, err_val, cap)
  while idx >= 0
    res = items[idx]
    idx -= 1
    call_res = nil
    threw = false
    threw_val = nil
    if res.method != nil
      begin
        call_res = js_call_arr(res.method, res.value, JS_NO_ARGS)
      rescue ex
        threw = true
        threw_val = js_error_value(ex)
    if threw
      if has_err
        err_val = js_suppressed_error_new(threw_val, err_val)
      else
        has_err = true
        err_val = threw_val
      next
    if res.hint == :async
      # Await call_res (even if method == nil -> await undefined!).
      # Capture state cleanly for the reaction callbacks.
      next_idx = idx
      he = has_err
      ev = err_val
      rw = nil
      begin
        rw = js_promise_resolve_value(call_res)
      rescue ex2
        ev2 = js_error_value(ex2)
        if has_err
          err_val = js_suppressed_error_new(ev2, err_val)
        else
          has_err = true
          err_val = ev2
        next
      on_f = ->(v)
        js_dispose_resources_async_step(items, next_idx, he, ev, cap)
        nil
      on_r = ->(rerr)
        nev = he ? js_suppressed_error_new(rerr, ev) : rerr
        js_dispose_resources_async_step(items, next_idx, true, nev, cap)
        nil
      js_perform_then(rw, JS:Reaction.new(nil, :fulfill, on_f), JS:Reaction.new(nil, :reject, on_r))
      return nil
  if has_err
    js_call_arr(cap.reject, nil, [err_val])
  else
    js_call_arr(cap.resolve, nil, [nil])
  nil

# ---- DisposableStack ----

-> js_req_disp_stack(v, who)
  js_throw_type(who + " called on incompatible receiver " + js_err_display(v)) if !(js_special?(v, "DisposableStack") && v.internal.is_a?(JS:DispStackState))
  v.internal

-> js_disp_stack_ctor(nt)
  js_throw_type("Constructor DisposableStack requires 'new'") if nt == nil
  o = js_new_special(js_realm().proto_from(nt, "DisposableStack"), "DisposableStack")
  o.internal = JS:DispStackState.new
  o

-> js_disp_stack_use(this, val)
  st = js_req_disp_stack(this, "DisposableStack.prototype.use")
  js_throw_reference("Cannot add values to a disposed DisposableStack") if st.state == :disposed
  js_add_disposable_resource(st.cap, val, :sync, false, nil)
  val

-> js_disp_stack_adopt(this, val, on_disp)
  st = js_req_disp_stack(this, "DisposableStack.prototype.adopt")
  js_throw_reference("Cannot add values to a disposed DisposableStack") if st.state == :disposed
  js_throw_type("DisposableStack.prototype.adopt callback is not a function") if !js_callable?(on_disp)
  fn = ->(t2, a2, nt2)
    js_call_arr(on_disp, nil, [val])
    nil
  js_add_disposable_resource(st.cap, nil, :sync, true, js_native("", 0, fn))
  val

-> js_disp_stack_defer(this, on_disp)
  st = js_req_disp_stack(this, "DisposableStack.prototype.defer")
  js_throw_reference("Cannot add values to a disposed DisposableStack") if st.state == :disposed
  js_throw_type("DisposableStack.prototype.defer callback is not a function") if !js_callable?(on_disp)
  js_add_disposable_resource(st.cap, nil, :sync, true, on_disp)
  nil

-> js_disp_stack_move(this)
  st = js_req_disp_stack(this, "DisposableStack.prototype.move")
  js_throw_reference("Cannot move elements from a disposed DisposableStack") if st.state == :disposed
  r = js_realm()
  nw = js_new_special(r.proto_from(r.intrinsic("DisposableStack"), "DisposableStack"), "DisposableStack")
  nst = JS:DispStackState.new
  nst.cap = st.cap
  nw.internal = nst
  st.cap = JS:DisposeCap.new
  st.state = :disposed
  nw

-> js_disp_stack_dispose(this)
  st = js_req_disp_stack(this, "DisposableStack.prototype.dispose")
  return nil if st.state == :disposed
  st.state = :disposed
  js_dispose_resources_sync(st.cap, false, nil)
  nil

# ---- AsyncDisposableStack ----

-> js_req_async_disp_stack(v, who)
  js_throw_type(who + " called on incompatible receiver " + js_err_display(v)) if !(js_special?(v, "AsyncDisposableStack") && v.internal.is_a?(JS:DispStackState))
  v.internal

-> js_async_disp_stack_ctor(nt)
  js_throw_type("Constructor AsyncDisposableStack requires 'new'") if nt == nil
  o = js_new_special(js_realm().proto_from(nt, "AsyncDisposableStack"), "AsyncDisposableStack")
  o.internal = JS:DispStackState.new
  o

-> js_async_disp_stack_use(this, val)
  st = js_req_async_disp_stack(this, "AsyncDisposableStack.prototype.use")
  js_throw_reference("Cannot add values to a disposed AsyncDisposableStack") if st.state == :disposed
  js_add_disposable_resource(st.cap, val, :async, false, nil)
  val

-> js_async_disp_stack_adopt(this, val, on_disp)
  st = js_req_async_disp_stack(this, "AsyncDisposableStack.prototype.adopt")
  js_throw_reference("Cannot add values to a disposed AsyncDisposableStack") if st.state == :disposed
  js_throw_type("AsyncDisposableStack.prototype.adopt callback is not a function") if !js_callable?(on_disp)
  fn = ->(t2, a2, nt2)
    js_call_arr(on_disp, nil, [val])
  js_add_disposable_resource(st.cap, nil, :async, true, js_native("", 0, fn))
  val

-> js_async_disp_stack_defer(this, on_disp)
  st = js_req_async_disp_stack(this, "AsyncDisposableStack.prototype.defer")
  js_throw_reference("Cannot add values to a disposed AsyncDisposableStack") if st.state == :disposed
  js_throw_type("AsyncDisposableStack.prototype.defer callback is not a function") if !js_callable?(on_disp)
  js_add_disposable_resource(st.cap, nil, :async, true, on_disp)
  nil

-> js_async_disp_stack_move(this)
  st = js_req_async_disp_stack(this, "AsyncDisposableStack.prototype.move")
  js_throw_reference("Cannot move elements from a disposed AsyncDisposableStack") if st.state == :disposed
  r = js_realm()
  nw = js_new_special(r.proto_from(r.intrinsic("AsyncDisposableStack"), "AsyncDisposableStack"), "AsyncDisposableStack")
  nst = JS:DispStackState.new
  nst.cap = st.cap
  nw.internal = nst
  st.cap = JS:DisposeCap.new
  st.state = :disposed
  nw

-> js_async_disp_stack_dispose(this)
  cap = js_new_capability()
  if !(js_special?(this, "AsyncDisposableStack") && this.internal.is_a?(JS:DispStackState))
    js_call_arr(cap.reject, nil, [js_make_error("TypeError", "AsyncDisposableStack.prototype.disposeAsync called on incompatible receiver " + js_err_display(this))])
    return cap.promise
  st = this.internal
  if st.state == :disposed
    js_call_arr(cap.resolve, nil, [nil])
    return cap.promise
  st.state = :disposed
  items = st.cap.stack
  st.cap = JS:DisposeCap.new
  if items.size == 0
    js_call_arr(cap.resolve, nil, [nil])
    return cap.promise
  js_dispose_resources_async_step(items, items.size - 1, false, nil, cap)
  cap.promise

js_install(->(r) js_install_dispose(r))

-> js_install_dispose(r)
  op = r.object_proto
  # DisposableStack
  dp = js_new_object(op)
  r.constructor("DisposableStack", 0, ->(this, args, nt) js_disp_stack_ctor(nt), dp)
  r.getter(dp, "disposed", ->(this, args, nt) js_req_disp_stack(this, "get DisposableStack.prototype.disposed").state == :disposed)
  r.method(dp, "use", 1, ->(this, args, nt) js_disp_stack_use(this, js_arg(args, 0)))
  r.method(dp, "adopt", 2, ->(this, args, nt) js_disp_stack_adopt(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(dp, "defer", 1, ->(this, args, nt) js_disp_stack_defer(this, js_arg(args, 0)))
  r.method(dp, "move", 0, ->(this, args, nt) js_disp_stack_move(this))
  disp_fn = r.method(dp, "dispose", 0, ->(this, args, nt) js_disp_stack_dispose(this))
  dp.define(SYM_DISPOSE, disp_fn, BUILTIN_ATTRS)
  dp.define(SYM_TO_STRING_TAG, "DisposableStack", ATTR_C)
  # AsyncDisposableStack
  adp = js_new_object(op)
  r.constructor("AsyncDisposableStack", 0, ->(this, args, nt) js_async_disp_stack_ctor(nt), adp)
  r.getter(adp, "disposed", ->(this, args, nt) js_req_async_disp_stack(this, "get AsyncDisposableStack.prototype.disposed").state == :disposed)
  r.method(adp, "use", 1, ->(this, args, nt) js_async_disp_stack_use(this, js_arg(args, 0)))
  r.method(adp, "adopt", 2, ->(this, args, nt) js_async_disp_stack_adopt(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(adp, "defer", 1, ->(this, args, nt) js_async_disp_stack_defer(this, js_arg(args, 0)))
  r.method(adp, "move", 0, ->(this, args, nt) js_async_disp_stack_move(this))
  adisp_fn = r.method(adp, "disposeAsync", 0, ->(this, args, nt) js_async_disp_stack_dispose(this))
  adp.define(SYM_ASYNC_DISPOSE, adisp_fn, BUILTIN_ATTRS)
  adp.define(SYM_TO_STRING_TAG, "AsyncDisposableStack", ATTR_C)
  nil
