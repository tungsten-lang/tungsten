# Compile-time target detection and predicate matching for platform guards.

-> host_c_compiler
  cc = env("TUNGSTEN_CC")
  if cc == nil || cc == ""
    return "clang"
  cc

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

  features = detect_features(os)
  detect_target_memo[:target] = { os: os, arch: arch, features: features }
  detect_target_memo[:target]

-> detect_features(os)
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

  features

-> detect_llvm_target
  cc = host_c_compiler()
  # Cross-compilation: TUNGSTEN_TARGET (set by `--target=<triple>`) retargets
  # codegen. Probe the target's datalayout+triple by asking clang to lower an
  # empty TU FOR that triple — LLVM's codegen is fully retargetable. Host-
  # specific -march=native function attrs are dropped for a cross target (they
  # name the host CPU and would be wrong / rejected for another arch).
  cross = env("TUNGSTEN_TARGET")
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

  fn_attrs = ""
  if cross == nil || cross == ""
    fn_attrs = detect_host_fn_attrs()

  { datalayout: datalayout, triple: triple, fn_attrs: fn_attrs }

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
-> detect_host_fn_attrs
  cc = host_c_compiler()
  awk = "awk '/^attributes #0 / { for(i=1;i<=NF;i++){ "
  awk = awk + "if($i~/^\"target-cpu\"=/||$i~/^\"target-features\"=/||$i~/^\"tune-cpu\"=/) "
  awk = awk + "printf \"%s \", $i } print \"\" }'"
  # Match the march the binary is actually built with (TUNGSTEN_MARCH_ARGS, set
  # by tungsten.w's --release), so the target-features baked into every emitted
  # function are the portable baseline for a release build — not the host's
  # native features, which would defeat portability and mismatch the runtime.
  march = env("TUNGSTEN_MARCH_ARGS")
  if march == nil || march == ""
    march = "-march=native -mtune=native"
  script = "echo 'void __tungsten_probe(void){}' | " + cc
  script = script + " -O3 " + march + " -S -emit-llvm -xc - -o - 2>/dev/null | " + awk
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
          if ast_kind(inner) == :method_def
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
      if ast_kind(expr) == :method_def && guarded_names.has_key?(expr.name)
        nil
      else
        result.push(expr)

  result
