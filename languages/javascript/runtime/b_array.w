# blade/js/b_array — Array and Array.prototype (through ES2023), plus array-likes.
#
# Every method works on any array-like `this`; dense JsArrays take fast paths.

-> js_dense?(o)
  o.is_a?(JsArray) && o.slen == nil

-> js_len_of(o)
  return o.length if o.is_a?(JsArray)
  js_to_length(o.get("length", o))

# Element i of an array-like (holes read through the prototype chain, as [[Get]] does).
-> js_el(o, i)
  if o.is_a?(JsArray) && i < o.elems.size
    v = o.elems[i]
    return v if v != JS_HOLE
  o.get_idx(i)

-> js_has_el?(o, i)
  if o.is_a?(JsArray) && i < o.elems.size && o.elems[i] != JS_HOLE
    return true
  o.has_property?(i.to_s)

-> js_put_el(o, i, v)
  if o.is_a?(JsArray)
    el = o.elems
    if i < el.size && el[i] != JS_HOLE
      el[i] = v
      return nil
  ok = o.set(i.to_s, v, o)
  js_set_failed(o, i.to_s) if !ok
  nil

-> js_set_len(o, n)
  ok = o.set("length", n + ~0.0, o)
  js_set_failed(o, "length") if !ok
  nil

-> js_fn_arg(args, i, what)
  f = js_arg(args, i)
  js_throw_type(js_to_display(f) + " is not a function") if !(f.is_a?(JsObject) && f.callable?)
  f

-> js_rel_index(v, len, dflt)
  return dflt if v == nil
  n = js_to_integer(v)
  if n < ~0.0
    n = n + len
    return 0 if n < ~0.0
    return n.to_i
  return len if n > len + ~0.0
  n.to_i

# ArraySpeciesCreate (only the default constructor is honoured beyond plain arrays).
-> js_species_create(o, n)
  r = JS_REALM[0]
  if o.is_a?(JsArray)
    c = o.get("constructor", o)
    if c.is_a?(JsObject) && c != r.intrinsic("Array")
      s = c.get(SYM_SPECIES, c)
      if s.is_a?(JsObject) && js_is_constructor?(s)
        return js_construct(s, [n + ~0.0], nil)
  a = r.new_array([])
  a

-> js_array_ctor(args, nt)
  r = JS_REALM[0]
  proto = nt == nil ? r.array_proto : r.proto_from(nt, "Array")
  if args.size == 1 && args[0].is_a?(Float)
    n = args[0]
    len = js_to_uint32(n)
    raise JsThrow.new(js_range_error("Invalid array length")) if len + ~0.0 != n
    a = JsArray.new(proto, [])
    a.set_length(n)
    return a
  JsArray.new(proto, args.map(->(x) x))

-> js_array_from(this, items, mapfn, this_arg)
  r = JS_REALM[0]
  js_throw_type(js_to_display(mapfn) + " is not a function") if mapfn != nil && !(mapfn.is_a?(JsObject) && mapfn.callable?)
  usable = js_get_method(items, SYM_ITERATOR) if !js_nullish?(items)
  out = []
  # the mapper runs as each value is read (it may change the source)
  if usable != nil
    js_for_of(items, ->(x) out.push(mapfn == nil ? x : js_call(mapfn, this_arg, [x, out.size + ~0.0])))
  else
    o = js_to_object(items)
    n = js_len_of(o)
    k = 0
    while k < n
      x = js_el(o, k)
      out.push(mapfn == nil ? x : js_call(mapfn, this_arg, [x, k + ~0.0]))
      k += 1
  if this.is_a?(JsFunction) && this != r.intrinsic("Array") && js_is_constructor?(this)
    a = js_construct(this, [], nil)
    j = 0
    while j < out.size
      js_create_data(a, j.to_s, out[j])
      j += 1
    js_set_len(a, out.size)
    return a
  r.new_array(out)

-> js_array_of(this, args)
  r = JS_REALM[0]
  if this.is_a?(JsFunction) && this != r.intrinsic("Array") && js_is_constructor?(this)
    a = js_construct(this, [args.size + ~0.0], nil)
    j = 0
    while j < args.size
      js_create_data(a, j.to_s, args[j])
      j += 1
    js_set_len(a, args.size)
    return a
  r.new_array(args.map(->(x) x))

-> js_is_array(v)
  return true if v.is_a?(JsArray)
  return js_is_array(v.target_obj) if v.is_a?(JsObject) && v.proxy?
  false

# ---- iteration-style methods: f.call(value, index, obj) ----

-> js_arr_each(this, args, mode)
  o = js_to_object(this)
  n = js_len_of(o)
  f = js_fn_arg(args, 0, mode.to_s)
  t = js_arg(args, 1)
  r = JS_REALM[0]
  out = mode == :map ? Array.new(n, JS_HOLE) : (mode == :filter ? [] : nil)
  i = 0
  while i < n
    if js_has_el?(o, i)
      v = js_el(o, i)
      res = js_call(f, t, [v, i + ~0.0, o])
      if mode == :map
        out[i] = res
      elsif mode == :filter
        out.push(v) if js_truthy(res)
      elsif mode == :some
        return true if js_truthy(res)
      elsif mode == :every
        return false if !js_truthy(res)
    i += 1
  return r.new_array(out) if mode == :map || mode == :filter
  return false if mode == :some
  return true if mode == :every
  nil

-> js_arr_find(this, args, from_end, want_index)
  o = js_to_object(this)
  n = js_len_of(o)
  f = js_fn_arg(args, 0, "find")
  t = js_arg(args, 1)
  i = from_end ? n - 1 : 0
  while from_end ? i >= 0 : i < n
    v = js_el(o, i)
    if js_truthy(js_call(f, t, [v, i + ~0.0, o]))
      return want_index ? i + ~0.0 : v
    i += from_end ? -1 : 1
  want_index ? ~-1.0 : nil

-> js_arr_reduce(this, args, right)
  o = js_to_object(this)
  n = js_len_of(o)
  f = js_fn_arg(args, 0, "reduce")
  i = right ? n - 1 : 0
  acc = nil
  if args.size >= 2
    acc = args[1]
  else
    found = false
    while (right ? i >= 0 : i < n) && !found
      if js_has_el?(o, i)
        acc = js_el(o, i)
        found = true
      i += right ? -1 : 1
    js_throw_type("Reduce of empty array with no initial value") if !found
  while right ? i >= 0 : i < n
    if js_has_el?(o, i)
      acc = js_call(f, nil, [acc, js_el(o, i), i + ~0.0, o])
    i += right ? -1 : 1
  acc

-> js_arr_index_of(this, args, last)
  o = js_to_object(this)
  n = js_len_of(o)
  return ~-1.0 if n == 0
  x = js_arg(args, 0)
  if last
    i = args.size > 1 ? js_to_integer(args[1]) : n - ~1.0
    i = i < ~0.0 ? i + n : (i > n - ~1.0 ? n - ~1.0 : i)
    k = i.to_i
    while k >= 0
      return k + ~0.0 if js_has_el?(o, k) && js_strict_eq(js_el(o, k), x)
      k -= 1
    return ~-1.0
  k = js_rel_index(js_arg(args, 1), n, 0)
  if js_dense?(o)
    el = o.elems
    while k < el.size
      v = el[k]
      return k + ~0.0 if v != JS_HOLE && js_strict_eq(v, x)
      k += 1
    return ~-1.0
  while k < n
    return k + ~0.0 if js_has_el?(o, k) && js_strict_eq(js_el(o, k), x)
    k += 1
  ~-1.0

-> js_arr_includes(this, args)
  o = js_to_object(this)
  n = js_len_of(o)
  x = js_arg(args, 0)
  k = js_rel_index(js_arg(args, 1), n, 0)
  while k < n
    return true if js_same_value_zero(js_el(o, k), x)
    k += 1
  false

-> js_arr_join(this, sep_v)
  o = js_to_object(this)
  n = js_len_of(o)
  sep = sep_v == nil ? "," : js_to_string(sep_v)
  r = JS_REALM[0]
  return "" if r.join_guard.include?(o)
  r.join_guard.push(o)
  sb = StringBuffer()
  begin
    i = 0
    while i < n
      sb.append(sep) if i > 0
      v = js_el(o, i)
      sb.append(js_to_string(v)) if !js_nullish?(v)
      i += 1
  rescue e
    r.join_guard.pop
    raise e
  r.join_guard.pop
  sb.to_s

-> js_arr_to_string(this)
  o = js_to_object(this)
  j = o.get("join", o)
  return js_call(j, o, JS_NO_ARGS) if j.is_a?(JsObject) && j.callable?
  js_object_to_string(o)

-> js_arr_push(this, args)
  if js_dense?(this) && this.extensible && !this.len_ro
    args.each ->(x) this.elems.push(x)
    return this.elems.size + ~0.0
  o = js_to_object(this)
  n = js_len_of(o)
  args.each ->(x)
    js_put_el_set(o, n, x)
    n += 1
  js_set_len(o, n)
  n + ~0.0

-> js_put_el_set(o, i, v)
  ok = o.set(i.to_s, v, o)
  js_set_failed(o, i.to_s) if !ok

-> js_arr_pop(this)
  if js_dense?(this) && this.extensible && !this.len_ro
    return nil if this.elems.size == 0
    v = js_arr_elem(this, this.elems.size - 1)
    this.elems.pop
    return v
  o = js_to_object(this)
  n = js_len_of(o)
  if n == 0
    js_set_len(o, 0)
    return nil
  v = js_el(o, n - 1)
  js_delete(o, (n - 1).to_s, true)
  js_set_len(o, n - 1)
  v

-> js_arr_shift(this)
  if js_dense?(this) && this.extensible && !this.len_ro
    return nil if this.elems.size == 0
    v = js_arr_elem(this, 0)
    this.elems.shift
    return v
  o = js_to_object(this)
  n = js_len_of(o)
  if n == 0
    js_set_len(o, 0)
    return nil
  first = js_el(o, 0)
  k = 1
  while k < n
    if js_has_el?(o, k)
      js_put_el_set(o, k - 1, js_el(o, k))
    else
      js_delete(o, (k - 1).to_s, true)
    k += 1
  js_delete(o, (n - 1).to_s, true)
  js_set_len(o, n - 1)
  first

-> js_arr_unshift(this, args)
  if js_dense?(this) && this.extensible && !this.len_ro
    i = args.size - 1
    while i >= 0
      this.elems.unshift(args[i])
      i -= 1
    return this.elems.size + ~0.0
  o = js_to_object(this)
  n = js_len_of(o)
  c = args.size
  k = n
  while k > 0
    if js_has_el?(o, k - 1)
      js_put_el_set(o, k + c - 1, js_el(o, k - 1))
    else
      js_delete(o, (k + c - 1).to_s, true)
    k -= 1
  j = 0
  while j < c
    js_put_el_set(o, j, args[j])
    j += 1
  js_set_len(o, n + c)
  (n + c) + ~0.0

-> js_arr_slice(this, args)
  o = js_to_object(this)
  n = js_len_of(o)
  a = js_rel_index(js_arg(args, 0), n, 0)
  b = js_rel_index(js_arg(args, 1), n, n)
  r = JS_REALM[0]
  if js_dense?(o) && o.class_name == "JsArray" && o.proto == r.array_proto && b <= o.elems.size
    return r.new_array(b > a ? o.elems.slice(a, b - a) : [])
  res = js_species_create(o, b > a ? b - a : 0)
  k = a
  j = 0
  while k < b
    js_create_data(res, j.to_s, js_el(o, k)) if js_has_el?(o, k)
    k += 1
    j += 1
  js_set_len(res, j) if !res.is_a?(JsArray) || res.length != j
  res

-> js_arr_splice(this, args)
  o = js_to_object(this)
  n = js_len_of(o)
  start = js_rel_index(js_arg(args, 0), n, 0)
  dc = 0
  if args.size == 0
    dc = 0
  elsif args.size == 1
    dc = n - start
  else
    d = js_to_integer(args[1])
    d = ~0.0 if d < ~0.0
    dc = d > (n - start) + ~0.0 ? n - start : d.to_i
  items = args.size > 2 ? args.slice(2, args.size - 2) : []
  r = JS_REALM[0]
  if js_dense?(o) && o.extensible && !o.len_ro && o.proto == r.array_proto && !r.array_proto_indexed && o.class_name == "JsArray"
    el = o.elems
    # copies: slices may share el's storage, which the pushes below overwrite
    removed = el.slice(start, dc).dup
    tail = el.slice(start + dc, el.size - start - dc).dup
    while el.size > start
      el.pop
    items.each ->(x) el.push(x)
    tail.each ->(x) el.push(x)
    # holes stay holes in the result (only present elements are copied)
    return r.new_array(removed)
  removed = r.new_array(Array.new(dc, JS_HOLE))
  k = 0
  while k < dc
    removed.elems[k] = js_el(o, start + k) if js_has_el?(o, start + k)
    k += 1
  ic = items.size
  if ic < dc
    k = start
    while k < n - dc
      if js_has_el?(o, k + dc)
        js_put_el_set(o, k + ic, js_el(o, k + dc))
      else
        js_delete(o, (k + ic).to_s, true)
      k += 1
    k = n
    while k > n - dc + ic
      js_delete(o, (k - 1).to_s, true)
      k -= 1
  elsif ic > dc
    k = n - dc
    while k > start
      if js_has_el?(o, k + dc - 1)
        js_put_el_set(o, k + ic - 1, js_el(o, k + dc - 1))
      else
        js_delete(o, (k + ic - 1).to_s, true)
      k -= 1
  j = 0
  while j < ic
    js_put_el_set(o, start + j, items[j])
    j += 1
  js_set_len(o, n - dc + ic)
  removed

-> js_arr_concat(this, args)
  r = JS_REALM[0]
  o = js_to_object(this)
  out = []
  all = [o] + args
  all.each ->(x)
    if js_spreadable?(x)
      if js_dense?(x)
        x.elems.each ->(e) out.push(e)
      else
        n = js_len_of(x)
        k = 0
        while k < n
          out.push(js_has_el?(x, k) ? js_el(x, k) : JS_HOLE)
          k += 1
    else
      out.push(x)
  r.new_array(out)

-> js_spreadable?(x)
  return false if !x.is_a?(JsObject)
  s = x.get(SYM_IS_CONCAT_SPREADABLE, x)
  return js_to_boolean(s) if s != nil
  js_is_array(x)

-> js_arr_reverse(this)
  o = js_to_object(this)
  if js_dense?(o)
    el = o.elems
    i = 0
    j = el.size - 1
    while i < j
      t = el[i]
      el[i] = el[j]
      el[j] = t
      i += 1
      j -= 1
    return o
  n = js_len_of(o)
  lo = 0
  hi = n - 1
  while lo < hi
    # HasProperty then Get, lower before upper (§23.1.3.26): a getter may change the array
    le = js_has_el?(o, lo)
    lv = le ? js_el(o, lo) : nil
    he = js_has_el?(o, hi)
    hv = he ? js_el(o, hi) : nil
    if he
      js_put_el_set(o, lo, hv)
    else
      js_delete(o, lo.to_s, true)
    if le
      js_put_el_set(o, hi, lv)
    else
      js_delete(o, hi.to_s, true)
    lo += 1
    hi -= 1
  o

-> js_arr_fill(this, args)
  o = js_to_object(this)
  n = js_len_of(o)
  v = js_arg(args, 0)
  a = js_rel_index(js_arg(args, 1), n, 0)
  b = js_rel_index(js_arg(args, 2), n, n)
  k = a
  while k < b
    js_put_el_set(o, k, v)
    k += 1
  o

-> js_arr_copy_within(this, args)
  o = js_to_object(this)
  n = js_len_of(o)
  to = js_rel_index(js_arg(args, 0), n, 0)
  from = js_rel_index(js_arg(args, 1), n, 0)
  fin = js_rel_index(js_arg(args, 2), n, n)
  count = fin - from
  count = n - to if n - to < count
  return o if count <= 0
  vals = []
  k = 0
  while k < count
    vals.push(js_has_el?(o, from + k) ? js_el(o, from + k) : JS_HOLE)
    k += 1
  k = 0
  while k < count
    if vals[k] == JS_HOLE
      js_delete(o, (to + k).to_s, true)
    else
      js_put_el_set(o, to + k, vals[k])
    k += 1
  o

# Stable merge sort with a JS comparator; undefined last, holes dropped (then re-added as holes).
-> js_sort_values(vals, cmp)
  defined = []
  undef = 0
  vals.each ->(v)
    if v == nil
      undef += 1
    else
      defined.push(v)
  sorted = js_merge_sort(defined, cmp)
  while undef > 0
    sorted.push(nil)
    undef -= 1
  sorted

-> js_sort_cmp(a, b, cmp)
  if cmp == nil
    return js_str_cmp(a, b) if a.is_a?(String) && b.is_a?(String)
    if a.is_a?(Float) && b.is_a?(Float) && js_int_like?(a) && js_int_like?(b) && a >= ~0.0 && b >= ~0.0 && js_digits_eq(a, b)
      return a < b ? -1 : (a > b ? 1 : 0)
    sa = js_to_string(a)
    sb = js_to_string(b)
    return js_str_cmp(sa, sb)
  v = js_to_number(js_call(cmp, nil, [a, b]))
  return 0 if v != v
  v < ~0.0 ? -1 : (v > ~0.0 ? 1 : 0)

-> js_int_like?(x)
  x == Math.floor(x) && x < ~1.0e15

# Same number of decimal digits: then numeric order equals string order.
-> js_digits_eq(a, b)
  js_ndigits(a) == js_ndigits(b)

-> js_ndigits(x)
  n = 1
  t = ~10.0
  while x >= t
    n += 1
    t = t * ~10.0
  n

-> js_merge_sort(a, cmp)
  n = a.size
  return a if n < 2
  if n <= 10
    # insertion sort for short runs
    out = a.map(->(x) x)
    i = 1
    while i < n
      x = out[i]
      j = i - 1
      while j >= 0 && js_sort_cmp(out[j], x, cmp) > 0
        out[j + 1] = out[j]
        j -= 1
      out[j + 1] = x
      i += 1
    return out
  mid = n / 2
  l = js_merge_sort(a.slice(0, mid), cmp)
  rr = js_merge_sort(a.slice(mid, n - mid), cmp)
  out = Array.new(n, nil)
  i = 0
  j = 0
  k = 0
  while i < l.size && j < rr.size
    if js_sort_cmp(rr[j], l[i], cmp) < 0
      out[k] = rr[j]
      j += 1
    else
      out[k] = l[i]
      i += 1
    k += 1
  while i < l.size
    out[k] = l[i]
    i += 1
    k += 1
  while j < rr.size
    out[k] = rr[j]
    j += 1
    k += 1
  out

-> js_arr_sort(this, cmp)
  js_throw_type("The comparison function must be either a function or undefined") if cmp != nil && !(cmp.is_a?(JsObject) && cmp.callable?)
  o = js_to_object(this)
  n = js_len_of(o)
  vals = []
  holes = 0
  k = 0
  while k < n
    if js_has_el?(o, k)
      vals.push(js_el(o, k))
    else
      holes += 1
    k += 1
  sorted = js_sort_values(vals, cmp)
  k = 0
  while k < sorted.size
    js_put_el_set(o, k, sorted[k])
    k += 1
  while k < n
    js_delete(o, k.to_s, true)
    k += 1
  o

-> js_arr_flat_into(out, o, depth)
  n = js_len_of(o)
  k = 0
  while k < n
    if js_has_el?(o, k)
      v = js_el(o, k)
      if depth > 0 && js_is_array(v)
        js_arr_flat_into(out, v, depth - 1)
      else
        out.push(v)
    k += 1
  out

-> js_arr_flat(this, d)
  o = js_to_object(this)
  depth = d == nil ? 1 : js_to_integer(d)
  depth = 0 if depth < ~0.0
  dd = depth > ~1000000.0 ? 1000000 : depth.to_i
  JS_REALM[0].new_array(js_arr_flat_into([], o, dd))

-> js_arr_flat_map(this, args)
  o = js_to_object(this)
  f = js_fn_arg(args, 0, "flatMap")
  t = js_arg(args, 1)
  n = js_len_of(o)
  out = []
  k = 0
  while k < n
    if js_has_el?(o, k)
      v = js_call(f, t, [js_el(o, k), k + ~0.0, o])
      if js_is_array(v)
        js_arr_flat_into(out, v, 0)
      else
        out.push(v)
    k += 1
  JS_REALM[0].new_array(out)

-> js_arr_values_list(o)
  n = js_len_of(o)
  out = Array.new(n, nil)
  k = 0
  while k < n
    out[k] = js_el(o, k)
    k += 1
  out

-> js_arr_with(this, idx, v)
  o = js_to_object(this)
  n = js_len_of(o)
  i = js_to_integer(idx)
  i = i + n if i < ~0.0
  raise JsThrow.new(js_range_error("Invalid index : " + js_number_to_s(js_to_integer(idx)))) if i < ~0.0 || i >= n + ~0.0
  vals = js_arr_values_list(o)
  vals[i.to_i] = v
  JS_REALM[0].new_array(vals)

-> js_arr_to_spliced(this, args)
  o = js_to_object(this)
  vals = js_arr_values_list(o)
  tmp = JS_REALM[0].new_array(vals)
  js_arr_splice(tmp, args)
  tmp

-> js_arr_at(this, idx)
  o = js_to_object(this)
  n = js_len_of(o)
  i = js_to_integer(idx)
  i = i + n if i < ~0.0
  return nil if i < ~0.0 || i >= n + ~0.0
  js_el(o, i.to_i)

js_install(->(r) js_install_array(r))

-> js_install_array(r)
  op = r.object_proto
  ap = JsArray.new(op, [])
  r.array_proto = ap
  ac = r.constructor("Array", 1, ->(this, args, nt) js_array_ctor(args, nt), ap)
  r.method(ac, "isArray", 1, ->(this, args, nt) js_is_array(js_arg(args, 0)))
  r.method(ac, "of", 0, ->(this, args, nt) js_array_of(this, args))
  r.method(ac, "from", 1, ->(this, args, nt) js_array_from(this, js_arg(args, 0), js_arg(args, 1), js_arg(args, 2)))
  r.getter(ac, SYM_SPECIES, ->(this, args, nt) this)
  r.method(ap, "at", 1, ->(this, args, nt) js_arr_at(this, js_arg(args, 0)))
  r.method(ap, "concat", 1, ->(this, args, nt) js_arr_concat(this, args))
  r.method(ap, "copyWithin", 2, ->(this, args, nt) js_arr_copy_within(this, args))
  r.method(ap, "every", 1, ->(this, args, nt) js_arr_each(this, args, :every))
  r.method(ap, "some", 1, ->(this, args, nt) js_arr_each(this, args, :some))
  r.method(ap, "forEach", 1, ->(this, args, nt) js_arr_each(this, args, :each))
  r.method(ap, "map", 1, ->(this, args, nt) js_arr_each(this, args, :map))
  r.method(ap, "filter", 1, ->(this, args, nt) js_arr_each(this, args, :filter))
  r.method(ap, "fill", 1, ->(this, args, nt) js_arr_fill(this, args))
  r.method(ap, "find", 1, ->(this, args, nt) js_arr_find(this, args, false, false))
  r.method(ap, "findIndex", 1, ->(this, args, nt) js_arr_find(this, args, false, true))
  r.method(ap, "findLast", 1, ->(this, args, nt) js_arr_find(this, args, true, false))
  r.method(ap, "findLastIndex", 1, ->(this, args, nt) js_arr_find(this, args, true, true))
  r.method(ap, "flat", 0, ->(this, args, nt) js_arr_flat(this, js_arg(args, 0)))
  r.method(ap, "flatMap", 1, ->(this, args, nt) js_arr_flat_map(this, args))
  r.method(ap, "includes", 1, ->(this, args, nt) js_arr_includes(this, args))
  r.method(ap, "indexOf", 1, ->(this, args, nt) js_arr_index_of(this, args, false))
  r.method(ap, "lastIndexOf", 1, ->(this, args, nt) js_arr_index_of(this, args, true))
  r.method(ap, "join", 1, ->(this, args, nt) js_arr_join(this, js_arg(args, 0)))
  r.method(ap, "pop", 0, ->(this, args, nt) js_arr_pop(this))
  r.method(ap, "push", 1, ->(this, args, nt) js_arr_push(this, args))
  r.method(ap, "reduce", 1, ->(this, args, nt) js_arr_reduce(this, args, false))
  r.method(ap, "reduceRight", 1, ->(this, args, nt) js_arr_reduce(this, args, true))
  r.method(ap, "reverse", 0, ->(this, args, nt) js_arr_reverse(this))
  r.method(ap, "shift", 0, ->(this, args, nt) js_arr_shift(this))
  r.method(ap, "unshift", 1, ->(this, args, nt) js_arr_unshift(this, args))
  r.method(ap, "slice", 2, ->(this, args, nt) js_arr_slice(this, args))
  r.method(ap, "sort", 1, ->(this, args, nt) js_arr_sort(this, js_arg(args, 0)))
  r.method(ap, "splice", 2, ->(this, args, nt) js_arr_splice(this, args))
  r.method(ap, "toLocaleString", 0, ->(this, args, nt) js_arr_join(this, ","))
  r.method(ap, "toString", 0, ->(this, args, nt) js_arr_to_string(this))
  r.method(ap, "toReversed", 0, ->(this, args, nt) js_arr_reverse(r.new_array(js_arr_values_list(js_to_object(this)))))
  r.method(ap, "toSorted", 1, ->(this, args, nt) js_arr_sort(r.new_array(js_arr_values_list(js_to_object(this))), js_arg(args, 0)))
  r.method(ap, "toSpliced", 2, ->(this, args, nt) js_arr_to_spliced(this, args))
  r.method(ap, "with", 2, ->(this, args, nt) js_arr_with(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(ap, "keys", 0, ->(this, args, nt) js_array_iter(js_to_object(this), :keys))
  r.method(ap, "entries", 0, ->(this, args, nt) js_array_iter(js_to_object(this), :entries))
  vals = r.method(ap, "values", 0, ->(this, args, nt) js_array_iter(js_to_object(this), :values))
  ap.define(SYM_ITERATOR, vals, BUILTIN_ATTRS)
  r.set_intrinsic("%ArrayProto_values%", vals)
  un = JsObject.new(JS_NULL, "Object")
  ["at", "copyWithin", "entries", "fill", "find", "findIndex", "findLast", "findLastIndex", "flat", "flatMap", "includes", "keys", "toReversed", "toSorted", "toSpliced", "values"].each ->(k) un.define(k, true)
  ap.define(SYM_UNSCOPABLES, un, ATTR_C)
  nil
