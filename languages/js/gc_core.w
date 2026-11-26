# jsn/gc_core — Allocation registry & flags for the jsn mark-sweep collector.
# Loaded early (right after prims.w) so allocation hot paths check JS_GC_ON[0] with zero overhead when off.

JS_GC_ON = [Env.get("BLADE_JS_GC", "") == "1"]
JS_GC_LOG = [Env.get("BLADE_JS_GC_LOG", "") == "1"]
JS_GC_VERIFY = [Env.get("BLADE_JS_GC_VERIFY", "") == "1"]
JS_GC_DEAD = {}
JS_GC_BOOT = [false]
JS_GC_TRUST = [false]
JS_GC_HEAP = []
JS_GC_REALMS = []
JS_GC_REALM_SET = {}
JS_GC_ROOTS = []
JS_GC_HOST_CLASSES = {}
JS_GC_KEEP = {}
JS_GC_WEAK_REFS = []
JS_GC_FIN_REGS = []
JS_GC_BASE = [Env.get("BLADE_JS_GC_EVERY", "").size > 0 ? Env.get("BLADE_JS_GC_EVERY", "").to_i : 80000]
JS_GC_NEXT = [JS_GC_BASE[0]]
JS_GC_STATS = [0, 0, 0, 0]

# Extract 47-bit aligned pointer key from any heap WValue (fits in immediate 48-bit Int — ZERO WBigint!).
fn js_gc_key(v_bits) (i64) i64
  v_bits & 140737488355312

# Register a JS-allocated object/array/closure/env as collectable (when BLADE_JS_GC=1).
-> js_gc_reg(v)
  JS_GC_HEAP.push(v) if JS_GC_ON[0] && !JS_GC_BOOT[0]
  v

-> js_gc_reg_weakref(wr)
  JS_GC_WEAK_REFS.push(wr) if JS_GC_ON[0]
  wr

-> js_gc_reg_finreg(fr)
  JS_GC_FIN_REGS.push(fr) if JS_GC_ON[0]
  fr

-> js_gc_add_root(v)
  JS_GC_ROOTS.push(v)
  nil

-> js_gc_remove_root(v)
  JS_GC_ROOTS.delete(v)
  nil

-> js_gc_host_class(name)
  JS_GC_HOST_CLASSES[name] = true
  nil

-> js_keep(f, vals)
  JS_GC_KEEP[js_gc_key(wvalue_bits(f) ## i64)] = vals if f != nil && vals != nil
  f
