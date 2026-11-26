# blade/jsn/unitcache — compiled units for page scripts (the js-aot engine's tier 1).
#
# When a script of at least JSU_MIN bytes runs, its functions are compiled to units in
# the background, JSU_WINDOW functions per unit (one compile of youtube-main's 47,000
# functions would need more than 16 GB), by the js-aot compiler (BLADE_JSC, with the
# js-aot tree at BLADE_JSAOT_ROOT): translate/unit.w's output, clang -O2 -c. Units are
# kept in ~/Library/Caches/Blade/js-units/ by the script's SHA-256 and the unit ABI, so a
# later visit loads them before the script's first statement runs. A unit that arrives
# while the page runs is loaded at the next task boundary (js_task_begin): calls from
# then on go native; activations already running finish in tier 0.
#
#   BLADE_JS_ENGINE=tier0     no units (tier 0 only); the default is aot
#   BLADE_JS_UNITS_SYNC=1     build a script's units before it runs (tests)
#   BLADE_JS_UNITS_DEBUG=1    log builds and loads
#   BLADE_JS_UNITS_JOBS=n     unit builds at once (default 1)

JSU_ON = [Env.get("BLADE_JS_ENGINE", "aot") != "tier0" && Env.get("BLADE_JS_UNITS", "0") == "1"]
JSU_SYNC = [Env.get("BLADE_JS_UNITS_SYNC", "") == "1"]
JSU_DEBUG = [Env.get("BLADE_JS_UNITS_DEBUG", "") == "1"]
JSU_MIN = [4096]
JSU_WINDOW = [2000]
# functions longer than this many bytes of source stay in tier 0 (a few machine-made
# wrappers of 100 KB and more take gigabytes to compile)
JSU_MAXSIZE = [100000]
# builds at once (each a compiler process of about 1.2 GB; BLADE_JS_UNITS_JOBS)
JSU_PARALLEL = [Env.get("BLADE_JS_UNITS_JOBS", "1").to_i < 1 ? 1 : Env.get("BLADE_JS_UNITS_JOBS", "1").to_i]
JSU_SCRIPTS = []
JSU_BUILDING = [0]

+ JsuShard
  rw :base, :skip, :state, :result, :thread
  -> new(@base, @skip)
    @state = :missing
    @result = nil
    @thread = nil

+ JsuScript
  rw :sha, :url, :codes, :shards, :src_path
  -> new(@sha, @url, @codes)
    @shards = []
    @src_path = nil

-> jsu_dir
  Env.get("HOME", "/tmp") + "/Library/Caches/Blade/js-units"

-> jsu_root
  r = Env.get("BLADE_JSAOT_ROOT", "")
  r.size > 0 ? r : Env.get("HOME", "/tmp") + "/tungsten-worktrees/js-aot"

-> jsu_jsc
  j = Env.get("BLADE_JSC", "")
  j.size > 0 ? j : jsu_root() + "/languages/js-aot/build/jsc"

-> jsu_cc
  cs = ["/opt/homebrew/opt/llvm/bin/clang", "/usr/bin/clang"]
  i = 0
  while i < cs.size
    return cs[i] if File.exist?(cs[i])
    i += 1
  nil

# A script is about to run (tier 0's WK_PRE_RUN): load its units, or start building them.
-> jsu_on_script(an)
  return nil if !JSU_ON[0] || an.src == nil || an.src.size < JSU_MIN[0]
  return nil if !File.exist?(jsu_jsc()) || jsu_cc() == nil
  sha = Crypto.sha256(an.src)
  codes = an.funcs.map(->(jf) wk_code(jf))
  s = JsuScript.new(sha, an.url, codes)
  # windows over the functions the translator supports
  n = 0
  an.funcs.each ->(jf) n += 1 if jf.unsupported == nil && !jf.script && jf.node.fin - jf.node.pos <= JSU_MAXSIZE[0]
  dir = jsu_dir()
  k = 0
  while k * JSU_WINDOW[0] < n || k == 0
    s.shards.push(JsuShard.new(dir + "/" + sha.slice(0, 40) + "-" + JSU_ENGINE_ID + "-w" + JSU_WINDOW[0].to_s + "-" + k.to_s, k * JSU_WINDOW[0]))
    k += 1
  # Skip background builds for data-only/one-shot inline scripts (< 3 reusable functions)
  # unless a cached unit already exists or synchronous test mode is on.
  can_build = JSU_SYNC[0] || n >= 3
  s.src_path = dir + "/" + sha.slice(0, 40) + ".js"
  if can_build && s.shards.any?(->(sh) !File.exist?(sh.base + ".json"))
    File.mkdir_p(dir) if !Dir.exist?(dir)
    File.write(s.src_path, an.src) if !File.exist?(s.src_path)
  loaded_or_pending = false
  s.shards.each ->(sh)
    if File.exist?(sh.base + ".o") && File.exist?(sh.base + ".json")
      jsu_load(s, sh)
      loaded_or_pending = true
    elsif JSU_SYNC[0]
      jsu_build(s, sh)
      jsu_load(s, sh) if sh.state == :built
      loaded_or_pending = true
    elsif can_build
      sh.state = :pending
      loaded_or_pending = true
  JSU_SCRIPTS.push(s) if loaded_or_pending
  jsu_poll() if !JSU_SYNC[0] && loaded_or_pending
  nil

-> jsu_load(s, sh)
  u = js_unit_load(sh.base + ".o", File.read(sh.base + ".json"), s.codes)
  if u.is_a?(String)
    sh.state = :failed
    ccall("w_eputs", "\[js units] not loaded (" + u + "): " + s.url.to_s.slice(0, 100)) if JSU_DEBUG[0]
    return nil
  sh.state = :loaded
  ccall("w_eputs", "\[js units] loaded " + u.nentries.to_s + " entries of " + s.url.to_s.slice(0, 100)) if JSU_DEBUG[0]
  nil

# Install finished builds and start pending ones (a task boundary: js_task_begin).
-> jsu_poll
  return nil if JSU_SCRIPTS.size == 0
  JSU_SCRIPTS.each ->(s)
    s.shards.each ->(sh)
      if sh.state == :building && sh.result != nil
        JSU_BUILDING[0] -= 1
        sh.state = sh.result ? :built : :failed
        jsu_load(s, sh) if sh.state == :built
      if sh.state == :pending && JSU_BUILDING[0] < JSU_PARALLEL[0]
        JSU_BUILDING[0] += 1
        sh.state = :building
        sh.thread = Thread.new ->
          jsu_build(s, sh)
  nil

# Build one unit: the compiler, then clang, then publish under the final names (renames,
# the manifest last, so a reader never sees half a unit).
-> jsu_build(s, sh)
  t0 = clock_ms()
  tmp = sh.base + ".tmp" + clock_ms().to_s
  root = jsu_root()
  cmd = "TUNGSTEN_ROOT='" + root + "' TUNGSTEN_INCREMENTAL=0 TUNGSTEN_SHARD_CODEGEN=0 TUNGSTEN_MEMORY_LIMIT=4G"
  cmd = cmd + " TUNGSTEN_LL_PATH='" + tmp + ".ll' JSC_JS='" + s.src_path + "' JSC_UNIT='" + tmp + ".json'"
  cmd = cmd + " JSC_LIMIT=" + JSU_WINDOW[0].to_s + " JSC_SKIP=" + sh.skip.to_s + " JSC_MAXSIZE=" + JSU_MAXSIZE[0].to_s
  cmd = cmd + " '" + jsu_jsc() + "' compile --emit-ll '" + root + "/languages/js-aot/unit/prelude.w' -o '" + tmp + ".bin' >'" + tmp + ".log' 2>&1"
  ok = OS.system(cmd)
  ok = ok == true || ok == 0
  if ok
    # (the unit's method-call inline caches become plain globals: the in-memory loader
    # takes no thread-local relocations, and a unit runs on the page's JS thread)
    OS.system("sed -i '' 's/ = internal thread_local global / = internal global /' '" + tmp + ".ll'")
    st = OS.system("'" + jsu_cc() + "' -O2 -fno-asynchronous-unwind-tables -c '" + tmp + ".ll' -o '" + tmp + ".o' 2>>'" + tmp + ".log'")
    ok = st == true || st == 0
  if ok
    File.rename(tmp + ".o", sh.base + ".o")
    File.rename(tmp + ".json", sh.base + ".json")
    if !JSU_DEBUG[0]
      File.rm(tmp + ".ll") if File.exist?(tmp + ".ll")
      File.rm(tmp + ".log") if File.exist?(tmp + ".log")
  else
    # Always clean up temporary files on failure so js-units doesn't leak GBs of .tmp leftovers
    File.rm(tmp + ".ll") if File.exist?(tmp + ".ll")
    File.rm(tmp + ".o") if File.exist?(tmp + ".o")
    File.rm(tmp + ".json") if File.exist?(tmp + ".json")
    File.rm(tmp + ".log") if !JSU_DEBUG[0] && File.exist?(tmp + ".log")
  File.rm(tmp + ".bin.sidemap") if File.exist?(tmp + ".bin.sidemap")
  File.rm(tmp + ".ll.done") if File.exist?(tmp + ".ll.done")
  ccall("w_eputs", "\[js units] " + (ok ? "built" : "build failed (" + tmp + ".log)") + " window " + sh.skip.to_s + " in " + (clock_ms() - t0).to_s + " ms: " + s.url.to_s.slice(0, 100)) if JSU_DEBUG[0]
  sh.state = :built if JSU_SYNC[0] && ok
  sh.result = ok
  nil
