# runtime/realm — the realm (intrinsics and the global object), generic property access,
# errors, and the builtins the compiled programs need so far.
#
# The global object keeps its properties in JS:GlobalCell records, one per name, so a
# compiled global read or write is one cell load or store: a site resolves its cell once
# (js_gcell) and keeps it. A cell holding JS_HOLE is an absent property.

in JS

+ Realm
  rw :global, :intrinsics, :jobs, :host, :symbol_registry, :template_cache, :modules, :object_proto, :function_proto, :array_proto, :string_proto, :number_proto, :boolean_proto, :error_proto, :symbol_proto, :fn_shape, :native_shape, :errors, :kind_shapes, :promise_shape, :promise_proto, :promise_ctor, :promise_then_fn, :promise_resolve_fn, :promise_species_acc, :regexp_shape, :regexp_proto, :regexp_exec_fn, :rx_match_shape, :rx_ctor, :rx_last_input, :rx_last_match, :rx_last_paren, :rx_left_ctx, :rx_right_ctx, :rx_parens, :rx_leg_s, :rx_leg_ng, :rx_leg_caps, :lexical, :global_vars, :unhandled, :analyses, :jit_keep

  -> new
    @kind_shapes = {}
    @global = nil
    @intrinsics = {}
    @jobs = JS:JobQueue.new
    @host = nil
    @symbol_registry = {}
    @template_cache = {}
    @modules = {}
    @errors = {}
    @promise_shape = nil
    @promise_proto = nil
    @promise_ctor = nil
    @promise_then_fn = nil
    @promise_resolve_fn = nil
    @promise_species_acc = nil
    @regexp_shape = nil
    @regexp_proto = nil
    @regexp_exec_fn = nil
    @rx_match_shape = nil
    @rx_ctor = nil
    @rx_last_input = ""
    @rx_last_match = ""
    @rx_last_paren = ""
    @rx_left_ctx = ""
    @rx_right_ctx = ""
    @rx_parens = ["", "", "", "", "", "", "", "", ""]
    @rx_leg_s = nil
    @rx_leg_ng = 0
    @rx_leg_caps = i64[20]
    @lexical = {}
    @global_vars = {}
    @unhandled = []
    @analyses = []
    @jit_keep = []

  -> intrinsic(name)
    v = @intrinsics[name]
    raise "js: missing intrinsic " + name if v == nil
    v

  -> intrinsic?(name)
    @intrinsics.has_key?(name)

  -> set_intrinsic(name, v)
    @intrinsics[name] = v

  # The prototype an error of this kind gets (TypeError, RangeError, ...).
  -> proto_of(kind)
    p = @intrinsics[kind + ".prototype"]
    p == nil ? @error_proto : p

  -> new_object
    js_new_object(@object_proto)

  # A JS array taking ownership of a fresh Tungsten list (no copy).
  -> adopt_array(elems)
    js_mark_array(elems)

  -> new_array(elems = nil)
    js_mark_array(elems == nil ? [] : elems.dup)

  # ToObject for primitives: the Number/String/Boolean/Symbol/BigInt wrappers.
  -> wrap_primitive(v)
    kind = js_number?(v) ? "Number" : (js_string?(v) ? "String" : ((v == true || v == false) ? "Boolean" : (v.is_a?(JS:Symbol) ? "Symbol" : "BigInt")))
    return js_string_object(intrinsic("String.prototype"), v) if js_string?(v)
    o = js_new_special(intrinsic(kind + ".prototype"), kind)
    o.internal = v
    o

  # ---- defining builtins (writable + configurable, not enumerable) ----

  -> native(name, arity, fun, ctor = false)
    f = js_native(name, arity, fun)
    f.set_ctor if ctor
    f

  -> method(obj, name, arity, fun)
    f = native(name.is_a?(JS:Symbol) ? "\[" + name.description + "]" : name, arity, fun)
    jdefine(obj, name, f, BUILTIN_ATTRS)
    f

  -> getter(obj, name, fun, setter = nil)
    dname = name.is_a?(JS:Symbol) ? "\[" + name.description + "]" : name
    g = native("get " + dname, 0, fun)
    st = setter == nil ? nil : native("set " + dname, 1, setter)
    obj.define_accessor(name, g, st, ATTR_C)
    g

  -> constant(obj, name, v)
    jdefine(obj, name, v, 0)

  # A constructor with its prototype object linked both ways; installed on the global.
  -> constructor(name, arity, fun, proto = nil, parent_proto = nil)
    proto = js_new_special(parent_proto == nil ? @object_proto : parent_proto, name) if proto == nil
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
      p = jget(new_target, "prototype")
      return p if js_object?(p)
      fr = js_get_function_realm(new_target)
      return fr.intrinsic(fallback_name + ".prototype")
    intrinsic(fallback_name + ".prototype")

  # ---- jobs (microtasks) ----

  -> enqueue_job(job, keep = nil)
    @jobs.push(job)
    nil

  # A frame's realm shares its parent's queue (one microtask queue per agent).
  -> share_jobs(parent)
    @jobs.transfer_to(parent.jobs)
    @jobs = parent.jobs
    nil

  # Run queued jobs until none remain (HTML's "perform a microtask checkpoint").
  # Uses a zero-closure flat ring buffer and outer begin/rescue (ZERO per-microtask setjmp!).
  -> run_jobs
    q = @jobs
    top = JS_CUR_ACT[0]
    while q.head != q.tail
      cur_kind = 0
      cur_a = nil
      begin
        while q.head != q.tail
          h = q.head
          k = q.kinds[h]
          fl = q.flags[h]
          a = q.qa[h]
          b = q.qb[h]
          c = q.qc[h]
          q.qa[h] = nil
          q.qb[h] = nil
          q.qc[h] = nil
          q.head = (h + 1) & q.mask
          if k == JOB_RX_PROM
            cur_kind = 1
            cur_a = a
            if fl == 0 && b.is_a?(JS:Function) && q.head == q.tail && !JS_MULTI_REALM[0]
              # Pure-LLVM tight drain for consecutive same-handler JITted Promise chains!
              cd = b.code
              fp = cd.jit_fp
              if fp == 0 && cd.jit_state == 0
                hc = cd.jit_hits + 1
                cd.jit_hits = hc
                if hc >= WK_JIT_FN_THRESH
                  jit_compile_and_install(cd)
                  fp = cd.jit_fp
              if fp != 0
                js_prom_offs_init(q) if JS_PROM_OFFS[0] == 0
                if JS_PROM_OFFS[0] > 0 && JS_PROM_OFFS[7] > 0
                  cur_kind = 4
                  offs_p = jit_arr_slots_ptr(wvalue_bits(JS_PROM_OFFS) ## i64)
                  out_p = jit_arr_slots_ptr(wvalue_bits(JS_PROM_DRAIN_OUT) ## i64)
                  rc = js_drain_prom_chain_ll(wvalue_bits(a) ## i64, fp ## i64, wvalue_bits(b) ## i64, wvalue_bits(c) ## i64, wvalue_bits(:pending) ## i64, wvalue_bits(:fulfilled) ## i64, wvalue_bits(q) ## i64, offs_p, out_p)
                  cur_kind = 1
                  if rc == 1
                    nt = wvalue_from_bits(jb_ld_i64(out_p + 8))
                    nh = wvalue_from_bits(jb_ld_i64(out_p + 16))
                    lres = wvalue_from_bits(jb_ld_i64(out_p + 24))
                    q.push_rx_prom(nt, nh, lres, 0)
                  elsif rc == 2
                    ct = wvalue_from_bits(jb_ld_i64(out_p))
                    lres = wvalue_from_bits(jb_ld_i64(out_p + 24))
                    cur_a = ct
                    if js_object?(lres)
                      js_promise_resolve_with(ct, lres)
                    else
                      js_promise_fulfill_fast(ct, lres, q)
                  elsif rc == 3
                    ct = wvalue_from_bits(jb_ld_i64(out_p))
                    cv = wvalue_from_bits(jb_ld_i64(out_p + 24))
                    cur_a = ct
                    res = wk_call_tier0(b, nil, 1, cv, nil, nil, nil, nil)
                    if ct != nil
                      if js_object?(res)
                        js_promise_resolve_with(ct, res)
                      else
                        js_promise_fulfill_fast(ct, res, q)
                else
                  js_run_prom_rx_inline(a, b, c, fl, q)
              else
                js_run_prom_rx_inline(a, b, c, fl, q)
            else
              js_run_prom_rx_inline(a, b, c, fl, q)
            cur_kind = 0
            cur_a = nil
          elsif k == JOB_ASYNC
            cur_kind = 3
            cur_a = a
            js_sm_async_resume(a, b, fl, q)
            cur_kind = 0
            cur_a = nil
          elsif k == JOB_ALL_SETTLE
            cur_kind = 0
            cur_a = nil
            js_prom_all_settle(a, fl >> 1, b, fl & 1, q)
          elsif k == JOB_ASYNC_CHAIN
            cur_kind = 1
            cur_a = a
            js_prom_async_chain_step(a, b, c, fl, q)
            cur_kind = 0
            cur_a = nil
          elsif k == JOB_ASYNC_PIPE
            if fl == 3
              collapsed = false
              if !JS_MULTI_REALM[0] && js_promise_pristine?(self) && a.is_a?(JS:Promise) && a.state == :pending && a.rx_kind == 5
                st = a.rx_target
                if st.is_a?(JS:PromiseAllState) && !st.settled && st.rem > 0 && q.size == st.rem - 1
                  fn2 = b.value
                  if fn2.is_a?(JS:Function) && fn2.code != nil && fn2.code.sm_code != nil
                    sc2 = fn2.code.sm_code
                    if sc2.fast_kind == 1 && sc2.fast_pure && sc2.fast_b.value == @promise_ctor && sc2.fast_a.jit_fp != 0
                      js_prom_offs_init(q) if JS_PROM_OFFS[0] == 0
                      if JS_PROM_OFFS[0] > 0 && JS_PROM_OFFS[5] > 0
                        pa = JS_PIPE_ARGS
                        pa[0] = wvalue_bits(a) ## i64
                        pa[1] = wvalue_bits(c) ## i64
                        pa[2] = wvalue_bits(st) ## i64
                        pa[3] = wvalue_bits(b) ## i64
                        pa[4] = sc2.fast_a.jit_fp ## i64
                        pa[5] = wvalue_bits(fn2) ## i64
                        pa[6] = wvalue_bits(:pending) ## i64
                        pa[7] = wvalue_bits(:fulfilled) ## i64
                        pa[8] = jit_arr_slots_ptr(wvalue_bits(st.values) ## i64)
                        pa[9] = jit_i64_ptr(JS_PROM_OFFS)
                        pa[10] = jit_i64_ptr(q.kinds)
                        pa[11] = jit_i64_ptr(q.flags)
                        pa[12] = jit_arr_slots_ptr(wvalue_bits(q.qa) ## i64)
                        pa[13] = jit_arr_slots_ptr(wvalue_bits(q.qb) ## i64)
                        pa[14] = jit_arr_slots_ptr(wvalue_bits(q.qc) ## i64)
                        pa[15] = q.head ## i64
                        pa[16] = q.mask ## i64
                        pa[17] = st.rem ## i64
                        pa[18] = wvalue_bits(5) ## i64
                        pa[19] = wvalue_bits(0) ## i64
                        if js_drain_async_pipe_all_ll(jit_i64_ptr(pa)) == 1
                          q.head = q.tail
                          st.rem = 0
                          st.settled = true
                          js_promise_fulfill_fast(st.target, adopt_array(st.values), q)
                          collapsed = true
              if !collapsed
                q.push_async_pipe(a, b, c, 2)
            else
              cur_kind = 1
              cur_a = a
              js_prom_async_chain_step(a, b.value, c, 0, q)
              cur_kind = 0
              cur_a = nil
          elsif k == JOB_LAMBDA
            cur_kind = 0
            cur_a = nil
            a.call()
          elsif k == JOB_RX_CAP
            cur_kind = 2
            cur_a = a
            js_reaction_job_inline(a, b)
            cur_kind = 0
            cur_a = nil
          elsif k == JOB_ADOPT
            cur_kind = 0
            cur_a = nil
            js_promise_adopt(a, b)
          else
            cur_kind = 0
            cur_a = nil
            js_thenable_job(a, b, c)
      rescue e
        JS_CUR_ACT[0] = top
        if cur_kind == 4
          out_p = jit_arr_slots_ptr(wvalue_bits(JS_PROM_DRAIN_OUT) ## i64)
          ct = wvalue_from_bits(jb_ld_i64(out_p))
          js_promise_reject(ct, js_error_value(e)) if ct != nil
        elsif cur_kind == 1 && cur_a != nil
          js_promise_reject(cur_a, js_error_value(e))
        elsif cur_kind == 2 && cur_a != nil && cur_a.cap != nil
          js_cap_reject(cur_a.cap, js_error_value(e))
        elsif cur_kind == 3 && cur_a != nil
          js_sm_async_reject(cur_a, js_error_value(e))
        else
          js_report_uncaught(e)
      JS_CUR_ACT[0] = top
    nil

  # ---- symbols ----

  -> symbol_for(key)
    sy = @symbol_registry[key]
    if sy == nil
      sy = JS:Symbol.new(key)
      @symbol_registry[key] = sy
    sy

JOB_LAMBDA      = 0
JOB_RX_PROM     = 1
JOB_RX_CAP      = 2
JOB_ASYNC       = 3
JOB_ADOPT       = 4
JOB_THENABLE    = 5
JOB_ALL_SETTLE  = 6
JOB_ASYNC_CHAIN = 7
JOB_ASYNC_PIPE  = 8

# Flat power-of-2 ring-buffer microtask queue (ZERO closure allocations per microtask!).
+ JobQueue
  rw :kinds, :flags, :qa, :qb, :qc, :head, :tail, :cap, :mask
  -> new
    @cap = 256
    @mask = 255
    @kinds = i64[256]
    @flags = i64[256]
    @qa = Array.new(256, nil)
    @qb = Array.new(256, nil)
    @qc = Array.new(256, nil)
    @head = 0
    @tail = 0

  -> grow
    nc = @cap * 2
    nk = i64[nc]
    nf = i64[nc]
    na = Array.new(nc, nil)
    nb = Array.new(nc, nil)
    nc_arr = Array.new(nc, nil)
    i = 0
    h = @head
    while h != @tail
      nk[i] = @kinds[h]
      nf[i] = @flags[h]
      na[i] = @qa[h]
      nb[i] = @qb[h]
      nc_arr[i] = @qc[h]
      i += 1
      h = (h + 1) & @mask
    @kinds = nk
    @flags = nf
    @qa = na
    @qb = nb
    @qc = nc_arr
    @head = 0
    @tail = i
    @cap = nc
    @mask = nc - 1
    nil

  -> push(j)
    nt = (@tail + 1) & @mask
    grow() if nt == @head
    t = @tail
    @kinds[t] = JOB_LAMBDA
    @flags[t] = 0
    @qa[t] = j
    @qb[t] = nil
    @qc[t] = nil
    @tail = (t + 1) & @mask
    nil

  -> push_rx_prom(target, handler, val, is_rej)
    nt = (@tail + 1) & @mask
    grow() if nt == @head
    t = @tail
    @kinds[t] = JOB_RX_PROM
    @flags[t] = is_rej
    @qa[t] = target
    @qb[t] = handler
    @qc[t] = val
    @tail = (t + 1) & @mask
    nil

  -> push_rx_cap(rx, val)
    nt = (@tail + 1) & @mask
    grow() if nt == @head
    t = @tail
    @kinds[t] = JOB_RX_CAP
    @flags[t] = 0
    @qa[t] = rx
    @qb[t] = val
    @qc[t] = nil
    @tail = (t + 1) & @mask
    nil

  -> push_async(frame, val, is_throw)
    nt = (@tail + 1) & @mask
    grow() if nt == @head
    t = @tail
    @kinds[t] = JOB_ASYNC
    @flags[t] = is_throw
    @qa[t] = frame
    @qb[t] = val
    @qc[t] = nil
    @tail = (t + 1) & @mask
    nil

  -> push_adopt(target, src)
    nt = (@tail + 1) & @mask
    grow() if nt == @head
    t = @tail
    @kinds[t] = JOB_ADOPT
    @flags[t] = 0
    @qa[t] = target
    @qb[t] = src
    @qc[t] = nil
    @tail = (t + 1) & @mask
    nil

  -> push_all_settle(st, idx, val, is_rej)
    nt = (@tail + 1) & @mask
    grow() if nt == @head
    t = @tail
    @kinds[t] = JOB_ALL_SETTLE
    @flags[t] = (idx << 1) | is_rej
    @qa[t] = st
    @qb[t] = val
    @qc[t] = nil
    @tail = (t + 1) & @mask
    nil

  -> push_async_chain(target, fn2, val, is_rej)
    nt = (@tail + 1) & @mask
    grow() if nt == @head
    t = @tail
    @kinds[t] = JOB_ASYNC_CHAIN
    @flags[t] = is_rej
    @qa[t] = target
    @qb[t] = fn2
    @qc[t] = val
    @tail = (t + 1) & @mask
    nil

  -> push_async_pipe(target, fn2_cell, val, ticks)
    nt = (@tail + 1) & @mask
    grow() if nt == @head
    t = @tail
    @kinds[t] = JOB_ASYNC_PIPE
    @flags[t] = ticks
    @qa[t] = target
    @qb[t] = fn2_cell
    @qc[t] = val
    @tail = (t + 1) & @mask
    nil

  -> push_thenable(target, x, th)
    nt = (@tail + 1) & @mask
    grow() if nt == @head
    t = @tail
    @kinds[t] = JOB_THENABLE
    @flags[t] = 0
    @qa[t] = target
    @qb[t] = x
    @qc[t] = th
    @tail = (t + 1) & @mask
    nil

  -> size
    (@tail - @head) & @mask

  -> transfer_to(dst)
    while @head != @tail
      h = @head
      k = @kinds[h]
      fl = @flags[h]
      a = @qa[h]
      b = @qb[h]
      c = @qc[h]
      @qa[h] = nil
      @qb[h] = nil
      @qc[h] = nil
      @head = (h + 1) & @mask
      nt = (dst.tail + 1) & dst.mask
      dst.grow() if nt == dst.head
      t = dst.tail
      dst.kinds[t] = k
      dst.flags[t] = fl
      dst.qa[t] = a
      dst.qb[t] = b
      dst.qc[t] = c
      dst.tail = (t + 1) & dst.mask
    nil

  -> compact
    nil

BUILTIN_ATTRS = ATTR_W + ATTR_C

# Builtin installers: each builtins file appends ->(realm) at load time; js_new_realm runs
# them in registration order.
JS_INSTALLERS = []

-> js_install(f)
  JS_INSTALLERS.push(f)
  nil

# An object with an internal slot and a class tag (Date, RegExp, Map, the primitive
# wrappers, and the embedder's host objects): JS:Base plus @cls and @internal.
+ Special < JS:Base
  rw :cls, :internal, :s0, :s1, :s2, :s3

  -> new(@shape, @cls)
    @ext = nil
    @internal = nil
    @s0 = nil
    @s1 = nil
    @s2 = nil
    @s3 = nil
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_OBJECT)

SP_IBASE = 4
SP_INLINE = 4

-> js_new_special(proto, cls)
  JS:Special.new(js_root_shape(proto, SP_INLINE, SP_IBASE), cls)

# What the embedder provides: the console, timers, the clock. Blade subclasses it.
+ Host
  -> new
    nil
  -> console(level, text)
    << text
    nil
  -> set_timer(f, ms, repeat)
    0
  -> clear_timer(id)
    nil
  -> now_ms
    Instant.now.unix_ms + ~0.0
  -> perf_now
    clock() * ~1000.0

JS_REALM = [nil]
JS_FIRST_REALM = [nil]

-> js_realm
  JS_REALM[0]

# Switch active realm (isolate) safely, invalidating cross-realm prototype pristine caches.
-> js_enter_realm(r)
  prev = [JS_REALM[0], JS_CUR_ACT[0]]
  if JS_REALM[0] != r
    JS_REALM[0] = r
    JS_EPOCH[0] = JS_EPOCH[0] + 1
  JS_CUR_ACT[0] = nil
  prev

-> js_leave_realm(prev)
  if JS_REALM[0] != prev[0]
    JS_REALM[0] = prev[0]
    JS_EPOCH[0] = JS_EPOCH[0] + 1
  JS_CUR_ACT[0] = prev[1]
  nil

# @fast holds the value while the cell is a plain writable data property, else the
# W_UNDEF bit pattern (3, never a JS value): a compiled read or write tests one word.
# Otherwise (absent, read-only, accessor) the value is in @store.
+ GlobalCell
  rw :fast, :store, :cattrs, :name
  -> new(@name)
    @fast = JS_NOTPLAIN
    @store = JS_HOLE
    @cattrs = ATTR_DEFAULT

  -> value
    jsr_is_notplain(wvalue_bits(@fast) ## i64) != 0 ? @store : @fast

  -> attrs
    @cattrs

  -> value=(v)
    put(v, @cattrs)

  -> attrs=(a)
    put(value(), a)

  -> put(v, a)
    @cattrs = a
    if v != JS_HOLE && (a & ATTR_W) != 0 && (a & ATTR_ACCESSOR) == 0
      @fast = v
      @store = JS_HOLE
    else
      @fast = JS_NOTPLAIN
      @store = v
    v

JS_NOTPLAIN = wvalue_from_bits(3)

fn jsr_is_notplain(b) (i64) i64
  b == 3 ? 1 : 0

+ GlobalObject < JS:Base
  rw :cells, :order, :cls, :internal, :priv_handlers

  # (cls, internal and priv_handlers are the host's, as on host objects: a browser's
  # global is its Window)
  -> new(@shape)
    @ext = nil
    @cells = {}
    @order = []
    @cls = "global"
    @internal = nil
    @priv_handlers = nil
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_EXOTIC)

  -> cell(key)
    c = @cells[key]
    if c == nil
      c = JS:GlobalCell.new(key)
      @cells[key] = c
    c

  -> get_own(key)
    c = @cells[key]
    return JS_HOLE if c == nil
    c.value

  -> has_own?(key)
    c = @cells[key]
    c != nil && c.value != JS_HOLE

  -> get(key, receiver = JS_HOLE)
    r = receiver == JS_HOLE ? self : receiver
    c = @cells[key]
    if c != nil && c.value != JS_HOLE
      return js_accessor_get(c.value, r) if (c.attrs & ATTR_ACCESSOR) != 0
      return c.value
    p = @shape.proto
    p == nil ? nil : p.get(key, r)

  -> set(key, v, receiver = JS_HOLE)
    r = receiver == JS_HOLE ? self : receiver
    c = @cells[key]
    if c != nil && c.value != JS_HOLE
      return js_accessor_set(c.value, r, v) if (c.attrs & ATTR_ACCESSOR) != 0
      return false if (c.attrs & ATTR_W) == 0
      return js_set_on_receiver(r, key, v) if r != self
      c.value = v
      return true
    p = @shape.proto
    while p != nil
      return p.set(key, v, r) if js_exotic_bits?(wvalue_bits(p) ## i64)
      return js_array_proto_set(p, key, v, r) if js_array?(p)
      s = p.shape
      i = s.slot_of(key)
      if i >= 0
        a = s.attrs_of(key)
        return js_accessor_set(p.slot_get(i), r, v) if (a & ATTR_ACCESSOR) != 0
        return false if (a & ATTR_W) == 0
        break
      gv = p.get_virtual(key)
      break if gv != JS_HOLE
      p = s.proto
    return js_set_on_receiver(r, key, v) if r != self
    return false if !is_extensible?
    c = cell(key)
    c.put(v, ATTR_DEFAULT)
    @order.push(key)
    true

  -> put_own(key, v)
    c = cell(key)
    @order.push(key) if c.value == JS_HOLE
    c.value = v
    v

  -> define(key, v, attrs = ATTR_DEFAULT)
    c = cell(key)
    @order.push(key) if c.value == JS_HOLE
    c.put(v, attrs)
    v

  -> delete_own(key)
    c = @cells[key]
    return true if c == nil || c.value == JS_HOLE
    return false if (c.attrs & ATTR_C) == 0
    c.value = JS_HOLE
    @order = @order.select(->(k) k != key)
    true

  -> own_keys
    @order.select(->(k) @cells[k].value != JS_HOLE)

  -> enumerable?(key)
    c = @cells[key]
    c != nil && (c.attrs & ATTR_E) != 0

  -> attr(key)
    c = @cells[key]
    c == nil ? ATTR_DEFAULT : c.attrs

  -> get_own_property(key)
    c = @cells[key]
    return nil if c == nil || c.value == JS_HOLE
    a = c.attrs
    v = c.value
    d = JS:PropDesc.new
    if (a & ATTR_ACCESSOR) != 0
      d.getter = v.getter
      d.setter = v.setter
      d.has_get = true
      d.has_set = true
    else
      d.value = v
      d.has_value = true
      d.writable = (a & ATTR_W) != 0
    d.enumerable = (a & ATTR_E) != 0
    d.configurable = (a & ATTR_C) != 0
    d

  -> define_accessor(key, g, st, flags = ATTR_E + ATTR_C)
    c = cell(key)
    @order.push(key) if c.value == JS_HOLE
    c.put(JS:Accessor.new(g, st), (flags & (ATTR_E + ATTR_C)) | ATTR_ACCESSOR)
    nil

# The cell of a global name (created absent).
-> js_gcell(name)
  js_realm().global.cell(name)

# A global read: the cell's value, else the global object's prototype chain, else a
# ReferenceError.
-> js_gget(c)
  cb = wvalue_bits(c) ## i64
  v = jsr_gcell_fast(cb)
  return wvalue_from_bits(v) if v != (6 ## i64)
  js_gget_slow(c)

# A cell's value while it is plain, else JSR_SLOW. (Raw bits are compared only inside
# typed fns: in untyped code an i64 beyond 48 bits would box.)
fn jsr_gcell_fast(cb) (i64) i64
  v = jsr_ivar(cb, 0)
  if v == 3
    return 6
  v


-> js_gget_slow(c)
  lm = js_lexical_map()
  if lm.size > 0
    lc = lm[c.name]
    if lc != nil
      js_throw_reference("Cannot access '" + c.name + "' before initialization") if lc.value == JS_HOLE
      return lc.value
  g = js_realm().global
  if c.value != JS_HOLE
    return (c.attrs & ATTR_ACCESSOR) != 0 ? js_accessor_get(c.value, g) : c.value
  p = g.shape.proto
  if p != nil
    return p.get(c.name, g) if jhas_property?(p, c.name)
  js_throw_reference(c.name + " is not defined")

# typeof of a global name: undefined instead of a ReferenceError.
-> js_gtypeof(c)
  v = c.value
  return js_typeof(v) if v != JS_HOLE && (c.attrs & ATTR_ACCESSOR) == 0
  g = js_realm().global
  js_typeof(g.get(c.name, g))

# A global write. strict: an undeclared name is a ReferenceError.
-> js_gset(c, v, strict)
  cb = wvalue_bits(c) ## i64
  if jsr_gcell_fast(cb) != (6 ## i64)
    ccall("w_ivar_set_idx", c, 0, v)
    return v
  g = js_realm().global
  if strict && c.value == JS_HOLE
    p = g.shape.proto
    js_throw_reference(c.name + " is not defined") if p == nil || !jhas_property?(p, c.name)
  ok = g.set(c.name, v, g)
  js_throw_type("Cannot assign to read only property '" + c.name + "' of object") if !ok && strict
  v

# A top-level var or function declaration (configurable: false, as declared bindings are).
# A script's var or function declaration (eval code's are configurable: attrs).
-> js_gdeclare(c, v, is_fn, attrs = ATTR_W + ATTR_E)
  g = js_realm().global
  if c.value == JS_HOLE
    g.define(c.name, is_fn ? v : nil, attrs)
  elsif is_fn
    if (c.attrs & ATTR_C) != 0
      g.define(c.name, v, attrs)
    else
      c.value = v
  nil

# ---- generic property access (computed keys, primitives) ----

# o[key] for any value o and any key value.
-> js_getv(o, key)
  js_throw_type("Cannot read properties of " + js_to_display(o)) if js_nullish?(o)
  if js_array?(o)
    return js_array_get_index(o, key) if js_number?(key)
    return js_array_get(o, js_to_property_key(key))
  if o.is_a?(JS:TypedArray) && js_number?(key)
    ix = jsr_index(wvalue_bits(key) ## i64)
    return js_ta_get(o, ix) if ix >= 0
  if js_string?(o) && js_number?(key)
    ix = jsr_index(wvalue_bits(key) ## i64)
    if ix >= 0
      if o.ascii?
        return ix < o.size ? o.slice(ix, 1) : nil
      u = js_units(o)
      return ix < u.size ? js_cp_str(u[ix]) : nil
  k = js_to_property_key(key)
  return o.get(k, o) if o.is_a?(JS:Base)
  js_get_prim(o, k)

# A property of a value that is not a JS:Base object.
-> js_get_prim(o, key)
  if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
    return JS_DOM_HOOK[0].get(o, key, o)
  if js_array?(o)
    if key.is_a?(String)
      return js_arr_len(o).to_f if key == "length"
      if (key.size == 0 || key.byte_at(0) < 48 || key.byte_at(0) > 57) && (js_array_flags(o) & JS_AF_EXT) == 0 && !JS_MULTI_REALM[0]
        return js_proto_get_cached(js_realm().array_proto, key, o)
    return js_array_get(o, key)
  if js_string?(o)
    if key.is_a?(String)
      return js_str_length(o) if key == "length"
      if key.size > 0 && key.byte_at(0) >= 48 && key.byte_at(0) <= 57 && js_array_index?(key)
        i = key.to_i
        if o.ascii?
          return i < o.size ? o.slice(i, 1) : nil
        u = js_units(o)
        return i < u.size ? js_cp_str(u[i]) : nil
      return js_proto_get_cached(js_realm().string_proto, key, o)
    return js_realm().string_proto.get(key, o)
  return js_realm().number_proto.get(key, o) if js_number?(o)
  return js_realm().boolean_proto.get(key, o) if o == true || o == false
  return js_realm().symbol_proto.get(key, o) if o.is_a?(JS:Symbol)
  if o.is_a?(JS:BigIntValue)
    bp = js_realm().intrinsics["BigInt.prototype"]
    return bp == nil ? nil : bp.get(key, o)
  js_throw_type("Cannot read properties of " + js_to_display(o) + " (reading '" + js_to_display(js_key_display(key)) + "')") if js_nullish?(o)
  nil

-> js_get_value(o, key)
  return o.get(key, o) if o.is_a?(JS:Base)
  js_get_prim(o, key)

# o[key] = v for any value o.
-> js_setv(o, key, v, strict)
  js_throw_type("Cannot set properties of " + js_to_display(o)) if js_nullish?(o)
  if js_array?(o)
    ok = js_array_set(o, key, v)
    js_throw_type("Cannot assign to read only property") if !ok && strict
    return v
  if o.is_a?(JS:TypedArray) && js_number?(key) && !o.buffer.immutable
    ix = jsr_index(wvalue_bits(key) ## i64)
    if ix >= 0
      js_ta_set_idx(o, ix, v)
      return v
  k = js_to_property_key(key)
  if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
    ok = JS_DOM_HOOK[0].set(o, k, v, o)
    js_throw_type("Cannot assign to read only property '" + js_to_display(js_key_display(k)) + "' of object") if !ok && strict
    return v
  if o.is_a?(JS:Base)
    ok = o.set(k, v, o)
    js_throw_type("Cannot assign to read only property '" + js_to_display(js_key_display(k)) + "' of object") if !ok && strict
    return v
  js_set_prim(o, k, v, strict)
  v

-> js_set_prim(o, key, v, strict = false)
  if js_dom_handle?(o) && JS_DOM_HOOK[0] != nil
    ok = JS_DOM_HOOK[0].set(o, key, v, o)
    js_throw_type("Cannot assign to read only property '" + js_to_display(js_key_display(key)) + "' of object") if !ok && strict
    return nil
  return js_array_set(o, key, v) if js_array?(o)
  js_throw_type("Cannot set properties of " + js_to_display(o) + " (setting '" + js_to_display(js_key_display(key)) + "')") if js_nullish?(o)
  r = js_realm()
  p = js_number?(o) ? r.number_proto : (js_string?(o) ? r.string_proto : ((o == true || o == false) ? r.boolean_proto : (o.is_a?(JS:Symbol) ? r.symbol_proto : r.intrinsics["BigInt.prototype"])))
  ok = p == nil ? false : p.set(key, v, o)
  js_throw_type("Cannot create property '" + js_to_display(js_key_display(key)) + "' on " + js_typeof(o)) if !ok && strict
  nil

# ---- strings (UTF-16 view of UTF-8 strings) ----

-> js_str_length(s)
  return s.size.to_f if s.ascii?
  js_units(s).size.to_f

-> js_str_units(s)
  js_units(s)

-> js_str_at(s, i)
  return s.slice(i, 1) if s.ascii?
  js_cp_str(js_units(s)[i])

# ---- errors ----

-> js_make_error(kind, msg)
  r = js_realm()
  p = r.proto_of(kind)
  e = js_new_special(p, "Error")
  e.define("message", msg, ATTR_W + ATTR_C)
  if JS_STACK_HOOK[0] == nil
    e.internal = kind + ": " + msg
  else
    js_error_locate(e)
  e

-> js_throw_type(msg)
  js_throw(js_make_error("TypeError", msg))

-> js_throw_range(msg)
  js_throw(js_make_error("RangeError", msg))

-> js_throw_reference(msg)
  js_throw(js_make_error("ReferenceError", msg))

# ---- the realm's intrinsics ----

SYM_TO_PRIMITIVE = JS:Symbol.new("Symbol.toPrimitive")
SYM_ITERATOR = JS:Symbol.new("Symbol.iterator")

-> js_method(o, name, len, fn)
  o.define(name, js_native(name, len, fn), ATTR_W + ATTR_C)
  nil

-> js_arg(args, i)
  i < args.size ? args[i] : nil

-> js_new_realm(host = nil)
  prev_boot = JS_GC_BOOT[0]
  JS_GC_BOOT[0] = true
  r = JS:Realm.new
  r.host = host == nil ? JS:Host.new : host
  JS_REALM[0] = r
  JS_FIRST_REALM[0] = r if !JS_MULTI_REALM[0]
  op = js_new_special(nil, "Object")
  r.object_proto = op
  r.set_intrinsic("Object.prototype", op)
  # Function.prototype is itself callable: a native that returns undefined
  fp = JS:NativeFunction.new(js_root_shape(op, NF_INLINE, NF_IBASE), ->(this, args, nt) nil, "", 0)
  fp.realm = r
  r.function_proto = fp
  r.set_intrinsic("Function.prototype", fp)
  r.fn_shape = js_root_shape(fp, FN_INLINE, FN_IBASE)
  r.native_shape = js_root_shape(fp, NF_INLINE, NF_IBASE)
  g = JS:GlobalObject.new(js_root_shape(op, 0, 2))
  r.global = g
  i = 0
  while i < JS_INSTALLERS.size
    JS_INSTALLERS[i].call(r)
    i += 1
  r.array_proto = r.intrinsic?("Array.prototype") ? r.intrinsic("Array.prototype") : js_new_special(op, "Array")
  r.string_proto = r.intrinsic?("String.prototype") ? r.intrinsic("String.prototype") : js_new_special(op, "String")
  r.number_proto = r.intrinsic?("Number.prototype") ? r.intrinsic("Number.prototype") : js_new_special(op, "Number")
  r.boolean_proto = r.intrinsic?("Boolean.prototype") ? r.intrinsic("Boolean.prototype") : js_new_special(op, "Boolean")
  r.symbol_proto = r.intrinsic?("Symbol.prototype") ? r.intrinsic("Symbol.prototype") : js_new_special(op, "Symbol")
  r.error_proto = r.intrinsic?("Error.prototype") ? r.intrinsic("Error.prototype") : js_new_special(op, "Error")
  g.define("globalThis", g, BUILTIN_ATTRS)
  g.define("undefined", nil, 0)
  g.define("NaN", js_nan(), 0)
  g.define("Infinity", ~1.0 / ~0.0, 0)
  JS_GC_BOOT[0] = prev_boot
  js_gc_add_realm(r)
  r

# Create a sibling realm inside the same agent (shares microtask queue and global symbol registry).
-> js_create_sub_realm(parent)
  JS_MULTI_REALM[0] = true
  prev = JS_REALM[0]
  r2 = nil
  begin
    r2 = js_new_realm(parent.host)
    r2.share_jobs(parent)
    r2.symbol_registry = parent.symbol_registry
  rescue ex
    JS_REALM[0] = prev
    raise ex
  JS_REALM[0] = prev
  r2

