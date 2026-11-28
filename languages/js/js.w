# tungsten/languages/js/js.w — Tungsten's canonical ECMAScript 2025 JavaScript engine.
#
# Complete pure-Tungsten JS runtime with:
#   - NEON SIMD Lexer (t/lexer_simd.w) & ECMAScript 2025 Parser / Analyzer
#   - Tier 0 AST evaluator + stackless coroutine state-machine (sm_coro.w)
#   - Tier 1 speculative ARM64 JIT + OSR + ARM64 RegExp JIT + WIRE-to-ARM64 NEON/Metal swizzler
#   - Precise mark-sweep garbage collector (gc.w)
#   - Full ES2025 standard library (Promises, Modules, TypedArrays, Intl, Temporal, ShadowRealm)
#
# High-level API:
#   JS.eval("1 + 2 * 3")            # => 7.0 (auto-creates a default realm)
#   JS.new_realm(host = nil)        # => JS:Realm
#   js_new_realm(host) / js_run_script(src, name) / realm.run_jobs

# Inline-cache words for compiled code; declared ahead of the runtime, whose fast paths
# read it (tier 0 keeps its caches on the syntax tree instead).
JS_IC = i64[8]

use main
use units
use unit_rt
use walk
use sm_coro
use module
use jit_mem
use arm64
use regexp_jit
use jit_rt
use jit_analyze
use jit
use gc
use compat
use unitcache
use t/compiler

# A function a loaded unit, JS->Tungsten kernel (BLADE_JS_TUNGSTEN=1), or the in-process
# ARM64 JIT compiled runs natively; the rest run in tier 0.
-> js_dispatch_in_realm(c, f, this, argc, a0, a1, a2, a3, more)
  if (c.flags & CODE_CLASS) != 0 && JS_NEW_TARGET[0] == nil
    js_throw_type("Class constructor " + c.name.to_s + " cannot be invoked without 'new'")
  if JS_DEADLINE_SEC[0] <= ~0.0
    if JST_ENABLED[0]
      jr = jst_try_dispatch(c, argc, a0, a1, a2, a3, more)
      return jr if jr != JS_HOLE
    return js_unit_enter(c, f, this, argc, a0, a1, a2, a3, more) if c.entry != 0
    if c.jit_fp != 0
      return jit_enter_fn(c, f, this, argc, a0, a1, a2, a3, more)
  wk_call(f, this, argc, a0, a1, a2, a3, more)

-> js_dispatch(i, f, this, argc, a0, a1, a2, a3, more)
  c = f.code
  fr = c.realm
  if fr != nil && fr != JS_REALM[0]
    prev = JS_REALM[0]
    JS_REALM[0] = fr
    res = nil
    begin
      res = js_dispatch_in_realm(c, f, this, argc, a0, a1, a2, a3, more)
    rescue ex
      JS_REALM[0] = prev
      raise ex
    JS_REALM[0] = prev
    return res
  js_dispatch_in_realm(c, f, this, argc, a0, a1, a2, a3, more)

WK_PRE_RUN[0] = ->(an) jsu_on_script(an)

# Convenience facade on the JS module namespace for standalone Tungsten scripts.
+ JS
  -> .new_realm(host = nil)
    js_new_realm(host)

  -> .eval(src, name = "<eval>", realm = nil)
    prev = JS_REALM[0]
    out = nil
    begin
      r = realm == nil ? js_new_realm(nil) : realm
      JS_REALM[0] = r
      out = js_run_script(src, name)
      r.run_jobs
    rescue ex
      JS_REALM[0] = prev
      raise ex
    JS_REALM[0] = prev
    out
