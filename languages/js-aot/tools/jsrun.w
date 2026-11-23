# jsrun — run a JavaScript file outside a browser: console to stdout, timers in virtual
# time, microtasks drained after each task.
#
#   jsrun file.js             # tier 0 (the closure interpreter)
#
# Prints "Uncaught …" and exits 1 on an uncaught exception. JSRUN_TIME=1 adds the run time.

use ../tier0/engine

+ JsRunTimers
  rw :list, :seq, :now
  -> new
    @list = []
    @seq = 0
    @now = ~0.0

  -> add(f, ms, args, repeat)
    @seq += 1
    d = ms == nil ? ~0.0 : js_to_number(ms)
    d = ~0.0 if d != d || d < ~0.0
    @list.push([@seq, @now + d, f, args, repeat ? (d < ~1.0 ? ~1.0 : d) : nil])
    @seq + ~0.0

  -> clear(id)
    i = js_to_number(id)
    @list = @list.select(->(t) t[0] + ~0.0 != i)
    nil

  -> run_all(r)
    guard = 0
    while @list.size > 0 && guard < 100000
      guard += 1
      @list = @list.sort_by(->(t) t[1] * ~1000000.0 + t[0])
      t = @list.shift
      @now = t[1] if t[1] > @now
      if t[4] != nil
        @list.push([t[0], @now + t[4], t[2], t[3], t[4]])
      js_call(t[2], nil, t[3]) if t[2].is_a?(JsObject) && t[2].callable?
      r.run_jobs
    nil

-> jsrun_install(r, rt)
  g = r.global
  r.method(g, "setTimeout", 2, ->(this, args, nt) rt.add(js_arg(args, 0), js_arg(args, 1), args.size > 2 ? args.slice(2, args.size - 2) : [], false))
  r.method(g, "setInterval", 2, ->(this, args, nt) rt.add(js_arg(args, 0), js_arg(args, 1), args.size > 2 ? args.slice(2, args.size - 2) : [], true))
  r.method(g, "clearTimeout", 1, ->(this, args, nt) rt.clear(js_arg(args, 0)))
  r.method(g, "clearInterval", 1, ->(this, args, nt) rt.clear(js_arg(args, 0)))
  r.method(g, "queueMicrotask", 1, ->(this, args, nt) r.enqueue_job(->() js_call(js_arg(args, 0), nil, []), [js_arg(args, 0)]))
  r.method(g, "print", 1, ->(this, args, nt) js_console_out("log", args))
  nil

-> jsrun_main(path)
  r = js_new_realm(nil)
  src = File.read(path)
  t0 = clock_ms()
  rt = JsRunTimers.new
  jsrun_install(r, rt)
  ok = true
  begin
    js_run_script(src, path)
    r.run_jobs
    rt.run_all(r)
  rescue e
    ok = false
    v = js_error_value(e)
    << "Uncaught " + (v.is_a?(JsObject) ? js_inspect(v, 1, []) : js_to_display(v))
  << "(" + (clock_ms() - t0).to_s + " ms)" if Env.get("JSRUN_TIME", "") == "1"
  ccall("w_flush")
  if Env.get("JSRUN_PAUSE", "") == "1"
    # tools/memstat.sh --heap: hold the heap still for `heap` until killed
    ccall("w_eputs", "jsrun: paused")
    while true
      sleep(1)
  # suspended generators and async functions are goroutines parked forever: don't wait on them
  exit(ok ? 0 : 1)

if ARGV.size < 1
  << "usage: jsrun file.js"
  exit(2)
jsrun_main(ARGV[0])
