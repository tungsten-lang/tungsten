# Run a list of test262 tests on Blade's jsn engine (with both JIT and Tier 0 support).
# Args: <test262_root> <list_file>
# Prints one flushed line per test: PASS|FAIL|SKIP path [reason]

use ../js

JSU_ON[0] = false

SKIP_FEATURES = []

+ T262Host < JsHost
  rw :out
  -> new
    @out = []
  -> console(level, text)
    nil

-> t262_frontmatter(src)
  a = src.index("/*---")
  return "" if a == nil
  b = src.index("---*/", a)
  return "" if b == nil
  fm = src.slice(a + 5, b - a - 5)
  return fm if fm.index("\r") == nil
  fm.split("\r\n").join("\n").split("\r").join("\n")

-> t262_list(fm, key)
  out = []
  i = fm.index("\n" + key + ":")
  i = fm.index(key + ":") if i == nil && fm.starts_with?(key + ":")
  return out if i == nil
  line_end = fm.index("\n", i + 1)
  line_end = fm.size if line_end == nil
  line = fm.slice(i, line_end - i)
  lb = line.index("\[")
  if lb != nil
    rb = line.index("]")
    inner = line.slice(lb + 1, (rb == nil ? line.size : rb) - lb - 1)
    inner.split(",").each ->(x)
      t = x.strip
      out.push(t) if t.size > 0
    return out
  j = line_end + 1
  while j < fm.size
    le = fm.index("\n", j)
    le = fm.size if le == nil
    l = fm.slice(j, le - j)
    t = l.strip
    if t.starts_with?("- ")
      out.push(t.slice(2, t.size - 2).strip)
    elsif t.size > 0
      break
    j = le + 1
  out

-> t262_negative(fm)
  i = fm.index("negative:")
  return nil if i == nil
  ph = fm.index("phase:", i)
  ty = fm.index("type:", i)
  return nil if ph == nil || ty == nil
  phe = fm.index("\n", ph)
  phe = fm.size if phe == nil
  tye = fm.index("\n", ty)
  tye = fm.size if tye == nil
  phase = fm.slice(ph + 6, phe - ph - 6).strip
  type = fm.slice(ty + 5, tye - ty - 5).strip
  [phase, type]

HARNESS = {}

-> t262_harness(root, name)
  h = HARNESS[name]
  if h == nil
    h = File.read(root + "/harness/" + name)
    HARNESS[name] = h
  h

+ T262AgentState
  rw :mu, :reports, :broadcast_sab, :broadcast_gen, :active, :threads, :workers, :timers, :aborted

  -> new
    @mu = Mutex.new
    @reports = []
    @broadcast_sab = nil
    @broadcast_gen = 0
    @active = 0
    @threads = []
    @workers = []
    @timers = []
    @aborted = false

  -> yield_turn(nap)
    r = JS_REALM[0]
    act = JS_CUR_ACT[0]
    top0 = JS_TOP[0]
    top1 = JS_TOP[1]
    nt = JS_NEW_TARGET[0]
    cr = JS_CONSTRUCT_REALM[0]
    cb = JS_CAN_BLOCK[0]
    cd = JS_CALL_DEPTH[0]
    @mu.unlock
    sleep(nap)
    @mu.lock
    JS_REALM[0] = r
    JS_CUR_ACT[0] = act
    JS_TOP[0] = top0
    JS_TOP[1] = top1
    JS_NEW_TARGET[0] = nt
    JS_CONSTRUCT_REALM[0] = cr
    JS_CAN_BLOCK[0] = cb
    JS_CALL_DEPTH[0] = cd
    nil

  -> start_worker(parent_realm, out, sub_realms, script)
    @active += 1
    JS_MULTI_REALM[0] = true
    wstate = [false, 0, nil]  # [leaving, seen_bcast_gen, realm]
    @workers.push(wstate)
    st = self
    th = Thread.new ->
      st.mu.lock
      r2 = nil
      begin
        JS_REALM[0] = parent_realm
        r2 = js_new_realm(parent_realm.host)
        sub_realms.push(r2)
        wstate[2] = r2
        t262_install_host(r2, out, sub_realms, st, wstate)
        JS_REALM[0] = r2
        JS_CUR_ACT[0] = nil
        JS_TOP[0] = script
        JS_TOP[1] = ""
        JS_CAN_BLOCK[0] = true
        JS_CALL_DEPTH[0] = 0
        js_run_script(script)
        r2.run_jobs
        while !wstate[0] && !st.aborted
          js_wait_async_poll()
          r2.run_jobs
          break if js_wait_async_poll() == 0 && r2.jobs.head == r2.jobs.tail
          st.yield_turn(~0.001)
      rescue e
        nil
      st.active -= 1
      st.mu.unlock
    @threads.push(th)
    yield_turn(~0.001)
    nil

  -> broadcast(sab)
    js_throw_type("$262.agent.broadcast requires a SharedArrayBuffer") if !(sab.is_a?(JS:ArrayBuffer) && sab.shared)
    @broadcast_sab = sab
    @broadcast_gen += 1
    yield_turn(~0.001)
    nil

  -> receive_broadcast(wstate, cb)
    while @broadcast_gen <= wstate[1] && !@aborted
      yield_turn(~0.0005)
    return nil if @aborted
    wstate[1] = @broadcast_gen
    sab = @broadcast_sab
    # Wrap shared ByteArray in worker realm's SharedArrayBuffer
    r = JS_REALM[0]
    nsab = js_special_new(r.intrinsic("SharedArrayBuffer.prototype"), "SharedArrayBuffer", :buffer)
    nsab.data = sab.data
    nsab.blen = sab.blen
    nsab.max_len = sab.max_len
    nsab.detached = false
    nsab.shared = true
    js_call_arr(cb, nil, [nsab])
    r.run_jobs
    nil

  -> report(val)
    @reports.push(js_to_string(val))
    nil

  -> get_report
    if @reports.size == 0 && @active > 0
      k = 0
      while k < 10 && @reports.size == 0 && @active > 0
        yield_turn(~0.0005)
        k += 1
    return JS_NULL if @reports.size == 0
    @reports.delete_at(0)

  -> sleep_ms(ms)
    d = js_to_number(ms)
    d = ~0.0 if d != d || d < ~0.0
    deadline = clock() + d / ~1000.0
    while clock() < deadline && !@aborted
      rem = deadline - clock()
      yield_turn(rem > ~0.002 ? ~0.002 : (rem > ~0.0002 ? rem : ~0.0002))
    nil

  -> pump_timers
    now = clock()
    i = 0
    fired = false
    while i < @timers.size
      t = @timers[i]
      if now >= t[0]
        @timers.delete_at(i)
        prev = JS_REALM[0]
        JS_REALM[0] = t[2]
        begin
          js_call_arr(t[1], nil, JS_NO_ARGS)
        rescue e
          nil
        JS_REALM[0] = prev
        fired = true
      else
        i += 1
    fired

  -> shutdown
    @aborted = true
    deadline = clock() + ~3.0
    while @active > 0 && clock() < deadline
      yield_turn(~0.002)
    nil

-> t262_install_host(r, out, sub_realms, ast, wstate = nil)
  prev = JS_REALM[0]
  JS_REALM[0] = r
  g = r.global
  r.method(g, "print", 1, ->(this, args, nt) out.push(js_to_string(js_arg(args, 0))))
  d = r.new_object
  g.define("$262", d, BUILTIN_ATTRS)
  d.define("global", g, BUILTIN_ATTRS)
  r.method(d, "evalScript", 1, ->(this, args, nt) js_run_script(js_to_string(js_arg(args, 0))))
  r.method(d, "gc", 0, ->(this, args, nt) js_gc_collect(nil))
  r.method(d, "detachArrayBuffer", 1, ->(this, args, nt) js_detach_buffer(js_arg(args, 0)))
  r.method(d, "createRealm", 0, ->(this, args, nt) t262_create_realm(r, out, sub_realms, ast))
  d.define("IsHTMLDDA", js_new_htmldda(r.object_proto), BUILTIN_ATTRS)
  d.define("AbstractModuleSource", r.intrinsic("%AbstractModuleSource%"), BUILTIN_ATTRS)
  ag = r.new_object
  d.define("agent", ag, BUILTIN_ATTRS)
  if ast != nil
    r.method(ag, "start", 1, ->(this, args, nt) ast.start_worker(r, out, sub_realms, js_to_string(js_arg(args, 0))))
    r.method(ag, "broadcast", 1, ->(this, args, nt) ast.broadcast(js_arg(args, 0)))
    r.method(ag, "receiveBroadcast", 1, ->(this, args, nt) ast.receive_broadcast(wstate, js_arg(args, 0)))
    r.method(ag, "report", 1, ->(this, args, nt) ast.report(js_arg(args, 0)))
    r.method(ag, "getReport", 0, ->(this, args, nt) ast.get_report())
    r.method(ag, "sleep", 1, ->(this, args, nt) ast.sleep_ms(js_arg(args, 0)))
    r.method(ag, "monotonicNow", 0, ->(this, args, nt) clock() * ~1000.0)
    r.method(ag, "leaving", 0, ->(this, args, nt) t262_agent_leaving(wstate))
  JS_REALM[0] = prev
  d

-> t262_agent_leaving(wstate)
  wstate[0] = true if wstate != nil
  nil

-> t262_set_timeout(ast, r, cb, delay_v)
  d = delay_v == nil ? ~0.0 : js_to_number(delay_v)
  d = ~0.0 if d != d || d < ~0.0
  # Cap getReportAsync's 1000ms retry sleep when reports arrive early by waking on next tick if report queued
  ast.timers.push([clock() + d / ~1000.0, cb, r])
  ~0.0

-> t262_create_realm(parent, out, sub_realms, ast)
  r2 = js_create_sub_realm(parent)
  sub_realms.push(r2)
  t262_install_host(r2, out, sub_realms, ast)

-> t262_norm_path(base_file, spec)
  # Resolve relative specifier against base_file's directory and normalize . / ..
  dir = ""
  li = base_file.rindex("/")
  dir = base_file.slice(0, li) if li != nil
  raw = spec.starts_with?("/") ? spec : (dir == "" ? spec : dir + "/" + spec)
  parts = raw.split("/")
  st = []
  i = 0
  while i < parts.size
    seg = parts[i]
    if seg == "" || seg == "."
      nil
    elsif seg == ".."
      st.pop if st.size > 0
    else
      st.push(seg)
    i += 1
  "/" + st.join("/")

-> t262_load_module(ref_url, spec, attrs, phase)
  # Validate supported `type` import attribute; ignore host-unknown non-type attributes per HostGetSupportedImportAttributes.
  kind = :source
  if attrs != nil && attrs.has_key?("type")
    tv = attrs["type"]
    if tv == "json"
      kind = :json
    elsif tv == "text"
      kind = :text
    elsif tv == "bytes"
      kind = :bytes
    else
      js_throw_type("Unsupported import attribute type: " + tv.to_s)
  canon = t262_norm_path(ref_url, spec)
  content = nil
  begin
    content = File.read(canon)
  rescue e
    js_throw_type("Cannot load module '" + spec + "'")
  [canon, kind, content]

-> t262_run(root, rel)
  path = root + "/test/" + rel
  src = File.read(path)
  fm = t262_frontmatter(src)
  flags = t262_list(fm, "flags")
  feats = t262_list(fm, "features")
  feats.each ->(f)
    return "SKIP " + rel + " feature " + f if SKIP_FEATURES.include?(f)
  is_mod = flags.include?("module")
  neg = t262_negative(fm)
  strict = flags.include?("onlyStrict")
  raw = flags.include?("raw")
  is_async = flags.include?("async")
  incs = t262_list(fm, "includes")
  has_agent = src.index("$262.agent.") != nil || incs.include?("atomicsHelper.js")
  sb = StringBuffer()
  if !raw
    sb.append("\"use strict\";\n") if strict && !is_mod
    sb.append(t262_harness(root, "assert.js"))
    sb.append("\n")
    sb.append(t262_harness(root, "sta.js"))
    sb.append("\n")
    if is_async
      sb.append(t262_harness(root, "doneprintHandle.js"))
      sb.append("\n")
    incs.each ->(inc)
      sb.append(t262_harness(root, inc))
      sb.append("\n")
  full = sb.to_s
  host = T262Host.new
  JS_LEXICAL.keys.each ->(k) JS_LEXICAL.delete(k)
  JS_UNHANDLED.clear
  JS_WAITERS.clear
  JS_MULTI_REALM[0] = false
  JS_ARR_REALM_PROTO.keys.each ->(k) JS_ARR_REALM_PROTO.delete(k)
  JS_RX_REALM.keys.each ->(k) JS_RX_REALM.delete(k)
  JS_CAN_BLOCK[0] = !flags.include?("CanBlockIsFalse")
  JS_CURRENT_URL[0] = path
  JS_MODULE_LOADER_HOOK[0] = ->(ref_url, spec, attrs, phase) t262_load_module(ref_url, spec, attrs, phase)
  ast = has_agent ? T262AgentState.new : nil
  if ast != nil
    ast.mu.lock
    JS_AGENT_YIELD_HOOK[0] = ->(nap) ast.yield_turn(nap)
  else
    JS_AGENT_YIELD_HOOK[0] = nil
  sub_realms = []
  r = js_new_realm(host)
  js_task_begin()
  out = []
  t262_install_host(r, out, sub_realms, ast)
  if ast != nil && incs.include?("atomicsHelper.js")
    r.method(r.global, "setTimeout", 2, ->(this, args, nt) t262_set_timeout(ast, r, js_arg(args, 0), js_arg(args, 1)))
  err = nil
  mod_prom = nil
  begin
    if is_mod
      if neg != nil && neg[0] == "parse"
        js_check_module(src, path)
      else
        js_run_script(full) if !raw
        mod_prom = js_run_module(src, path)
    elsif !raw && neg == nil
      js_run_script(full)
      js_run_script(strict ? "\"use strict\";\n" + src : src)
    elsif neg != nil && neg[0] == "parse"
      ps = strict ? "\"use strict\";\n" + src : src
      wk_check(ps)
    else
      js_run_script(full) if !raw
      js_run_script(strict ? "\"use strict\";\n" + src : src)
    r.run_jobs
    # Pump async waiters, timers, and active agent workers until completion
    deadline = clock() + ~20.0
    while clock() < deadline
      done_now = is_async && out.select(->(l) l.starts_with?("Test262:Async")).size > 0
      js_wait_async_poll()
      fired = ast != nil ? ast.pump_timers() : false
      r.run_jobs
      break if done_now
      has_t = ast != nil && ast.timers.size > 0
      has_w = ast != nil && ast.active > 0
      break if js_wait_async_poll() == 0 && !has_t && !has_w && r.jobs.head == r.jobs.tail && !fired
      if ast != nil
        ast.yield_turn(~0.001)
      else
        sleep(~0.001)
    if mod_prom != nil && mod_prom.state == :rejected
      err = JS:Throw.new(mod_prom.value)
  rescue e
    err = e
  if ast != nil
    ast.shutdown()
    JS_AGENT_YIELD_HOOK[0] = nil
    ast.mu.unlock
  JS_WAITERS.clear
  sub_realms.each ->(sr) js_gc_remove_realm(sr)
  js_gc_remove_realm(r)
  if neg != nil
    return "FAIL " + rel + " expected " + neg[1] if err == nil
    v = err.is_a?(JS:Throw) ? err.value : nil
    nm = js_object?(v) ? js_to_string(jget(v, "name")) : "?"
    if nm == "undefined" && js_object?(v)
      ctor = jget(v, "constructor")
      nm = js_to_string(jget(ctor, "name")) if js_object?(ctor)
    return "PASS " + rel if nm == neg[1]
    return "FAIL " + rel + " got " + nm + " want " + neg[1]
  if err != nil
    msg = err.is_a?(JS:Throw) ? js_inspect(err.value, 1, []) : "internal: " + (err.is_a?(String) ? err : err.message.to_s)
    msg = msg.slice(0, 160) if msg.size > 160
    return "FAIL " + rel + " " + msg.sub("\n", " ")
  if is_async
    done = out.select(->(l) l.starts_with?("Test262:Async"))
    return "FAIL " + rel + " async: no $DONE" if done.size == 0
    return "PASS " + rel if done[0] == "Test262:AsyncTestComplete"
    return "FAIL " + rel + " " + done[0]
  "PASS " + rel

Process.memory_limit = (4294967296 ## int)
root = ARGV[0]
list = File.read(ARGV[1]).split("\n")
list.each ->(rel)
  if rel.strip.size > 0
    res = "FAIL " + rel + " runner"
    begin
      res = t262_run(root, rel.strip)
    rescue e
      res = "FAIL " + rel + " runner " + (e.is_a?(String) ? e : e.message.to_s)
    << res
    ccall("w_flush")
    ccall("w_flush")
