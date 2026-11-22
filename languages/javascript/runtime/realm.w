# js/realm — the runtime contract every piece of the JavaScript engine builds against.
#
# value.w defines values and the abstract operations. This file defines:
#   - JsRealm: the intrinsics (%Object.prototype%, %Array%, …) and the global object,
#     with one registration point so builtins can be written in independent files;
#   - helpers to define native functions, methods, getters and constants with the
#     attributes the spec gives builtins (writable+configurable, not enumerable);
#   - the iteration protocol (GetIterator / IteratorStep / IteratorClose);
#   - the job queue (Promise reactions run as microtasks) and host hooks (timers,
#     the console, the DOM) that the embedder (Blade) provides.
#
# Native function signature: ->(this, args, new_target) → value. args is a Tungsten
# Array of JS values (missing arguments read as nil, i.e. undefined, via js_arg).
# new_target is nil for [[Call]] and the constructor for [[Construct]].

-> js_arg(args, i)
  i < args.size ? args[i] : nil

BUILTIN_ATTRS = ATTR_W + ATTR_C

+ JsRealm
  rw :global, :intrinsics, :jobs, :host, :symbol_registry, :template_cache, :glex, :array_proto, :array_proto_indexed, :modules, :join_guard

  -> new
    @glex = {}
    @array_proto = nil
    @array_proto_indexed = false
    @modules = {}
    @join_guard = []
    @intrinsics = {}
    @jobs = []
    @host = nil
    @symbol_registry = {}
    @template_cache = {}
    op = JsObject.new(JS_NULL, "Object")
    @intrinsics["Object.prototype"] = op
    fp = JsFunction.new(op, ->(this, args, nt) nil, "", 0, false)
    @intrinsics["Function.prototype"] = fp
    @global = JsObject.new(op, "global")
    JS_REALM[0] = self
    # every builtin file registers an installer; they run in registration order
    JS_INSTALLERS.each ->(inst) inst.call(self)
    @array_proto = @intrinsics["Array.prototype"]
    @global.define("globalThis", @global, BUILTIN_ATTRS)

  # The cell for a script-scope let/const/class (shared by all scripts in the realm).
  -> glex_cell(name, is_const)
    c = @glex[name]
    if c == nil
      c = JsCell.new(name, JS_TDZ, is_const)
      @glex[name] = c
    c

  # Is iteration of plain arrays still the built-in one (no user override)?
  -> array_iter_pristine?
    ap = @array_proto
    v = @intrinsics["%ArrayProto_values%"]
    return false if ap.props[SYM_ITERATOR] != v
    aip = @intrinsics["%ArrayIteratorPrototype%"]
    aip.props["next"] == @intrinsics["%ArrayIteratorProto_next%"]

  -> string_iter_pristine?
    sp = @intrinsics["String.prototype"]
    sp.props[SYM_ITERATOR] == @intrinsics["%StringProto_iterator%"] && @intrinsics["%StringIteratorPrototype%"].props["next"] == @intrinsics["%StringIteratorProto_next%"]

  -> intrinsic(name)
    v = @intrinsics[name]
    raise "js: missing intrinsic " + name if v == nil
    v

  -> intrinsic?(name)
    @intrinsics.has_key?(name)

  -> set_intrinsic(name, v)
    @intrinsics[name] = v

  # The prototype an error of this kind gets (TypeError, RangeError, …).
  -> proto_of(kind)
    p = @intrinsics[kind + ".prototype"]
    p == nil ? @intrinsics["Error.prototype"] : p

  -> object_proto
    @intrinsics["Object.prototype"]

  -> function_proto
    @intrinsics["Function.prototype"]

  # A new ordinary object inheriting from %Object.prototype%.
  -> new_object
    JsObject.new(object_proto(), "Object")

  # (copied: a Tungsten slice is a borrowed view that cannot grow)
  -> new_array(elems = [])
    JsArray.new(@array_proto, elems.dup)

  # ToObject for primitives: Number/String/Boolean/Symbol/BigInt wrappers.
  -> wrap_primitive(v)
    kind = v.is_a?(Float) ? "Number" : (v.is_a?(String) ? "String" : ((v == true || v == false) ? "Boolean" : (v.is_a?(JsSymbol) ? "Symbol" : "BigInt")))
    return js_string_object(intrinsic("String.prototype"), v) if v.is_a?(String)
    o = JsObject.new(intrinsic(kind + ".prototype"), kind)
    o.internal = v
    o

  # ---- defining builtins ----

  -> native(name, arity, fun, ctor = false)
    fun = js_trace_native_wrap(name, fun) if JS_TRACE_NATIVE[0] != nil
    JsFunction.new(function_proto(), fun, name, arity, ctor)

  -> method(obj, name, arity, fun)
    f = native(name.is_a?(JsSymbol) ? "\[" + name.description + "]" : name, arity, fun)
    obj.define(name, f, BUILTIN_ATTRS)
    f

  -> getter(obj, name, fun, setter = nil)
    g = native("get " + (name.is_a?(JsSymbol) ? "\[" + name.description + "]" : name), 0, fun)
    s = setter == nil ? nil : native("set " + name.to_s, 1, setter)
    obj.define_accessor(name, g, s, ATTR_C)
    g

  -> constant(obj, name, v)
    obj.define(name, v, 0)

  # A constructor with its prototype object linked both ways; installed on the global.
  -> constructor(name, arity, fun, proto = nil, parent_proto = nil)
    proto = JsObject.new(parent_proto == nil ? object_proto() : parent_proto, name) if proto == nil
    c = native(name, arity, fun, true)
    c.define("prototype", proto, 0)
    proto.define("constructor", c, BUILTIN_ATTRS)
    @intrinsics[name] = c
    @intrinsics[name + ".prototype"] = proto
    @global.define(name, c, BUILTIN_ATTRS)
    c

  # OrdinaryCreateFromConstructor: the prototype a constructor call should use.
  -> proto_from(new_target, fallback_name)
    if new_target != nil
      p = new_target.get("prototype")
      return p if p.is_a?(JsObject)
    intrinsic(fallback_name + ".prototype")

  # ---- jobs (microtasks) ----

  -> enqueue_job(job)
    @jobs.push(job)

  # Run queued jobs until none remain (HTML's "perform a microtask checkpoint").
  -> run_jobs
    # every job starts at the depth of the checkpoint (a job that threw cannot leak depth)
    d = JS_DEPTH[0]
    while @jobs.size > 0
      j = @jobs.shift
      JS_DEPTH[0] = d
      j.call()
    JS_DEPTH[0] = d
    nil

  # ---- symbols ----

  -> symbol_for(key)
    s = @symbol_registry[key]
    if s == nil
      s = JsSymbol.new(key)
      @symbol_registry[key] = s
    s


# Builtin installers: each builtins file appends ->(realm) to this at load time.
JS_INSTALLERS = []

-> js_install(f)
  JS_INSTALLERS.push(f)


# ---- the iteration protocol (§7.4) ----

+ JsIterRecord
  rw :iterator, :next_fn, :done
  -> new(@iterator, @next_fn)
    @done = false

-> js_get_iterator(v, async_kind = false)
  m = nil
  if async_kind
    m = js_get_method(v, SYM_ASYNC_ITERATOR)
  m = js_get_method(v, SYM_ITERATOR) if m == nil
  js_throw_type(js_to_display(v) + " is not iterable") if m == nil
  it = js_call(m, v, JS_NO_ARGS)
  js_throw_type("Result of the Symbol.iterator method is not an object") if !it.is_a?(JsObject)
  JsIterRecord.new(it, it.get("next"))

# GetMethod: nil when undefined or null.
-> js_get_method(v, key)
  o = v.is_a?(JsObject) ? v : js_to_object(v)
  f = o.get(key, v)
  return nil if js_nullish?(f)
  js_throw_type(js_key_display(key) + " is not a function") if !f.is_a?(JsFunction)
  f

# The next value, or JS_ITER_DONE.
+ JsIterDone
  -> new
JS_ITER_DONE = JsIterDone.new

-> js_iter_step(rec)
  r = js_call(rec.next_fn, rec.iterator, JS_NO_ARGS)
  js_throw_type("Iterator result is not an object") if !r.is_a?(JsObject)
  if js_to_boolean(r.get("done"))
    rec.done = true
    return JS_ITER_DONE
  r.get("value")

-> js_iter_close(rec)
  return nil if rec.done
  rec.done = true
  ret = js_get_method(rec.iterator, "return")
  js_call(ret, rec.iterator, JS_NO_ARGS) if ret != nil
  nil

# Iterate a JS iterable with a Tungsten block; the iterator is closed if the block raises.
-> js_for_of(v, f)
  # fast path: plain arrays whose iterator is the intrinsic one
  if v.is_a?(JsArray) && JS_REALM[0] != nil && v.get(SYM_ITERATOR) == JS_REALM[0].intrinsic("%ArrayProto_values%")
    i = 0
    while i < v.length
      f.call(js_arr_elem(v, i))
      i += 1
    return nil
  rec = js_get_iterator(v)
  begin
    while true
      x = js_iter_step(rec)
      break if x == JS_ITER_DONE
      f.call(x)
  rescue e
    js_iter_close(rec) if !rec.done
    raise e
  nil

-> js_iter_result(value, done)
  o = JS_REALM[0].new_object
  o.put_own("value", value)
  o.put_own("done", done)
  o

# A JS array (JsArray) → Tungsten Array of values (holes as undefined); other iterables via the protocol.
-> js_to_list(v)
  out = []
  js_for_of(v, ->(x) out.push(x))
  out


# ---- host hooks: what the embedder provides ----

# A JsHost tells the engine how to reach the outside world. Blade subclasses it.
+ JsHost
  # Print for console.log/info/warn/error/debug.
  -> console(level, text)
    << "\[js " + level + "] " + text

  # setTimeout/setInterval: schedule f after ms; returns an id.
  -> set_timer(f, ms, repeat)
    0

  -> clear_timer(id)
    nil

  # The current time for Date.now / performance.now (ms).
  -> now_ms
    Instant.now.unix_ms + ~0.0

  -> perf_now
    clock_ms() + ~0.0

# Debugging aid (BLADE_JS_TRACE=native): log every native function (builtin or host API) a
# script calls: the caller's column, the function, its receiver and arguments, and the
# result (stderr). Which script: BLADE_JS_TRACE_URL=<part of its URL>; without it, script
# that has no URL (new Function code, or what a URL-less script evals: how YouTube's
# BotGuard VM arrives, and how its read of a null <iframe>.contentWindow was found).
# The builtins a bytecode loop calls per step are left out; BLADE_JS_TRACE=native-all logs
# those too. Receivers and arguments are shown without reading any property.
JS_TRACE_NATIVE = [Env.get("BLADE_JS_TRACE", "") == "native" ? :quiet : (Env.get("BLADE_JS_TRACE", "") == "native-all" ? :all : nil)]
JS_TRACE_NATIVE_BUSY = [false]
JS_TRACE_NATIVE_SKIP = {"charCodeAt" => true, "push" => true, "pop" => true, "fromCharCode" => true, "join" => true, "toString" => true, "valueOf" => true, "slice" => true, "create" => true, "call" => true, "random" => true, "floor" => true, "now" => true, "Number" => true, "" => true}

-> js_trace_show(v)
  if v.is_a?(String)
    return "\"" + (v.size > 160 ? v.slice(0, 160) + "...(" + v.size.to_s + ")" : v) + "\""
  if v.is_a?(JsArray)
    parts = []
    i = 0
    while i < v.elems.size && i < 6
      e = v.elems[i]
      parts.push(e.is_a?(String) ? "\"" + e.slice(0, 40) + "\"" : js_to_display(e))
      i += 1
    return "\[" + parts.join(", ") + (v.elems.size > 6 ? ", ..." + v.elems.size.to_s : "") + "]"
  js_to_display(v)

-> js_trace_native_wrap(name, fun)
  return fun if JS_TRACE_NATIVE[0] == :quiet && JS_TRACE_NATIVE_SKIP[name.to_s] == true
  ->(this, args, nt) js_trace_native_call(name, fun, [this, args, nt])

JS_TRACE_NATIVE_URL = [Env.get("BLADE_JS_TRACE_URL", "")]

# Is the running script the one being traced? (Checked before anything is formatted: the
# line and column of a caller in a large script cost a pass over its source.)
-> js_trace_native_from?
  k = JS_DEPTH[0]
  u = JS_TOP[1]
  u = JS_STACK[k].url if k > 0 && k < 1000 && JS_STACK[k] != nil
  f = JS_TRACE_NATIVE_URL[0]
  return u == nil || u == "" if f.size == 0
  u != nil && u.index(f) != nil

-> js_trace_native_call(name, fun, c)
  return fun.call(c[0], c[1], c[2]) if JS_TRACE_NATIVE_BUSY[0] || !js_trace_native_from?()
  loc = js_top_location()
  JS_TRACE_NATIVE_BUSY[0] = true
  head = "\[js native] @" + loc[2].to_s + " " + js_trace_show(c[0]) + " . " + name.to_s + "(" + c[1].map(->(a) js_trace_show(a)).join(", ") + ")"
  JS_TRACE_NATIVE_BUSY[0] = false
  res = nil
  begin
    res = fun.call(c[0], c[1], c[2])
  rescue e
    ccall("w_eputs", head + " !! threw")
    raise e
  ccall("w_eputs", head + " => " + js_trace_show(res))
  res
