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
  return js_arr_len(o) if js_array?(o)
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
  rw :src, :fun, :mode, :count, :limit, :inner, :done, :running, :items, :started
  -> new(@src, @fun, @mode, @limit)
    @count = 0
    @inner = nil
    @done = false
    @running = false
    @items = nil
    @started = false

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
  h.started = true
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
  if m == :concat
    return js_iter_concat_step(h)
  if m == :chunks
    return js_iter_chunks_step(h)
  if m == :windows
    return js_iter_windows_step(h)
  if m == :zip
    return js_iter_zip_step(h)
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
  sdisp = r.native("\[Symbol.dispose]", 0, ->(this, args, nt) js_iter_dispose(this))
  ip.define(SYM_DISPOSE, sdisp, BUILTIN_ATTRS)
  # Iterator constructor and helpers
  ic = r.constructor("Iterator", 0, ->(this, args, nt) js_iterator_ctor(nt), ip)
  r.method(ic, "from", 1, ->(this, args, nt) js_iterator_from(js_arg(args, 0)))
  r.method(ic, "concat", 0, ->(this, args, nt) js_iterator_concat(args))
  r.method(ic, "zip", 1, ->(this, args, nt) js_iterator_zip(js_arg(args, 0), js_arg(args, 1), false))
  r.method(ic, "zipKeyed", 1, ->(this, args, nt) js_iterator_zip(js_arg(args, 0), js_arg(args, 1), true))
  r.method(ip, "map", 1, ->(this, args, nt) js_iter_helper(this, :map, js_arg(args, 0), nil))
  r.method(ip, "filter", 1, ->(this, args, nt) js_iter_helper(this, :filter, js_arg(args, 0), nil))
  r.method(ip, "take", 1, ->(this, args, nt) js_iter_helper(this, :take, nil, js_arg(args, 0)))
  r.method(ip, "drop", 1, ->(this, args, nt) js_iter_helper(this, :drop, nil, js_arg(args, 0)))
  r.method(ip, "flatMap", 1, ->(this, args, nt) js_iter_helper(this, :flat_map, js_arg(args, 0), nil))
  r.method(ip, "chunks", 1, ->(this, args, nt) js_iter_chunks_init(this, js_arg(args, 0)))
  r.method(ip, "windows", 1, ->(this, args, nt) js_iter_windows_init(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(ip, "includes", 1, ->(this, args, nt) js_iter_includes(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(ip, "join", 1, ->(this, args, nt) js_iter_join(this, js_arg(args, 0)))
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
  asdisp = r.native("\[Symbol.asyncDispose]", 0, ->(this, args, nt) js_async_iter_dispose(this))
  aiter.define(SYM_ASYNC_DISPOSE, asdisp, BUILTIN_ATTRS)
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
  c = r.native(name, 1, ->(this, args, nt) js_function_ctor(args, kind, nt), true)
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
  js_throw_range(js_err_display(v) + " exceeds MAX_SAFE_INTEGER") if n != INF && n > ~9007199254740991.0
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
    if h.started
      h.running = true
      begin
        if h.mode == :zip
          js_iter_close_all(h.items, false)
        else
          js_iter_close(h.inner) if h.inner.is_a?(JS:IterRecord)
          js_iter_close(h.src) if h.src != nil
      rescue e
        h.running = false
        raise e
      h.running = false
    else
      if h.mode == :zip
        js_iter_close_all(h.items, false)
      else
        js_iter_close(h.inner) if h.inner.is_a?(JS:IterRecord)
        js_iter_close(h.src) if h.src != nil
  js_iter_result(nil, true)

# ---- Iterator.concat, includes, join, chunks, windows, zip, zipKeyed ----

-> js_iterator_concat(args)
  iterables = []
  i = 0
  while i < args.size
    item = args[i]
    js_throw_type("Iterator.concat argument is not an object") if !js_object?(item)
    m = js_get_method(item, SYM_ITERATOR)
    js_throw_type("Iterator.concat argument is not iterable") if m == nil
    iterables.push([m, item])
    i += 1
  h = js_new_special(js_realm().intrinsic("%IteratorHelperPrototype%"), "Iterator Helper")
  st = JS:IterHelper.new(nil, nil, :concat, 0)
  st.items = iterables
  h.internal = st
  h

-> js_iter_concat_step(h)
  while true
    if h.inner == nil
      if h.count >= h.items.size
        h.done = true
        return js_iter_result(nil, true)
      pair = h.items[h.count]
      h.count += 1
      begin
        it = js_call_arr(pair[0], pair[1], JS_NO_ARGS)
        js_throw_type("Iterator is not an object") if !js_object?(it)
        h.inner = JS:IterRecord.new(it, jget(it, "next"))
      rescue e
        h.done = true
        raise e
    v = nil
    begin
      v = js_iter_step(h.inner)
    rescue e
      h.done = true
      h.inner = nil
      raise e
    if v == JS_ITER_DONE
      h.inner = nil
    else
      return js_iter_result(v, false)
  nil

-> js_iter_includes(this, search, skip_v)
  js_throw_type("Iterator.prototype.includes called on non-object") if !js_object?(this)
  iterated = JS:IterRecord.new(this, nil)
  to_skip = ~0.0
  if skip_v != nil
    if !js_number?(skip_v) || skip_v != skip_v || (js_finite?(skip_v) && skip_v != Math.floor(skip_v))
      js_iter_close_quiet(iterated)
      js_throw_type("skippedElements must be an integral number or Infinity")
    to_skip = skip_v
    if to_skip < ~0.0 || (to_skip != INF && to_skip > ~9007199254740991.0)
      js_iter_close_quiet(iterated)
      js_throw_range("skippedElements out of range")
  rec = js_get_iter_direct(this)
  skipped = ~0.0
  while true
    v = js_iter_step(rec)
    return false if v == JS_ITER_DONE
    if skipped < to_skip
      skipped = skipped + ~1.0
      next
    if js_same_value_zero(v, search)
      js_iter_close(rec)
      return true
  false

-> js_iter_join(this, sep_v)
  js_throw_type("Iterator.prototype.join called on non-object") if !js_object?(this)
  sep = ","
  if sep_v != nil
    begin
      sep = js_to_string(sep_v)
    rescue e
      js_iter_close_quiet(JS:IterRecord.new(this, nil))
      raise e
  rec = js_get_iter_direct(this)
  sb = StringBuffer()
  first = true
  while true
    v = js_iter_step(rec)
    break if v == JS_ITER_DONE
    sb.append(sep) if !first
    first = false
    if !js_nullish?(v)
      begin
        sb.append(js_to_string(v))
      rescue e
        js_iter_close_quiet(rec)
        raise e
  sb.to_s

-> js_iter_check_size(this, sz_v, what)
  iterated = JS:IterRecord.new(this, nil)
  if !js_is_integer?(sz_v)
    js_iter_close_quiet(iterated)
    js_throw_type(what + " size must be an integral number")
  if sz_v < ~1.0 || sz_v > ~4294967295.0
    js_iter_close_quiet(iterated)
    js_throw_range(what + " size out of range")
  sz_v.to_i

-> js_iter_chunks_init(this, sz_v)
  js_throw_type("Iterator.prototype.chunks called on non-object") if !js_object?(this)
  sz = js_iter_check_size(this, sz_v, "chunks")
  rec = js_get_iter_direct(this)
  h = js_new_special(js_realm().intrinsic("%IteratorHelperPrototype%"), "Iterator Helper")
  h.internal = JS:IterHelper.new(rec, nil, :chunks, sz)
  h

-> js_iter_chunks_step(h)
  buf = []
  while buf.size < h.limit
    x = js_iter_step_done(h, h.src)
    break if x == JS_ITER_DONE
    buf.push(x)
  return js_iter_result(nil, true) if buf.size == 0
  js_iter_result(js_realm().adopt_array(buf), false)

-> js_iter_windows_init(this, sz_v, under_v)
  js_throw_type("Iterator.prototype.windows called on non-object") if !js_object?(this)
  sz = js_iter_check_size(this, sz_v, "windows")
  under = under_v == nil ? "only-full" : under_v
  if under != "only-full" && under != "allow-partial"
    js_iter_close_quiet(JS:IterRecord.new(this, nil))
    js_throw_type("Invalid undersized option")
  rec = js_get_iter_direct(this)
  h = js_new_special(js_realm().intrinsic("%IteratorHelperPrototype%"), "Iterator Helper")
  st = JS:IterHelper.new(rec, under, :windows, sz)
  st.inner = []
  h.internal = st
  h

-> js_iter_windows_step(h)
  buf = h.inner
  if buf.size == h.limit
    x = js_iter_step_done(h, h.src)
    return js_iter_result(nil, true) if x == JS_ITER_DONE
    buf.delete_at(0)
    buf.push(x)
    return js_iter_result(js_realm().adopt_array(buf.dup), false)
  while buf.size < h.limit
    x = js_iter_step_done(h, h.src)
    if x == JS_ITER_DONE
      return js_iter_result(js_realm().adopt_array(buf.dup), false) if h.fun == "allow-partial" && buf.size > 0
      return js_iter_result(nil, true)
    buf.push(x)
  js_iter_result(js_realm().adopt_array(buf.dup), false)

-> js_iter_close_all(iters, quiet)
  err = nil
  has_err = false
  i = iters.size - 1
  while i >= 0
    rec = iters[i]
    iters[i] = nil
    if rec != nil && !rec.done
      if quiet
        js_iter_close_quiet(rec)
      else
        begin
          js_iter_close(rec)
        rescue e
          if !has_err
            err = e
            has_err = true
    i -= 1
  raise err if has_err
  nil

-> js_get_iter_flattenable_plain(v)
  js_throw_type(js_err_display(v) + " is not an object") if !js_object?(v)
  m = js_get_method(v, SYM_ITERATOR)
  it = m == nil ? v : js_call_arr(m, v, JS_NO_ARGS)
  js_throw_type("not an iterator") if !js_object?(it)
  JS:IterRecord.new(it, jget(it, "next"))

-> js_iterator_zip(iterables, opts, keyed)
  js_throw_type("Iterator." + (keyed ? "zipKeyed" : "zip") + " requires an object") if !js_object?(iterables)
  mode = "shortest"
  pad_opt = nil
  if opts != nil
    js_throw_type("options must be an object") if !js_object?(opts)
    mv = jget(opts, "mode")
    if mv != nil
      js_throw_type("Invalid mode option") if mv != "shortest" && mv != "longest" && mv != "strict"
      mode = mv
    if mode == "longest"
      pv = jget(opts, "padding")
      js_throw_type("padding must be an object") if pv != nil && !js_object?(pv)
      pad_opt = pv
  iters = []
  keys = keyed ? [] : nil
  if keyed
    begin
      all_k = jown_keys(iterables)
      ki = 0
      while ki < all_k.size
        k = all_k[ki]
        d = jget_own_property(iterables, k)
        if d != nil && d.enumerable == true
          v = jget(iterables, k)
          if v != nil
            iters.push(js_get_iter_flattenable_plain(v))
            keys.push(k)
        ki += 1
    rescue e
      js_iter_close_all(iters, true)
      raise e
  else
    outer = js_get_iterator(iterables)
    begin
      while true
        item = js_iter_step(outer)
        break if item == JS_ITER_DONE
        iters.push(js_get_iter_flattenable_plain(item))
    rescue e
      js_iter_close_all(iters, true)
      js_iter_close_quiet(outer) if !outer.done
      raise e
  padding = []
  if mode == "longest"
    if pad_opt == nil
      k = 0
      while k < iters.size
        padding.push(nil)
        k += 1
    elsif keyed
      begin
        k = 0
        while k < keys.size
          padding.push(jget(pad_opt, keys[k]))
          k += 1
      rescue e
        js_iter_close_all(iters, true)
        raise e
    else
      prec = nil
      begin
        prec = js_get_iterator(pad_opt)
        k = 0
        using_pad = true
        while k < iters.size
          if using_pad
            pv = js_iter_step(prec)
            if pv == JS_ITER_DONE
              using_pad = false
              padding.push(nil)
            else
              padding.push(pv)
          else
            padding.push(nil)
          k += 1
        js_iter_close(prec) if using_pad && !prec.done
      rescue e
        js_iter_close_quiet(prec) if prec != nil && !prec.done
        js_iter_close_all(iters, true)
        raise e
  h = js_new_special(js_realm().intrinsic("%IteratorHelperPrototype%"), "Iterator Helper")
  st = JS:IterHelper.new(nil, [mode, padding, keys], :zip, 0)
  st.items = iters
  h.internal = st
  h

-> js_iter_zip_step(h)
  iters = h.items
  n = iters.size
  if n == 0
    h.done = true
    return js_iter_result(nil, true)
  info = h.fun
  mode = info[0]
  padding = info[1]
  keys = info[2]
  results = []
  any_open = false
  i = 0
  while i < n
    rec = iters[i]
    if rec == nil
      results.push(padding[i])
      i += 1
      next
    v = nil
    begin
      v = js_iter_step(rec)
    rescue e
      iters[i] = nil
      h.done = true
      js_iter_close_all(iters, true)
      raise e
    if v == JS_ITER_DONE
      iters[i] = nil
      if mode == "shortest"
        h.done = true
        js_iter_close_all(iters, false)
        return js_iter_result(nil, true)
      if mode == "strict"
        if i != 0
          h.done = true
          js_iter_close_all(iters, true)
          js_throw_type("Iterator.zip strict mode: iterators ended at different lengths")
        j = 1
        while j < n
          r2 = iters[j]
          v2 = nil
          begin
            v2 = js_iter_step(r2)
          rescue e
            iters[j] = nil
            h.done = true
            js_iter_close_all(iters, true)
            raise e
          if v2 != JS_ITER_DONE
            h.done = true
            js_iter_close_all(iters, true)
            js_throw_type("Iterator.zip strict mode: iterators ended at different lengths")
          iters[j] = nil
          j += 1
        h.done = true
        return js_iter_result(nil, true)
      results.push(padding[i])
    else
      any_open = true
      results.push(v)
    i += 1
  if !any_open
    h.done = true
    return js_iter_result(nil, true)
  if keys == nil
    return js_iter_result(js_realm().adopt_array(results), false)
  obj = js_new_object(nil)
  k = 0
  while k < n
    obj.define(keys[k], results[k], ATTR_ALL)
    k += 1
  js_iter_result(obj, false)

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

-> js_iter_dispose(this)
  ret = js_get_method(this, "return")
  js_call_arr(ret, this, JS_NO_ARGS) if ret != nil
  nil

-> js_async_iter_dispose(this)
  r = js_realm()
  cap = js_new_capability()
  begin
    ret = js_get_method(this, "return")
    if ret == nil
      js_call_arr(cap.resolve, nil, [nil])
      return cap.promise
    res = js_call_arr(ret, this, JS_NO_ARGS)
    rw = js_promise_resolve_value(res)
    unwrap = r.native("", 1, ->(t2, a2, nt2) nil)
    js_perform_then(rw, JS:Reaction.new(cap, :fulfill, unwrap), JS:Reaction.new(cap, :reject, nil))
  rescue ex
    js_call_arr(cap.reject, nil, [js_error_value(ex)])
  cap.promise

-> js_rec_cb(rec, f, args)
  r = nil
  begin
    r = js_call_arr(f, nil, args)
  rescue e
    js_iter_close_quiet(rec)
    raise e
  r
