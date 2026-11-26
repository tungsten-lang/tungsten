# runtime/b_iter — %IteratorPrototype% and the Iterator helpers, array and string
# iterators, generator and async-generator prototypes, the function-kind constructors.
# (Ported from blade/js/b_iter.w.)
#
# Iterator objects are JS:Specials whose internal holds the iteration state.

in JS

+ ArrayIterState
  rw :target, :index, :kind
  -> new(@target, @kind)
    @index = 0

-> js_array_iter(o, kind)
  it = js_new_special(js_realm().intrinsic("%ArrayIteratorPrototype%"), "Array Iterator")
  it.internal = JS:ArrayIterState.new(o, kind)
  it

# The length an array iterator sees: an array's size, a typed array's length, else
# ToLength(o.length).
-> js_iter_len_of(o)
  return o.size if js_array?(o)
  return js_typed_iter_length(o) if o.is_a?(JS:TypedArray)
  js_to_length(jget(o, "length"))

-> js_array_iter_next(this)
  js_throw_type("next method called on incompatible receiver " + js_err_display(this)) if !(js_special?(this, "Array Iterator") && this.internal.is_a?(JS:ArrayIterState))
  st = this.internal
  o = st.target
  return js_iter_result(nil, true) if o == nil
  i = st.index
  n = js_iter_len_of(o)
  if i >= n
    st.target = nil
    return js_iter_result(nil, true)
  st.index = i + 1
  k = st.kind
  return js_iter_result(i + ~0.0, false) if k == :keys
  v = js_array?(o) ? js_arr_elem(o, i) : jget(o, i.to_s)
  return js_iter_result(v, false) if k == :values
  js_iter_result(js_realm().adopt_array([i + ~0.0, v]), false)

+ StringIterState
  rw :s, :index
  -> new(@s)
    @index = 0

-> js_string_iter(s)
  it = js_new_special(js_realm().intrinsic("%StringIteratorPrototype%"), "String Iterator")
  it.internal = JS:StringIterState.new(s)
  it

-> js_string_iter_next(this)
  js_throw_type("next method called on incompatible receiver " + js_err_display(this)) if !(js_special?(this, "String Iterator") && this.internal.is_a?(JS:StringIterState))
  st = this.internal
  s = st.s
  return js_iter_result(nil, true) if s == nil
  i = st.index
  if i >= s.size
    st.s = nil
    return js_iter_result(nil, true)
  b = s.byte_at(i)
  w = b < 128 ? 1 : (b < 224 ? 2 : (b < 240 ? 3 : 4))
  w = s.size - i if i + w > s.size
  st.index = i + w
  js_iter_result(s.slice(i, w), false)

# ---- Iterator helpers (ES2025) ----

+ IterHelper
  rw :src, :fun, :mode, :count, :limit, :inner, :done, :running
  -> new(@src, @fun, @mode, @limit)
    @count = 0
    @inner = nil
    @done = false
    @running = false

-> js_get_iter_direct(o)
  js_throw_type(js_err_display(o) + " is not an object") if !js_object?(o)
  JS:IterRecord.new(o, jget(o, "next"))

-> js_iter_helper(this, mode, f, limit_v)
  js_throw_type(js_err_display(this) + " is not an object") if !js_object?(this)
  limit = 0
  if mode == :map || mode == :filter || mode == :flat_map
    if !js_callable?(f)
      js_iter_close_quiet(JS:IterRecord.new(this, nil))
      js_throw_type(js_err_display(f) + " is not a function")
  else
    limit = js_iter_limit_or_close(this, limit_v)
  rec = js_get_iter_direct(this)
  h = js_new_special(js_realm().intrinsic("%IteratorHelperPrototype%"), "Iterator Helper")
  h.internal = JS:IterHelper.new(rec, f, mode, limit)
  h

-> js_this_helper(v)
  js_throw_type("Iterator Helper method called on incompatible receiver " + js_err_display(v)) if !(js_special?(v, "Iterator Helper") && v.internal.is_a?(JS:IterHelper))
  v.internal

-> js_iter_helper_next(this)
  h = js_this_helper(this)
  js_throw_type("Generator is already running") if h.running
  return js_iter_result(nil, true) if h.done
  h.running = true
  r = nil
  begin
    r = js_iter_helper_step(h)
  rescue e
    h.running = false
    raise e
  h.running = false
  r

-> js_iter_helper_step(h)
  m = h.mode
  while true
    if m == :take && h.count >= h.limit
      h.done = true
      js_iter_close(h.src)
      return js_iter_result(nil, true)
    if m == :drop
      while h.count < h.limit
        x = js_iter_step_done(h, h.src)
        return js_iter_result(nil, true) if x == JS_ITER_DONE
        h.count += 1
    if m == :flat_map && h.inner != nil
      y = js_flat_inner_step(h)
      return js_iter_result(y, false) if y != JS_ITER_DONE
      h.done = false
      h.inner = nil
    x = js_iter_step_done(h, h.src)
    return js_iter_result(nil, true) if x == JS_ITER_DONE
    c = h.count
    h.count += 1 if m != :drop
    if m == :map
      return js_iter_result(js_helper_cb(h, [x, c + ~0.0]), false)
    if m == :filter
      return js_iter_result(x, false) if js_truthy(js_helper_cb(h, [x, c + ~0.0]))
    elsif m == :take || m == :drop
      return js_iter_result(x, false)
    elsif m == :flat_map
      inner = js_helper_cb(h, [x, c + ~0.0])
      h.inner = js_get_iterator_flattenable(h, inner)
  nil

# IteratorStep that marks the helper done when the source is exhausted or throws.
-> js_iter_step_done(h, rec)
  x = nil
  begin
    x = js_iter_step(rec)
  rescue e
    h.done = true
    raise e
  h.done = true if x == JS_ITER_DONE
  x

# flatMap's inner step: when it throws, the underlying iterator is closed too.
-> js_flat_inner_step(h)
  y = nil
  begin
    y = js_iter_step(h.inner)
  rescue e
    h.done = true
    h.inner = nil
    js_iter_close_quiet(h.src)
    raise e
  y

# GetIteratorFlattenable (reject-strings): flatMap's mapper result.
-> js_get_iterator_flattenable(h, v)
  begin
    js_throw_type(js_err_display(v) + " is not an object") if !js_object?(v)
    m = js_get_method(v, SYM_ITERATOR)
    it = m == nil ? v : js_call_arr(m, v, JS_NO_ARGS)
    js_throw_type("not an iterator") if !js_object?(it)
    return JS:IterRecord.new(it, jget(it, "next"))
  rescue e
    h.done = true
    js_iter_close_quiet(h.src)
    raise e
  nil

-> js_iter_reduce_like(this, mode, f, init, has_init)
  js_throw_type(js_err_display(this) + " is not an object") if !js_object?(this)
  if mode != :to_array && !js_callable?(f)
    js_iter_close_quiet(JS:IterRecord.new(this, nil))
    js_throw_type(js_err_display(f) + " is not a function")
  rec = js_get_iter_direct(this)
  acc = init
  started = has_init
  out = []
  i = 0
  while true
    x = js_iter_step(rec)
    break if x == JS_ITER_DONE
    if mode == :to_array
      out.push(x)
    elsif mode == :for_each
      js_rec_cb(rec, f, [x, i + ~0.0])
    elsif mode == :some
      if js_truthy(js_rec_cb(rec, f, [x, i + ~0.0]))
        js_iter_close(rec)
        return true
    elsif mode == :every
      if !js_truthy(js_rec_cb(rec, f, [x, i + ~0.0]))
        js_iter_close(rec)
        return false
    elsif mode == :find
      if js_truthy(js_rec_cb(rec, f, [x, i + ~0.0]))
        js_iter_close(rec)
        return x
    elsif mode == :reduce
      if !started
        acc = x
        started = true
      else
        acc = js_rec_cb(rec, f, [acc, x, i + ~0.0])
    i += 1
  return js_realm().adopt_array(out) if mode == :to_array
  return false if mode == :some
  return true if mode == :every
  js_throw_type("Reduce of empty iterator with no initial value") if mode == :reduce && !started
  return acc if mode == :reduce
  nil

-> js_iterator_from(v)
  if js_string?(v)
    return js_string_iter(v) if js_string_iter_pristine?()
  else
    js_throw_type(js_err_display(v) + " is not an object") if !js_object?(v)
  m = js_get_method(v, SYM_ITERATOR)
  it = m == nil ? v : js_call_arr(m, v, JS_NO_ARGS)
  js_throw_type("not an iterator") if !js_object?(it)
  r = js_realm()
  nx = jget(it, "next")
  return it if js_is_proto_of(r.intrinsic("%IteratorPrototype%"), it)
  w = js_new_special(r.intrinsic("%WrapForValidIteratorPrototype%"), "WrapForValidIterator")
  w.internal = JS:IterHelper.new(JS:IterRecord.new(it, nx), nil, :wrap, 0)
  w

-> js_this_wrap(v)
  js_throw_type("incompatible receiver " + js_err_display(v)) if !(js_special?(v, "WrapForValidIterator") && v.internal.is_a?(JS:IterHelper))
  v.internal

-> js_wrap_return(this)
  h = js_this_wrap(this)
  it = h.src.iterator
  ret = js_get_method(it, "return")
  return js_iter_result(nil, true) if ret == nil
  js_call_arr(ret, it, JS_NO_ARGS)

js_install(->(r) js_install_iter(r))

-> js_install_iter(r)
  op = r.object_proto
  fp = r.function_proto
  ip = js_new_object(op)
  r.set_intrinsic("%IteratorPrototype%", ip)
  sit = r.native("\[Symbol.iterator]", 0, ->(this, args, nt) this)
  ip.define(SYM_ITERATOR, sit, BUILTIN_ATTRS)
  # Iterator constructor and helpers
  ic = r.constructor("Iterator", 0, ->(this, args, nt) js_iterator_ctor(nt), ip)
  r.method(ic, "from", 1, ->(this, args, nt) js_iterator_from(js_arg(args, 0)))
  r.method(ip, "map", 1, ->(this, args, nt) js_iter_helper(this, :map, js_arg(args, 0), nil))
  r.method(ip, "filter", 1, ->(this, args, nt) js_iter_helper(this, :filter, js_arg(args, 0), nil))
  r.method(ip, "take", 1, ->(this, args, nt) js_iter_helper(this, :take, nil, js_arg(args, 0)))
  r.method(ip, "drop", 1, ->(this, args, nt) js_iter_helper(this, :drop, nil, js_arg(args, 0)))
  r.method(ip, "flatMap", 1, ->(this, args, nt) js_iter_helper(this, :flat_map, js_arg(args, 0), nil))
  r.method(ip, "toArray", 0, ->(this, args, nt) js_iter_reduce_like(this, :to_array, nil, nil, false))
  r.method(ip, "forEach", 1, ->(this, args, nt) js_iter_reduce_like(this, :for_each, js_arg(args, 0), nil, false))
  r.method(ip, "some", 1, ->(this, args, nt) js_iter_reduce_like(this, :some, js_arg(args, 0), nil, false))
  r.method(ip, "every", 1, ->(this, args, nt) js_iter_reduce_like(this, :every, js_arg(args, 0), nil, false))
  r.method(ip, "find", 1, ->(this, args, nt) js_iter_reduce_like(this, :find, js_arg(args, 0), nil, false))
  r.method(ip, "reduce", 1, ->(this, args, nt) js_iter_reduce_like(this, :reduce, js_arg(args, 0), js_arg(args, 1), args.size > 1))
  r.getter(ip, SYM_TO_STRING_TAG, ->(this, args, nt) "Iterator", ->(this, args, nt) js_iter_proto_set(this, SYM_TO_STRING_TAG, js_arg(args, 0)))
  r.getter(ip, "constructor", ->(this, args, nt) r.intrinsic("Iterator"), ->(this, args, nt) js_iter_proto_set(this, "constructor", js_arg(args, 0)))
  hp = js_new_object(ip)
  r.set_intrinsic("%IteratorHelperPrototype%", hp)
  r.method(hp, "next", 0, ->(this, args, nt) js_iter_helper_next(this))
  r.method(hp, "return", 0, ->(this, args, nt) js_iter_helper_return(this))
  hp.define(SYM_TO_STRING_TAG, "Iterator Helper", ATTR_C)
  wp = js_new_object(ip)
  r.set_intrinsic("%WrapForValidIteratorPrototype%", wp)
  r.method(wp, "next", 0, ->(this, args, nt) js_call_arr(js_this_wrap(this).src.next_fn, js_this_wrap(this).src.iterator, JS_NO_ARGS))
  r.method(wp, "return", 0, ->(this, args, nt) js_wrap_return(this))
  # array iterator
  aip = js_new_object(ip)
  r.set_intrinsic("%ArrayIteratorPrototype%", aip)
  an = r.method(aip, "next", 0, ->(this, args, nt) js_array_iter_next(this))
  r.set_intrinsic("%ArrayIteratorProto_next%", an)
  aip.define(SYM_TO_STRING_TAG, "Array Iterator", ATTR_C)
  # string iterator
  sip = js_new_object(ip)
  r.set_intrinsic("%StringIteratorPrototype%", sip)
  sn = r.method(sip, "next", 0, ->(this, args, nt) js_string_iter_next(this))
  r.set_intrinsic("%StringIteratorProto_next%", sn)
  sip.define(SYM_TO_STRING_TAG, "String Iterator", ATTR_C)
  # generators
  gfp = js_new_object(fp)
  r.set_intrinsic("%GeneratorFunction.prototype%", gfp)
  gp = js_new_object(ip)
  r.set_intrinsic("%GeneratorPrototype%", gp)
  gfp.define("prototype", gp, ATTR_C)
  gp.define("constructor", gfp, ATTR_C)
  gfp.define(SYM_TO_STRING_TAG, "GeneratorFunction", ATTR_C)
  gp.define(SYM_TO_STRING_TAG, "Generator", ATTR_C)
  r.method(gp, "next", 1, ->(this, args, nt) js_gen_resume(js_req_gen(this), :next, js_arg(args, 0)))
  r.method(gp, "return", 1, ->(this, args, nt) js_gen_resume(js_req_gen(this), :return, js_arg(args, 0)))
  r.method(gp, "throw", 1, ->(this, args, nt) js_gen_resume(js_req_gen(this), :throw, js_arg(args, 0)))
  gfc = js_kind_ctor(r, "GeneratorFunction", :generator)
  gfc.define("prototype", gfp, 0)
  gfp.define("constructor", gfc, ATTR_C)
  r.set_intrinsic("GeneratorFunction", gfc)
  # async functions
  afp = js_new_object(fp)
  r.set_intrinsic("%AsyncFunction.prototype%", afp)
  afp.define(SYM_TO_STRING_TAG, "AsyncFunction", ATTR_C)
  afc = js_kind_ctor(r, "AsyncFunction", :async)
  afc.define("prototype", afp, 0)
  afp.define("constructor", afc, ATTR_C)
  r.set_intrinsic("AsyncFunction", afc)
  # async iterators and generators
  aiter = js_new_object(op)
  r.set_intrinsic("%AsyncIteratorPrototype%", aiter)
  asit = r.native("\[Symbol.asyncIterator]", 0, ->(this, args, nt) this)
  aiter.define(SYM_ASYNC_ITERATOR, asit, BUILTIN_ATTRS)
  agfp = js_new_object(fp)
  r.set_intrinsic("%AsyncGeneratorFunction.prototype%", agfp)
  agp = js_new_object(aiter)
  r.set_intrinsic("%AsyncGeneratorPrototype%", agp)
  agfp.define("prototype", agp, ATTR_C)
  agp.define("constructor", agfp, ATTR_C)
  agfp.define(SYM_TO_STRING_TAG, "AsyncGeneratorFunction", ATTR_C)
  agp.define(SYM_TO_STRING_TAG, "AsyncGenerator", ATTR_C)
  r.method(agp, "next", 1, ->(this, args, nt) js_async_gen_enqueue(this, :next, js_arg(args, 0)))
  r.method(agp, "return", 1, ->(this, args, nt) js_async_gen_enqueue(this, :return, js_arg(args, 0)))
  r.method(agp, "throw", 1, ->(this, args, nt) js_async_gen_enqueue(this, :throw, js_arg(args, 0)))
  agfc = js_kind_ctor(r, "AsyncGeneratorFunction", :async_gen)
  agfc.define("prototype", agfp, 0)
  agfp.define("constructor", agfc, ATTR_C)
  r.set_intrinsic("AsyncGeneratorFunction", agfc)
  nil

# GeneratorFunction, AsyncFunction, AsyncGeneratorFunction: constructors (not globals)
# whose prototype is %Function%.
-> js_kind_ctor(r, name, kind)
  c = r.native(name, 1, ->(this, args, nt) js_function_ctor(args, kind), true)
  c.set_prototype_of(r.intrinsic("Function"))
  c

# SetterThatIgnoresPrototypeProperties (Iterator.prototype's toStringTag and constructor).
-> js_iter_proto_set(this, key, v)
  js_throw_type("Iterator.prototype setter called on non-object") if !js_object?(this)
  js_throw_type("Cannot assign to read only property of Iterator.prototype") if this == js_realm().intrinsic("%IteratorPrototype%")
  if jget_own_property(this, key) == nil
    js_create_data(this, key, v)
  else
    jset(this, key, v)
  nil

-> js_iterator_ctor(nt)
  js_throw_type("Abstract class Iterator not directly constructable") if nt == nil || nt == js_realm().intrinsic("Iterator")
  js_new_object(js_realm().proto_from(nt, "Iterator"))

-> js_iter_limit(v)
  n = js_to_number(v)
  js_throw_range(js_err_display(v) + " must be positive") if n != n
  t = js_to_integer(n)
  js_throw_range(js_err_display(v) + " must be positive") if t < ~0.0
  return 9007199254740991 if t == INF
  t.to_i

# take/drop: a bad limit closes the underlying iterator first.
-> js_iter_limit_or_close(it, v)
  r = 0
  begin
    r = js_iter_limit(v)
  rescue e
    js_iter_close_quiet(JS:IterRecord.new(it, nil))
    raise e
  r

-> js_iter_helper_return(this)
  h = js_this_helper(this)
  js_throw_type("Generator is already running") if h.running
  if !h.done
    h.done = true
    js_iter_close(h.inner) if h.inner != nil
    js_iter_close(h.src) if h.src != nil
  js_iter_result(nil, true)

# IfAbruptCloseIterator: a callback that throws ends the helper and closes its sources.
-> js_helper_cb(h, args)
  r = nil
  begin
    r = js_call_arr(h.fun, nil, args)
  rescue e
    h.done = true
    js_iter_close_quiet(h.inner) if h.inner != nil
    h.inner = nil
    js_iter_close_quiet(h.src)
    raise e
  r

-> js_rec_cb(rec, f, args)
  r = nil
  begin
    r = js_call_arr(f, nil, args)
  rescue e
    js_iter_close_quiet(rec)
    raise e
  r
