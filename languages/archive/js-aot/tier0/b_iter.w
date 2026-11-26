# blade/js/b_iter — %IteratorPrototype% and the Iterator helpers, array and string
# iterators, generator and async-generator prototypes, the function-kind constructors.

+ JsArrayIter < JsObject
  rw :target, :index, :kind

-> js_array_iter(o, kind)
  r = JS_REALM[0]
  it = JsArrayIter.new(r.intrinsic("%ArrayIteratorPrototype%"), "Array Iterator")
  it.target = o
  it.index = 0
  it.kind = kind
  it

-> js_array_iter_next(this)
  js_throw_type("next method called on incompatible receiver") if !this.is_a?(JsArrayIter)
  o = this.target
  return js_iter_result(nil, true) if o == nil
  i = this.index
  n = o.is_a?(JsArray) ? o.length : (o.is_a?(JsTypedArray) ? o.length : js_len_of(o))
  if i >= n
    this.target = nil
    return js_iter_result(nil, true)
  this.index = i + 1
  k = this.kind
  return js_iter_result(i + ~0.0, false) if k == :keys
  v = js_el(o, i)
  return js_iter_result(v, false) if k == :values
  js_iter_result(JS_REALM[0].new_array([i + ~0.0, v]), false)

+ JsStringIter < JsObject
  rw :s, :index

-> js_string_iter(s)
  it = JsStringIter.new(JS_REALM[0].intrinsic("%StringIteratorPrototype%"), "String Iterator")
  it.s = s
  it.index = 0
  it

-> js_string_iter_next(this)
  js_throw_type("next method called on incompatible receiver") if !this.is_a?(JsStringIter)
  s = this.s
  return js_iter_result(nil, true) if s == nil
  i = this.index
  if i >= s.size
    this.s = nil
    return js_iter_result(nil, true)
  b = s.byte_at(i)
  w = b < 0x80 ? 1 : (b < 0xE0 ? 2 : (b < 0xF0 ? 3 : 4))
  w = s.size - i if i + w > s.size
  this.index = i + w
  js_iter_result(s.slice(i, w), false)

# ---- Iterator helpers (ES2025) ----

+ JsIterHelper < JsObject
  rw :src, :fun, :mode, :count, :limit, :inner, :done

-> js_get_iter_direct(o)
  js_throw_type(js_to_display(o) + " is not an object") if !o.is_a?(JsObject)
  JsIterRecord.new(o, o.get("next", o))

-> js_iter_helper(this, mode, f, limit)
  rec = js_get_iter_direct(this)
  if mode == :map || mode == :filter || mode == :flat_map
    js_throw_type(js_to_display(f) + " is not a function") if !(f.is_a?(JsObject) && f.callable?)
  h = JsIterHelper.new(JS_REALM[0].intrinsic("%IteratorHelperPrototype%"), "Iterator Helper")
  h.src = rec
  h.fun = f
  h.mode = mode
  h.count = 0
  h.limit = limit
  h.inner = nil
  h.done = false
  h

-> js_iter_helper_next(h)
  js_throw_type("not an iterator helper") if !h.is_a?(JsIterHelper)
  return js_iter_result(nil, true) if h.done
  m = h.mode
  while true
    if m == :take && h.count >= h.limit
      h.done = true
      js_iter_close(h.src)
      return js_iter_result(nil, true)
    if m == :drop
      while h.count < h.limit
        x = js_iter_step(h.src)
        if x == JS_ITER_DONE
          h.done = true
          return js_iter_result(nil, true)
        h.count += 1
    if m == :flat_map && h.inner != nil
      y = js_iter_step(h.inner)
      return js_iter_result(y, false) if y != JS_ITER_DONE
      h.inner = nil
    x = js_iter_step(h.src)
    if x == JS_ITER_DONE
      h.done = true
      return js_iter_result(nil, true)
    c = h.count
    h.count += 1 if m != :drop
    if m == :map
      return js_iter_result(js_helper_cb(h, [x, c + ~0.0]), false)
    if m == :filter
      return js_iter_result(x, false) if js_truthy(js_helper_cb(h, [x, c + ~0.0]))
    elsif m == :take || m == :drop
      return js_iter_result(x, false)
    elsif m == :flat_map
      h.inner = js_get_iterator(js_helper_cb(h, [x, c + ~0.0]))
  nil

-> js_iter_reduce_like(this, mode, f, init, has_init)
  rec = js_get_iter_direct(this)
  js_throw_type(js_to_display(f) + " is not a function") if mode != :to_array && !(f.is_a?(JsObject) && f.callable?)
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
  return JS_REALM[0].new_array(out) if mode == :to_array
  return false if mode == :some
  return true if mode == :every
  js_throw_type("Reduce of empty iterator with no initial value") if mode == :reduce && !started
  return acc if mode == :reduce
  nil

-> js_iterator_from(v)
  if v.is_a?(String)
    return js_string_iter(v)
  m = js_get_method(v, SYM_ITERATOR)
  it = m == nil ? v : js_call(m, v, JS_NO_ARGS)
  js_throw_type("not an iterator") if !it.is_a?(JsObject)
  r = JS_REALM[0]
  return it if js_is_proto_of(r.intrinsic("%IteratorPrototype%"), it)
  w = JsIterHelper.new(r.intrinsic("%WrapForValidIteratorPrototype%"), "Object")
  w.src = JsIterRecord.new(it, it.get("next", it))
  w

js_install(->(r) js_install_iter(r))

-> js_install_iter(r)
  op = r.object_proto
  fp = r.function_proto
  ip = JsObject.new(op, "Object")
  r.set_intrinsic("%IteratorPrototype%", ip)
  sit = r.native("\[Symbol.iterator]", 0, ->(this, args, nt) this)
  ip.define(SYM_ITERATOR, sit, BUILTIN_ATTRS)
  # Iterator constructor and helpers
  ic = r.constructor("Iterator", 0, ->(this, args, nt) js_iterator_ctor(nt), ip)
  r.method(ic, "from", 1, ->(this, args, nt) js_iterator_from(js_arg(args, 0)))
  r.method(ip, "map", 1, ->(this, args, nt) js_iter_helper(this, :map, js_arg(args, 0), 0))
  r.method(ip, "filter", 1, ->(this, args, nt) js_iter_helper(this, :filter, js_arg(args, 0), 0))
  r.method(ip, "take", 1, ->(this, args, nt) js_iter_helper(this, :take, nil, js_iter_limit(js_arg(args, 0))))
  r.method(ip, "drop", 1, ->(this, args, nt) js_iter_helper(this, :drop, nil, js_iter_limit(js_arg(args, 0))))
  r.method(ip, "flatMap", 1, ->(this, args, nt) js_iter_helper(this, :flat_map, js_arg(args, 0), 0))
  r.method(ip, "toArray", 0, ->(this, args, nt) js_iter_reduce_like(this, :to_array, nil, nil, false))
  r.method(ip, "forEach", 1, ->(this, args, nt) js_iter_reduce_like(this, :for_each, js_arg(args, 0), nil, false))
  r.method(ip, "some", 1, ->(this, args, nt) js_iter_reduce_like(this, :some, js_arg(args, 0), nil, false))
  r.method(ip, "every", 1, ->(this, args, nt) js_iter_reduce_like(this, :every, js_arg(args, 0), nil, false))
  r.method(ip, "find", 1, ->(this, args, nt) js_iter_reduce_like(this, :find, js_arg(args, 0), nil, false))
  r.method(ip, "reduce", 1, ->(this, args, nt) js_iter_reduce_like(this, :reduce, js_arg(args, 0), js_arg(args, 1), args.size > 1))
  ip.define(SYM_TO_STRING_TAG, "Iterator", ATTR_W + ATTR_C)
  hp = JsObject.new(ip, "Object")
  r.set_intrinsic("%IteratorHelperPrototype%", hp)
  r.method(hp, "next", 0, ->(this, args, nt) js_iter_helper_next(this))
  r.method(hp, "return", 0, ->(this, args, nt) js_iter_helper_return(this))
  hp.define(SYM_TO_STRING_TAG, "Iterator Helper", ATTR_C)
  wp = JsObject.new(ip, "Object")
  r.set_intrinsic("%WrapForValidIteratorPrototype%", wp)
  r.method(wp, "next", 0, ->(this, args, nt) js_call(this.src.next_fn, this.src.iterator, JS_NO_ARGS))
  r.method(wp, "return", 0, ->(this, args, nt) js_iter_helper_return(this))
  # array iterator
  aip = JsObject.new(ip, "Object")
  r.set_intrinsic("%ArrayIteratorPrototype%", aip)
  an = r.method(aip, "next", 0, ->(this, args, nt) js_array_iter_next(this))
  r.set_intrinsic("%ArrayIteratorProto_next%", an)
  aip.define(SYM_TO_STRING_TAG, "Array Iterator", ATTR_C)
  # string iterator
  sip = JsObject.new(ip, "Object")
  r.set_intrinsic("%StringIteratorPrototype%", sip)
  sn = r.method(sip, "next", 0, ->(this, args, nt) js_string_iter_next(this))
  r.set_intrinsic("%StringIteratorProto_next%", sn)
  sip.define(SYM_TO_STRING_TAG, "String Iterator", ATTR_C)
  # generators
  gfp = JsObject.new(fp, "Object")
  r.set_intrinsic("%GeneratorFunction.prototype%", gfp)
  gp = JsObject.new(ip, "Object")
  r.set_intrinsic("%GeneratorPrototype%", gp)
  gfp.define("prototype", gp, ATTR_C)
  gp.define("constructor", gfp, ATTR_C)
  gfp.define(SYM_TO_STRING_TAG, "GeneratorFunction", ATTR_C)
  gp.define(SYM_TO_STRING_TAG, "Generator", ATTR_C)
  r.method(gp, "next", 1, ->(this, args, nt) js_gen_resume(js_req_gen(this), :next, js_arg(args, 0)))
  r.method(gp, "return", 1, ->(this, args, nt) js_gen_resume(js_req_gen(this), :return, js_arg(args, 0)))
  r.method(gp, "throw", 1, ->(this, args, nt) js_gen_resume(js_req_gen(this), :throw, js_arg(args, 0)))
  gfc = JsFunction.new(r.intrinsic("Function"), ->(this, args, nt) js_function_ctor(args, :generator), "GeneratorFunction", 1, true)
  gfc.define("prototype", gfp, 0)
  gfp.define("constructor", gfc, ATTR_C)
  # async functions
  afp = JsObject.new(fp, "Object")
  r.set_intrinsic("%AsyncFunction.prototype%", afp)
  afp.define(SYM_TO_STRING_TAG, "AsyncFunction", ATTR_C)
  afc = JsFunction.new(r.intrinsic("Function"), ->(this, args, nt) js_function_ctor(args, :async), "AsyncFunction", 1, true)
  afc.define("prototype", afp, 0)
  afp.define("constructor", afc, ATTR_C)
  # async iterators and generators
  aiter = JsObject.new(op, "Object")
  r.set_intrinsic("%AsyncIteratorPrototype%", aiter)
  asit = r.native("\[Symbol.asyncIterator]", 0, ->(this, args, nt) this)
  aiter.define(SYM_ASYNC_ITERATOR, asit, BUILTIN_ATTRS)
  agfp = JsObject.new(fp, "Object")
  r.set_intrinsic("%AsyncGeneratorFunction.prototype%", agfp)
  agp = JsObject.new(aiter, "Object")
  r.set_intrinsic("%AsyncGeneratorPrototype%", agp)
  agfp.define("prototype", agp, ATTR_C)
  agp.define("constructor", agfp, ATTR_C)
  agfp.define(SYM_TO_STRING_TAG, "AsyncGeneratorFunction", ATTR_C)
  agp.define(SYM_TO_STRING_TAG, "AsyncGenerator", ATTR_C)
  r.method(agp, "next", 1, ->(this, args, nt) js_async_gen_enqueue(this, :next, js_arg(args, 0)))
  r.method(agp, "return", 1, ->(this, args, nt) js_async_gen_enqueue(this, :return, js_arg(args, 0)))
  r.method(agp, "throw", 1, ->(this, args, nt) js_async_gen_enqueue(this, :throw, js_arg(args, 0)))
  agfc = JsFunction.new(r.intrinsic("Function"), ->(this, args, nt) js_function_ctor(args, :async_gen), "AsyncGeneratorFunction", 1, true)
  agfc.define("prototype", agfp, 0)
  agfp.define("constructor", agfc, ATTR_C)
  nil

-> js_iterator_ctor(nt)
  js_throw_type("Abstract class Iterator not directly constructable") if nt == nil || nt == JS_REALM[0].intrinsic("Iterator")
  JsObject.new(JS_REALM[0].proto_from(nt, "Iterator"), "Object")

-> js_iter_limit(v)
  n = js_to_number(v)
  raise JsThrow.new(js_range_error(js_to_display(v) + " must be positive")) if n != n || n < ~0.0
  return 9007199254740991 if n == INF
  js_to_integer(n).to_i

-> js_iter_helper_return(h)
  if h.is_a?(JsIterHelper) && !h.done
    h.done = true
    js_iter_close(h.src) if h.src != nil
    js_iter_close(h.inner) if h.inner != nil
  js_iter_result(nil, true)

-> js_req_gen(g)
  js_throw_type("next method called on incompatible receiver " + js_to_display(g)) if !g.is_a?(JsGenerator)
  g

# IfAbruptCloseIterator: a callback that throws ends the helper and closes its sources.
-> js_helper_cb(h, args)
  r = nil
  begin
    r = js_call(h.fun, nil, args)
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
    r = js_call(f, nil, args)
  rescue e
    js_iter_close_quiet(rec)
    raise e
  r
