# Compile-time target detection and predicate matching for platform guards.

# Which C compiler drives the final .ll → binary step. Explicit TUNGSTEN_CC wins.
# Otherwise prefer a clang whose LLVM is >= 22 when one is installed: its loop
# vectorizer splits associative reductions (and vectorizes headerless-small-array
# reductions with natural alignment) where older clang's cost model declines —
# ~2.3x on such loops, matching rustc's LLVM 22. Falls back to plain `clang`
# (system default) when no newer clang is found, so other machines are unaffected.
host_cc_memo = {}

# Target layout/attribute probing shells out through clang twice. A compiler
# process normally targets one exact configuration for many files, so retain
# that answer in memory. The driver may additionally provide its compiler
# cache directory; native compilers then persist the checksummed answer for the
# current local civil day. The short lifetime deliberately bounds staleness
# for an auto-selected clang without running another subprocess merely to ask
# clang for its version before consulting the cache.
target_probe_cache_state = {
  entries: {},
  persistent_dir: nil,
  memory_hits: 0,
  disk_hits: 0,
  misses: 0,
  stores: 0,
  last_source: :none,
  native_memory_hits: 0,
  native_disk_hits: 0,
  native_misses: 0,
  native_stores: 0,
  last_native_source: :none
}

-> target_probe_cache_configure(dir)
  target_probe_cache_state[:persistent_dir] = dir
  nil

-> target_probe_cache_enabled?
  env("TUNGSTEN_TARGET_CACHE") != "0"

-> target_probe_disk_cache_enabled?
  target_probe_cache_state[:persistent_dir] != nil && env("TUNGSTEN_TARGET_DISK_CACHE") != "0" && runtime_identity() == "compiled-runtime"

-> target_probe_cache_field(value)
  text = value == nil ? "" : value.to_s()
  text.size().to_s() + ":" + text

-> target_probe_cache_key(cc, cross, march)
  text = StringBuffer(256)
  text << "target-probe-v1"
  text << target_probe_cache_field(cc)
  text << target_probe_cache_field(cross)
  text << target_probe_cache_field(march)
  text << target_probe_cache_field(env("TUNGSTEN_CC"))
  text << target_probe_cache_field(env("TUNGSTEN_TARGET"))
  text << target_probe_cache_field(env("TUNGSTEN_CPU"))
  text << target_probe_cache_field(env("TUNGSTEN_MARCH_ARGS"))
  text.to_s()

-> target_probe_cache_path(key)
  dir = target_probe_cache_state[:persistent_dir]
  if dir == nil
    return nil
  dir + "/target-probe-v1-" + wyhash64_hex_string(key) + ".twc"

-> target_probe_cache_today
  # A packed Date is an immediate WValue and is supported by the checksummed
  # compiler graph serializer. Comparing it directly gives the on-disk cache
  # a local-calendar-day lifetime without spawning `date` or adding a clock
  # conversion to the language surface.
  ccall("w_date_today")

-> target_probe_cache_entry_valid?(entry, key)
  type(entry) == "Hash" && entry[:version] == "target-probe-v1" && entry[:key] == key && entry[:day] == target_probe_cache_today() && type(entry[:datalayout]) == "String" && entry[:datalayout] != "" && type(entry[:triple]) == "String" && entry[:triple] != "" && type(entry[:fn_attrs]) == "String"

-> target_probe_cache_result(entry)
  {datalayout: entry[:datalayout], triple: entry[:triple], fn_attrs: entry[:fn_attrs]}

-> target_probe_cache_lookup(key)
  if !target_probe_cache_enabled?
    target_probe_cache_state[:last_source] = :disabled
    return nil
  entry = target_probe_cache_state[:entries][key]
  if entry != nil
    target_probe_cache_state[:memory_hits] = target_probe_cache_state[:memory_hits] + 1
    target_probe_cache_state[:last_source] = :memory
    return target_probe_cache_result(entry)
  if target_probe_disk_cache_enabled?
    path = target_probe_cache_path(key)
    loaded = ccall("w_core_cache_read", path)
    if target_probe_cache_entry_valid?(loaded, key)
      target_probe_cache_state[:entries][key] = loaded
      target_probe_cache_state[:disk_hits] = target_probe_cache_state[:disk_hits] + 1
      target_probe_cache_state[:last_source] = :disk
      return target_probe_cache_result(loaded)
  target_probe_cache_state[:misses] = target_probe_cache_state[:misses] + 1
  target_probe_cache_state[:last_source] = :miss
  nil

-> target_probe_cache_store(key, result)
  if !target_probe_cache_enabled? || result[:datalayout] == "" || result[:triple] == ""
    return result
  entry = {
    version: "target-probe-v1",
    key: key,
    day: target_probe_cache_today(),
    datalayout: result[:datalayout],
    triple: result[:triple],
    fn_attrs: result[:fn_attrs]
  }
  target_probe_cache_state[:entries][key] = entry
  if target_probe_disk_cache_enabled?
    path = target_probe_cache_path(key)
    if ccall("w_core_cache_write", path, entry) == true
      target_probe_cache_state[:stores] = target_probe_cache_state[:stores] + 1
  result

-> target_probe_cache_verbose_text
  source = target_probe_cache_state[:last_source]
  if source == :none
    return nil
  text = "  target probe cache: " + source.to_s() + " (" + target_probe_cache_state[:memory_hits].to_s() + " memory, " + target_probe_cache_state[:disk_hits].to_s() + " disk, " + target_probe_cache_state[:misses].to_s() + " misses)"
  native_source = target_probe_cache_state[:last_native_source]
  if native_source != :none
    text = text + "; native CPU " + native_source.to_s()
  text

-> target_homebrew_formula_prefix(formula)
  key = ("brew:" + formula).to_sym()
  cached = host_cc_memo[key]
  if cached != nil
    return cached
  prefix = capture("brew --prefix " + formula + " 2>/dev/null").strip()
  host_cc_memo[key] = prefix
  prefix

-> host_c_compiler
  cc = env("TUNGSTEN_CC")
  if cc != nil && cc != ""
    return cc
  cached = host_cc_memo[:cc]
  if cached != nil
    return cached
  chosen = "clang"
  candidates = ["clang-22"]
  ["llvm", "llvm@22"].each ->(formula)
    prefix = target_homebrew_formula_prefix(formula)
    if prefix != ""
      candidates.push(prefix + "/bin/clang")
  ci = 0
  while ci < candidates.size()
    c = candidates[ci]
    exists = capture("test -x \"" + c + "\" && echo y").strip()
    if exists == "y"
      ver = capture("\"" + c + "\" --version 2>/dev/null | head -1")
      # major >= 22: match "clang version 22." / 23. / … (two-digit majors)
      if ver.index("version 22.") != nil || ver.index("version 23.") != nil || ver.index("version 24.") != nil
        chosen = c
        ci = candidates.size()
    ci = ci + 1
  host_cc_memo[:cc] = chosen
  chosen

# `-mcpu=native` is only as good as the host clang's CPU detection, which
# lags new silicon: Xcode clang 21 and Homebrew LLVM 22 both resolve
# `native` to apple-m4 on an M5. Name the chip explicitly instead: when the
# brand string says M5 and the host compiler knows `apple-m5`, use that;
# otherwise approximate as apple-m4 plus the ISA features the M5 adds
# (each verified against `--print-supported-extensions`). Other chips keep
# plain `-mcpu=native`.
native_cpu_memo = {}

-> target_native_cpu_cache_key(cc)
  "native-arm-cpu-v1" + target_probe_cache_field(cc) + target_probe_cache_field(env("TUNGSTEN_CC"))

-> target_native_cpu_cache_path(key)
  dir = target_probe_cache_state[:persistent_dir]
  if dir == nil
    return nil
  dir + "/native-arm-cpu-v1-" + wyhash64_hex_string(key) + ".twc"

-> target_native_cpu_cache_entry_valid?(entry, key)
  type(entry) == "Hash" && entry[:version] == "native-arm-cpu-v1" && entry[:key] == key && entry[:day] == target_probe_cache_today() && type(entry[:flags]) == "String" && entry[:flags] != ""

-> target_native_cpu_cache_lookup(key)
  if !target_probe_cache_enabled?
    target_probe_cache_state[:last_native_source] = :disabled
    return nil
  entry = target_probe_cache_state[:entries][key]
  if target_native_cpu_cache_entry_valid?(entry, key)
    target_probe_cache_state[:native_memory_hits] = target_probe_cache_state[:native_memory_hits] + 1
    target_probe_cache_state[:last_native_source] = :memory
    return entry[:flags]
  if target_probe_disk_cache_enabled?
    loaded = ccall("w_core_cache_read", target_native_cpu_cache_path(key))
    if target_native_cpu_cache_entry_valid?(loaded, key)
      target_probe_cache_state[:entries][key] = loaded
      target_probe_cache_state[:native_disk_hits] = target_probe_cache_state[:native_disk_hits] + 1
      target_probe_cache_state[:last_native_source] = :disk
      return loaded[:flags]
  target_probe_cache_state[:native_misses] = target_probe_cache_state[:native_misses] + 1
  target_probe_cache_state[:last_native_source] = :miss
  nil

-> target_native_cpu_cache_store(key, flags)
  if !target_probe_cache_enabled? || flags == nil || flags == ""
    return flags
  entry = {version: "native-arm-cpu-v1", key: key, day: target_probe_cache_today(), flags: flags}
  target_probe_cache_state[:entries][key] = entry
  if target_probe_disk_cache_enabled?
    if ccall("w_core_cache_write", target_native_cpu_cache_path(key), entry) == true
      target_probe_cache_state[:native_stores] = target_probe_cache_state[:native_stores] + 1
  flags

-> native_arm_cpu_flags
  cached = native_cpu_memo[:flags]
  if cached != nil
    return cached
  cc = host_c_compiler()
  cache_key = target_native_cpu_cache_key(cc)
  cached = target_native_cpu_cache_lookup(cache_key)
  if cached != nil
    native_cpu_memo[:flags] = cached
    return cached
  flags = "-mcpu=native"
  target = detect_target()
  if target[:os] == "macos" && target[:arch] == "arm64"
    brand = capture("sysctl -n machdep.cpu.brand_string 2>/dev/null").strip()
    if brand.index("M5") != nil
      if host_cc_supports_mcpu?("apple-m5")
        flags = "-mcpu=apple-m5"
      else
        flags = "-mcpu=apple-m4+sme2p1+sme-f16f16+sme-b16b16+cssc+wfxt+hbc"
  native_cpu_memo[:flags] = target_native_cpu_cache_store(cache_key, flags)
  native_cpu_memo[:flags]

# A clean `-fsyntax-only` run prints nothing; an unknown -mcpu value is an
# error on both clang ("unsupported argument") and gcc ("unknown value").
-> host_cc_supports_mcpu?(cpu)
  cc = host_c_compiler()
  out = capture("\"" + cc + "\" -mcpu=" + cpu + " -fsyntax-only -x c /dev/null 2>&1")
  out.index("error") == nil

# LLVM's llvm.minimumnum/llvm.maximumnum intrinsics (IEEE-754-2019
# minimumNumber/maximumNumber: NaN treated as missing data) lower to single
# fminnm/fmaxnm instructions on AArch64. Probe by parsing+ISel'ing a module
# that calls the f64 form — an older host clang rejects it at parse with
# "unknown intrinsic", and the fused-pipeline reduce combine then keeps its
# boxed compare-select fallback. Memoized per process alongside the cc.
-> host_cc_supports_llvm_fminmaxnum?
  cached = host_cc_memo[:llvm_fminmaxnum]
  if cached != nil
    return cached == :yes
  cc = host_c_compiler()
  probe = "declare double @llvm.maximumnum.f64(double, double)\ndefine double @w_probe(double %a, double %b) {\n  %r = call double @llvm.maximumnum.f64(double %a, double %b)\n  ret double %r\n}\n"
  out = capture("printf %s '" + probe + "' | \"" + cc + "\" -x ir - -S -o /dev/null 2>&1")
  ok = out.index("error") == nil
  host_cc_memo[:llvm_fminmaxnum] = ok ? :yes : :no
  ok

# detect_target is called once per class definition and once per @on
# guard during lowering — 260+ times per compile of tungsten.w. Each
# uncached call spawns `uname -s` + `uname -m` subprocesses (~8ms each,
# ~2.2s per stage under the C VM bootstrap AND again in stage 2).
# The result is deterministic for the life of the process, so memoize.
# The cache is a top-level HASH mutated from inside the function —
# rebinding a top-level name from a function body does NOT write
# through in the compiled engine (it shadows locally), but mutating a
# container read from the global does.
detect_target_memo = {}

-> detect_target
  cached = detect_target_memo[:target]
  if cached != nil
    return cached
  os_raw = capture("uname -s").strip()
  arch_raw = capture("uname -m").strip()

  os = "unknown"

  case os_raw
  when "Darwin"
    os = "macos"
  when "Linux"
    os = "linux"
  when "FreeBSD"
    os = "freebsd"

  arch = "unknown"

  case arch_raw
  when "x86_64", "amd64"
    arch = "x86_64"
  when "arm64", "aarch64"
    arch = "arm64"

  features = detect_features(os, arch)
  detect_target_memo[:target] = { os: os, arch: arch, features: features }
  detect_target_memo[:target]

-> detect_features(os, arch)
  features = []

  if os == "linux"
    if file?("/proc/sys/kernel/io_uring_disabled") || file?("/proc/sys/kernel/io_uring_group")
      features.push("io_uring")

  # Keep in sync with target.rb detect_features — an `@on(metal)` guard must
  # resolve identically under the Ruby and compiled bootstraps or byte-identity
  # can drift.
  if os == "macos"
    if file?("/System/Library/Frameworks/Metal.framework/Metal")
      features.push("metal")

  # Feature guards describe the configured code-generation target, not just
  # the host CPU. `--native` resolves M5 explicitly before lowering Core;
  # explicit +cssc targets use the same capability. A generic `-mcpu=native`
  # may still resolve to apple-m4 in clang and therefore stays portable.
  if arch == "arm64"
    march = env("TUNGSTEN_MARCH_ARGS")
    if march != nil && (march.index("apple-m5") != nil || march.index("+cssc") != nil)
      features.push("cssc")

  features

-> detect_llvm_target
  cc = host_c_compiler()
  # Cross-compilation: TUNGSTEN_TARGET (set by `--target=<triple>`) retargets
  # codegen. Probe the target's datalayout+triple by asking clang to lower an
  # empty TU FOR that triple — LLVM's codegen is fully retargetable. When an
  # explicit --cpu accompanies it, the same probe stamps target-cpu/features
  # for that target rather than leaking host attributes.
  cross = env("TUNGSTEN_TARGET")
  march = target_probe_march(cross)
  cache_key = target_probe_cache_key(cc, cross, march)
  cached = target_probe_cache_lookup(cache_key)
  if cached != nil
    return cached
  tflag = ""
  if cross != nil && cross != ""
    tflag = " --target=" + cross
  awk = "awk -F'\"' '/target datalayout/ {print $2} /target triple/ {print $2}'"
  out = capture("echo '' | " + cc + tflag + " -x c - -emit-llvm -S -o - 2>/dev/null | " + awk)
  parts = out.replace("\r", "").split("\n")
  datalayout = ""
  triple = ""

  if parts.size() > 0
    datalayout = parts[0]

  if parts.size() > 1
    triple = parts[1]

  fn_attrs = detect_target_fn_attrs(cross, march)

  target_probe_cache_store(cache_key, { datalayout: datalayout, triple: triple, fn_attrs: fn_attrs })

# Ask clang what target-cpu / target-features / tune-cpu it would stamp
# on C code compiled with -march=native on this host, and return them as
# an LLVM function-attribute fragment. The emitter reuses this on every
# Tungsten function so LTO can inline runtime helpers (which carry the
# same attribute set from clang -march=native) into Tungsten-emitted
# code.
#
# Implementation: compile a 1-line empty probe through the real C→IR
# front end, then grep the `attributes #0 = { ... }` block for the
# target-cpu / target-features / tune-cpu keys. This captures the
# BACKEND-EXPANDED feature set (e.g. auto-added +v8.1a…+v8.6a from
# +v8.6a), which is what the runtime's functions will actually carry.
# The driver-level `clang -###` output is a subset and won't match.
-> target_probe_march(cross = nil)
  # Match the march the binary is actually built with. tungsten.w resolves the
  # profile/target flags into TUNGSTEN_MARCH_ARGS before lowering, so emitted
  # functions and the runtime use the same configured CPU feature set.
  march = env("TUNGSTEN_MARCH_ARGS")
  if march == nil || march == ""
    if cross == nil || cross == ""
      host_arch = capture("uname -m").strip()
      if host_arch == "x86_64" || host_arch == "amd64"
        march = "-march=native -mtune=native"
      else
        march = native_arm_cpu_flags()
  march

-> detect_target_fn_attrs(cross = nil, march = nil)
  cc = host_c_compiler()
  awk = "awk '/^attributes #0 / { for(i=1;i<=NF;i++){ "
  awk = awk + "if($i~/^\"target-cpu\"=/||$i~/^\"target-features\"=/||$i~/^\"tune-cpu\"=/) "
  awk = awk + "printf \"%s \", $i } print \"\" }'"
  if march == nil
    march = target_probe_march(cross)
  target_flag = ""
  if cross != nil && cross != ""
    target_flag = " --target=" + cross
  script = "echo 'void __tungsten_probe(void){}' | " + cc
  script = script + target_flag + " -O3 " + march + " -S -emit-llvm -xc - -o - 2>/dev/null | " + awk
  capture(script).strip()

-> normalize_designator(name)
  if name in ("amd64" "intel")
    return "x86_64"
  if name == "aarch64"
    return "arm64"
  name

-> evaluate_target_predicate(node, target)
  case ast_kind(node)
  when :target_designator
    name = normalize_designator(node.name)
    return target[:os] == name || target[:arch] == name
  when :target_and
    return evaluate_target_predicate(node.left, target) && evaluate_target_predicate(node.right, target)
  when :target_or
    return evaluate_target_predicate(node.left, target) || evaluate_target_predicate(node.right, target)
  when :target_not
    return !evaluate_target_predicate(node.expression, target)

  false

-> target_matches?(predicate, capabilities, target)
  if !evaluate_target_predicate(predicate, target)
    return false
  capabilities.size().times ->
    if !target[:features].include?(capabilities[i])
      return false

  true

-> expand_on_guards(body, target)
  # First pass: collect guarded method names, detect duplicates
  guarded_names = {}
  body.size().times ->
    expr = body[i]
    if ast_kind(expr) == :on_guard
      if target_matches?(expr.predicate, expr.capabilities, target)
        expr.body.size().times ->
          inner = expr.body[j]
          if ast_kind(inner) in (:method_def :fn_def)
            name = inner.name
            if guarded_names.has_key?(name)
              raise "ambiguous platform guard: multiple guarded definitions of '" + name + "' match the current target"
            guarded_names[name] = true

  # Second pass: inline matching guards, drop overridden fallbacks
  result = []
  body.size().times ->
    expr = body[i]
    if ast_kind(expr) == :on_guard
      if target_matches?(expr.predicate, expr.capabilities, target)
        expr.body.size().times ->
          result.push(expr.body[j])
    else
      if ast_kind(expr) in (:method_def :fn_def) && guarded_names.has_key?(expr.name)
        nil
      else
        result.push(expr)

  result
