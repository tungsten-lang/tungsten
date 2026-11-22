# Run a list of test262 tests: bin args are the test262 root and a file listing test paths
# (relative to test/). Prints one line per test: PASS|FAIL|SKIP path [reason], flushed, so
# a driver can resume after a crash or hang (tools/test262.py).

use ../engine

SKIP_FEATURES = ["Temporal", "ShadowRealm", "decorators", "tail-call-optimization", "import-defer", "source-phase-imports", "explicit-resource-management", "Atomics.waitAsync", "Atomics.pause", "regexp-modifiers", "IsHTMLDDA", "cross-realm", "json-parse-with-source", "Math.sumPrecise", "upsert", "immutable-arraybuffer", "nonextensible-applies-to-private", "canonical-tz", "Intl.DurationFormat", "Intl.Locale-info", "uint8array-base64", "iterator-sequencing", "joint-iteration", "await-dictionary", "symbols-as-weakmap-keys"]

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
  src.slice(a + 5, b - a - 5)

# Values of a YAML list key: "key: [a, b]" or a block list.
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
  phase = fm.slice(ph + 6, fm.index("\n", ph) - ph - 6).strip
  type = fm.slice(ty + 5, fm.index("\n", ty) - ty - 5).strip
  [phase, type]

HARNESS = {}

-> t262_harness(root, name)
  h = HARNESS[name]
  if h == nil
    h = File.read(root + "/harness/" + name)
    HARNESS[name] = h
  h

-> t262_install_host(r, out)
  g = r.global
  r.method(g, "print", 1, ->(this, args, nt) out.push(js_to_string(js_arg(args, 0))))
  d = r.new_object
  g.define("$262", d, BUILTIN_ATTRS)
  d.define("global", g, BUILTIN_ATTRS)
  r.method(d, "evalScript", 1, ->(this, args, nt) js_run_script(js_to_string(js_arg(args, 0))))
  r.method(d, "gc", 0, ->(this, args, nt) nil)
  r.method(d, "detachArrayBuffer", 1, ->(this, args, nt) js_detach_buffer(js_arg(args, 0)))
  r.method(d, "createRealm", 0, ->(this, args, nt) js_throw_type("createRealm unsupported"))
  ag = r.new_object
  d.define("agent", ag, BUILTIN_ATTRS)
  nil

-> t262_run(root, rel)
  path = root + "/test/" + rel
  src = File.read(path)
  fm = t262_frontmatter(src)
  flags = t262_list(fm, "flags")
  feats = t262_list(fm, "features")
  feats.each ->(f)
    return "SKIP " + rel + " feature " + f if SKIP_FEATURES.include?(f)
  return "SKIP " + rel + " module" if flags.include?("module")
  return "SKIP " + rel + " CanBlockIsTrue" if flags.include?("CanBlockIsTrue")
  neg = t262_negative(fm)
  strict = flags.include?("onlyStrict")
  raw = flags.include?("raw")
  is_async = flags.include?("async")
  sb = StringBuffer()
  if !raw
    sb.append("\"use strict\";\n") if strict
    sb.append(t262_harness(root, "assert.js"))
    sb.append("\n")
    sb.append(t262_harness(root, "sta.js"))
    sb.append("\n")
    if is_async
      sb.append(t262_harness(root, "doneprintHandle.js"))
      sb.append("\n")
    t262_list(fm, "includes").each ->(inc)
      sb.append(t262_harness(root, inc))
      sb.append("\n")
  full = sb.to_s
  host = T262Host.new
  r = js_new_realm(host)
  JS_UNHANDLED.clear
  out = []
  t262_install_host(r, out)
  err = nil
  begin
    if !raw && neg == nil
      js_run_script(full)
      js_run_script(strict ? "\"use strict\";\n" + src : src)
    elsif neg != nil && neg[0] == "parse"
      # parse phase = parsing plus early errors (found while compiling); nothing runs
      ps = strict ? "\"use strict\";\n" + src : src
      JsCompiler.new(ps).compile_script(js_parse_or_throw(ps, false))
    else
      js_run_script(full) if !raw
      js_run_script(strict ? "\"use strict\";\n" + src : src)
    r.run_jobs
  rescue e
    err = e
  if neg != nil
    return "FAIL " + rel + " expected " + neg[1] if err == nil
    v = err.is_a?(JsThrow) ? err.value : nil
    nm = v.is_a?(JsObject) ? js_to_string(v.get("name", v)) : "?"
    return "PASS " + rel if nm == neg[1]
    return "FAIL " + rel + " got " + nm + " want " + neg[1]
  if err != nil
    msg = err.is_a?(JsThrow) ? js_inspect(err.value, 1, []) : "internal: " + err.message.to_s
    msg = msg.slice(0, 160) if msg.size > 160
    return "FAIL " + rel + " " + msg.sub("\n", " ")
  if is_async
    done = out.select(->(l) l.starts_with?("Test262:Async"))
    return "FAIL " + rel + " async: no $DONE" if done.size == 0
    return "PASS " + rel if done[0] == "Test262:AsyncTestComplete"
    return "FAIL " + rel + " " + done[0]
  "PASS " + rel

root = ARGV[0]
list = File.read(ARGV[1]).split("\n")
list.each ->(rel)
  if rel.strip.size > 0
    res = "FAIL " + rel + " runner"
    begin
      res = t262_run(root, rel.strip)
    rescue e
      res = "FAIL " + rel + " runner " + e.message.to_s
    << res
    ccall("w_flush")
