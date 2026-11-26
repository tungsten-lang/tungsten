# blade/js/tls — per-thread engine state, so each Web Worker runs its own realm on its own
# OS thread (blade/jsworker).
#
# The engine keeps its running state in global cells (JS_REALM[0], JS_DEPTH[0], the call
# stack JS_STACK, caches …). Each such global is defined as a JsTlsCell / JsTlsHash /
# JsTlsList instead of an Array or Hash literal: the interface is the same (`X[0]`,
# `X[0] = v`, `h[k]`, `l.push`), so no call site changes, but every thread sees its own copy.
#
# A thread is identified by its thread pointer (TPIDRRO_EL0 on arm64 macOS). Goroutines run
# on the OS thread that spawned them (Tungsten's cooperative per-thread run queues), so JS
# generators/async functions of a worker see the worker's state. The main thread is index 0;
# worker threads register (js_tls_register) and get 1..JS_TLS_MAX-1. A thread that never
# registered (Blade's media decode workers) reads the main thread's state, as before.
#
# TODO(tungsten web-apis branch): core ThreadLocal provides the same slots in the runtime,
# inherited by goroutines even under the M:P scheduler; switch js_tls_index to it once that
# branch is merged into blade-ui.

fn js_tp() () i64
  asm <<~ASM
    mrs x0, tpidrro_el0
    ret
  ASM

JS_TLS_MAX = 64
JS_TLS_MAIN = [js_tp()]
# tps[i] of registered threads (0 = free slot); slot 0 is the main thread
JS_TLS_TPS = Array.new(64, 0)
JS_TLS_HI = [0]
JS_TLS_LOCK = Mutex.new
JS_TLS_ALL = []

-> js_tls_index
  tp = js_tp()
  return 0 if tp == JS_TLS_MAIN[0]
  i = 1
  n = JS_TLS_HI[0]
  while i <= n
    return i if JS_TLS_TPS[i] == tp
    i += 1
  0

# Register the calling thread; returns its index (nil when all slots are taken). Its
# per-thread state starts fresh (initial values of every cell, empty hashes and lists).
-> js_tls_register
  tp = js_tp()
  idx = nil
  JS_TLS_LOCK.lock
  i = 1
  while i < JS_TLS_MAX && idx == nil
    idx = i if JS_TLS_TPS[i] == 0
    i += 1
  if idx != nil
    JS_TLS_ALL.each ->(c) c.reset_slot(idx)
    JS_TLS_TPS[idx] = tp
    JS_TLS_HI[0] = idx if idx > JS_TLS_HI[0]
  JS_TLS_LOCK.unlock
  idx

# The calling thread is finishing: free its slot.
-> js_tls_unregister
  i = js_tls_index()
  return nil if i == 0
  JS_TLS_LOCK.lock
  JS_TLS_TPS[i] = 0
  JS_TLS_LOCK.unlock
  nil

# Fixed-size cells: `JS_DEPTH = JsTlsCell.new(1, 0)` behaves like `[0]` per thread.
+ JsTlsCell
  -> new(n, init)
    @n = n
    @init = init
    @per = Array.new(64, nil)
    @main = Array.new(n, init)
    @main_tp = JS_TLS_MAIN[0]
    @per[0] = @main
    JS_TLS_ALL.push(self)

  -> reset_slot(i)
    @per[i] = Array.new(@n, @init)

  -> cells
    a = @per[js_tls_index()]
    a == nil ? @main : a

  # (hot: JS_REALM[0], JS_DEPTH[0], JS_STACK[d] on every call — the main thread is one compare)
  -> [](k)
    return @main[k] if js_tp() == @main_tp
    cells()[k]

  -> []=(k, v)
    return @main[k] = v if js_tp() == @main_tp
    cells()[k] = v

  -> size
    @n

  # Set slot k of another thread's copy (terminate() stopping a worker's script).
  -> set_for(idx, k, v)
    a = @per[idx]
    a[k] = v if a != nil
    nil

# A per-thread Hash (caches, registries).
+ JsTlsHash
  -> new
    @per = Array.new(64, nil)
    @per[0] = {}
    JS_TLS_ALL.push(self)

  -> reset_slot(i)
    @per[i] = {}

  -> h
    a = @per[js_tls_index()]
    a == nil ? @per[0] : a

  -> [](k)
    h()[k]

  -> []=(k, v)
    h()[k] = v

  -> has_key?(k)
    h().has_key?(k)

  -> delete(k)
    h().delete(k)

  -> size
    h().size

  -> keys
    h().keys

  -> values
    h().values

  -> clear
    h().clear

# A per-thread growable Array (pending lists).
+ JsTlsList
  -> new
    @per = Array.new(64, nil)
    @per[0] = []
    JS_TLS_ALL.push(self)

  -> reset_slot(i)
    @per[i] = []

  -> l
    a = @per[js_tls_index()]
    a == nil ? @per[0] : a

  -> [](k)
    l()[k]

  -> []=(k, v)
    l()[k] = v

  -> push(v)
    l().push(v)

  -> pop
    l().pop

  -> shift
    l().shift

  -> size
    l().size

  -> index(v)
    l().index(v)

  -> delete_at(i)
    l().delete_at(i)

  -> select(f)
    l().select(f)

  -> include?(v)
    l().include?(v)

  -> clear
    l().clear

  -> to_a
    l()
