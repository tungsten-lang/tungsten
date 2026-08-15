
-> runtime_event_source
  cached = env("TUNGSTEN_OS")
  if cached != nil && cached != ""
    os = cached
  else
    os = capture("uname -s").strip()

  if os == "Darwin"
    return "event_kqueue.c"
  elsif os == "Linux"
    use_uring = env("USE_IOURING")

    if use_uring != nil && use_uring != ""
      return "event_iouring.c"
    return "event_epoll.c"
  return "event_*.c"

-> extra_c_includes
  raw = env("TUNGSTEN_C_INCLUDES")

  if raw == nil || raw == ""
    return []

  parts = raw.split(":")
  out = []

  parts -> (part)
    out.push(part) if part != ""

  out

# Resolve the runtime/ directory.
# First checks if "runtime/" exists relative to CWD (works during bootstrap).
# Otherwise resolves relative to the compiler binary's install location.
-> resolve_runtime_dir
  if file?("runtime/runtime.c")
    return "runtime/"
  root = env("TUNGSTEN_ROOT")
  if root != nil && root != "" && file?(root + "/runtime/runtime.c")
    return root + "/runtime/"
  ccall("w_runtime_dir")

# CPU names accepted by --cpu are passed to clang command strings, so keep the
# allowed alphabet deliberately small. LLVM target names such as apple-m5,
# neoverse-v2, znver5, and x86-64-v3 all fit this set.
-> cpu_name_safe?(name)
  if name == nil || name == ""
    return false
  chars = name.chars()
  i = 0
  while i < chars.size()
    ch = chars[i]
    alpha = (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z")
    digit = ch >= "0" && ch <= "9"
    if !alpha && !digit && ch != "-" && ch != "_" && ch != "." && ch != "+"
      return false
    i += 1
  true

-> normalize_cpu_name(name)
  normalized = name.downcase()
  if normalized == "v1"
    return "x86-64-v1"
  if normalized == "v2"
    return "x86-64-v2"
  if normalized == "v3"
    return "x86-64-v3"
  if normalized == "v4"
    return "x86-64-v4"
  normalized

-> cpu_flags(name)
  normalized = normalize_cpu_name(name)
  if normalized in ("x86-64-v1" "x86-64-v2" "x86-64-v3" "x86-64-v4")
    return "-march=" + normalized + " -mtune=generic"
  if normalized == "native" && detect_target()[:arch] == "x86_64"
    return "-march=native -mtune=native"
  if normalized == "native"
    return native_arm_cpu_flags()
  "-mcpu=" + normalized

# CPU/tuning flags for the C compiler. Target resolution sets
# TUNGSTEN_MARCH_ARGS so link, runtime compile, and the target-features probe
# (target.w) all agree. Default: host-tuned native (`-mcpu=native` on Arm).
# is a post-.ll clang flag, so this never affects the stage1==stage2 identity.
-> march_flags
  m = env("TUNGSTEN_MARCH_ARGS")
  if m != nil && m != ""
    return m
  ""

-> profile_opt_flag
  if dev_mode
    return "-O0"
  "-O3"

-> debug_compile_flag
  if debug_enabled
    return "-g"
  "-DNDEBUG"

-> cross_compile_flags
  flags = ""
  if cross_target != ""
    flags = flags + "--target=" + cross_target + " "
  if cross_sysroot != ""
    flags = flags + "--sysroot=" + dev_runtime_shell_quote(cross_sysroot) + " "
  flags

-> http2_ldflags
  if cross_target != ""
    flags = env("TUNGSTEN_CROSS_HTTP2_LDFLAGS")
    return flags == nil ? "" : flags
  flags = env("TUNGSTEN_HTTP2_LDFLAGS")
  flags == nil ? "" : flags

-> link_binary(ll_path, out_path, runtime_objs, verbose = false)
  ll_probe_text = read_file(ll_path)
  compiler_image_runtime_profile = ll_code_has(ll_probe_text, "@w_compiler_image_lean_profile(")
  dynamic_exports_needed = ll_needs_dynamic_exports(ll_probe_text)
  bridges_needed = ll_needs_apple_bridges(ll_probe_text)
  blas_needed = ll_needs_blas(ll_probe_text)
  sparse_needed = ll_needs_sparse(ll_probe_text)
  sci_io_needed = ll_needs_sci_io(ll_probe_text)
  wtensor_needed = ll_needs_wtensor(ll_probe_text)
  cuda_needed = ll_needs_cuda(ll_probe_text)
  mlx_needed = ll_needs_mlx(ll_probe_text)
  # Data-table gating (weak twins in runtime.c make absence safe):
  #   prime    → ssmr_witness.c (512KB witness table; absent = exact 4-base
  #              fallback over its range)
  #   lexchars → lexchar_tables.c (348KB SIMD-lexer tables; absent = clear
  #              raise if ever reached)
  prime_needed = ll_code_has(ll_probe_text, "@w_prime_") || ll_code_has(ll_probe_text, "@w_primes_") || ll_code_has(ll_probe_text, "@w_bigint_prime")
  # The String API is `.lchs`; direct lexchars runtime calls are covered too.
  lexchars_needed = ll_needs_lexchars(ll_probe_text)
  unicode_needed = ll_needs_unicode(ll_probe_text)
  link_started_at = clock
  needs_zstd = ll_needs_zstd_text(ll_probe_text)
  # LTO is opt-in: whole-program LTO (lean binary, slow link) only for
  # --release / --lto; the default is a target-matched object runtime
  # archive (fatter binary, ~0.1s link vs ~5s recompiling the C runtime).
  doing_lto = (release_mode || explicit_lto) && !no_lto
  # Fast native-archive link (default): reuse the cached runtime objects
  # rather than recompiling the ~28k-line runtime every build. runtime.o's weak
  # companion stubs keep the gated ssmr/lexchar/metal/blas adds below valid.
  # Configs the shared archive can't represent (cross-target and zstd) fall
  # through to the from-source path. Frame-pointer mode is part of the archive
  # flags and identity, so debug builds can reuse it without losing backtraces.
  if runtime_objs == nil && !doing_lto && cross_target == "" && !needs_zstd
    runtime_objs = dev_runtime_archive(verbose)
  clang_opt = env("TUNGSTEN_CLANG_OPT")
  if clang_opt == nil || clang_opt == ""
    # --dev: clang -O0 on the emitted module. Measured on the self-hosted
    # compiler: link 19.5s -> 5.2s (-O1 is no cheaper than -O3's 18s; only
    # -O0 skips the expensive passes), full build 2.8x faster, produced
    # binary ~2.2x slower — the right trade for edit-test loops. Its
    # separately keyed runtime archive uses the same -O0 profile.
    clang_opt = dev_mode ? "-O0" : "-O3"

  # The source/output-path incremental cache runs before lowering. This second
  # cache sits at the other end of the pipeline: if two builds emit identical
  # LLVM under the same complete link contract, reuse the already linked
  # executable without introducing an object/LTO boundary. This catches a new
  # -o path, comment-only edits, and identical release batch entries. Arbitrary
  # user C includes are deliberately ineligible because their transitive header
  # graph is opaque to this driver.
  link_cache_slot = nil
  if doing_lto || env("TUNGSTEN_LINK_CACHE") == "1"
    link_cache_slot = link_artifact_cache_slot(ll_probe_text, runtime_objs, needs_zstd)
  if link_cache_slot != nil && link_artifact_cache_try_reuse(link_cache_slot, out_path)
    if verbose
      << fmt_elapsed(phase_elapsed(link_started_at)) + " clang (link cache)"
    return true

  # Parallel codegen — OPT-IN via TUNGSTEN_PARALLEL_CODEGEN=1. -O3 on one
  # big module is single-threaded and ~90% of a large build's wall; with
  # homebrew LLVM present, llvm-split the module ~14 ways and compile the
  # parts with parallel clang -c (self-compile codegen 13.5s -> ~5s, -o
  # wall 23.5s -> 17.2s). NOT the default: the parts must be compiled by
  # HOMEBREW clang (Apple clang can't read llvm-split's newer bitcode, and
  # its textual IR carries newer-only attributes), and brew LLVM 22's
  # arm64 codegen measured 1.54x MORE instructions on nbody's hot fp loop
  # than Apple clang on identical IR — a silent runtime-quality trade is
  # unacceptable, so the build-speed win is explicit. Any failure falls
  # back to the single-TU path. Plain -O3 native builds only (dev -O0
  # doesn't need it; PGO must not mix brew instrumentation with Apple's
  # profile runtime).
  parallel_objs = nil
  if clang_opt == "-O3" && cross_target == "" && !doing_lto && !frame_pointers && env("TUNGSTEN_PARALLEL_CODEGEN") == "1"
    parallel_objs = parallel_codegen_objects(ll_path, verbose)

  clang_cmd = StringBuffer(0)
  clang_cmd << host_c_compiler()
  clang_cmd << " "
  clang_cmd << clang_opt
  clang_cmd << " "
  clang_cmd << debug_compile_flag()
  clang_cmd << " "
  # CPU is an independent target axis. For cross builds, an explicit --cpu is
  # applied alongside --target; without one march_flags() is intentionally empty.
  if march_flags() != ""
    clang_cmd << march_flags()
    clang_cmd << " "
  clang_cmd << " -fmerge-all-constants "

  if doing_lto
    clang_cmd << (release_mode ? "-flto=full " : "-flto ")

  if frame_pointers
    clang_cmd << "-fno-omit-frame-pointer "

  # A compiler launcher carries an explicit, no-op marker in its emitted IR.
  # When this link owns the runtime compilation, turn that marker into a C
  # reachability profile: optional product dispatch roots are omitted and
  # FullLTO can discard the now-unreferenced implementation regions. Runtime
  # archives remain the universal profile because one archive may serve a
  # mixed compile-batch.
  if compiler_image_runtime_profile && runtime_objs == nil
    clang_cmd << "-DTUNGSTEN_RUNTIME_COMPILER_IMAGE=1 "

  # ld64 (macOS) vs GNU/lld (Linux): -dead_strip and -stack_size are ld64-only;
  # GNU ld also can't read LTO-bitcode archives, so Linux links through lld.
  # -export_dynamic/-rdynamic is restricted to JIT hosts. Ordinary standalone
  # programs have no dynamic ABI; keeping every runtime symbol visible both
  # bloats their export table and prevents FullLTO from internalizing dead
  # runtime entry points. The --jit/--hot compiler host is detected from its
  # emitted call to w_jit_load_object, and TUNGSTEN_DYNAMIC_EXPORTS=1 is the
  # explicit embedding-host override.
  if cross_target != ""
    clang_cmd << cross_compile_flags()
  if cross_target != "" && detect_target()[:os] != "macos"
    # Cross-link an ELF target through lld. The sysroot supplies its libc,
    # crt objects, and system libraries.
    clang_cmd << "-fuse-ld=lld -Wl,--gc-sections "
    if dynamic_exports_needed
      clang_cmd << "-rdynamic "
  elsif detect_target()[:os] == "macos"
    # -fveclib: the LLVM loop vectorizer may replace scalar libm calls in
    # vectorizable loops (e.g. the compiler's fused elementwise loops) with
    # libsystem_m's NEON SIMD variants (_simd_sin_d2 & co). Post-.ll clang
    # flag — never affects stage1==stage2 identity. Linux is left alone:
    # libmvec coverage varies by glibc version/arch and a missing _ZGV*
    # symbol would break the link.
    clang_cmd << "-fveclib=Darwin_libsystem_m "
    clang_cmd << "-Wl,-dead_strip -Wl,-stack_size,0x8000000 "
    if dynamic_exports_needed
      clang_cmd << "-Wl,-export_dynamic "
    else
      # Native runtime archives contain ordinary external C symbols. Restrict
      # the executable's export trie even when there is no LTO internalizer;
      # this does not change resolution among objects in the final link.
      clang_cmd << "-Wl,-exported_symbol,_main "
  else
    clang_cmd << "-fuse-ld=lld -Wl,--gc-sections "
    if dynamic_exports_needed
      clang_cmd << "-rdynamic "

  ocf = onig_cflags
  if ocf != ""
    clang_cmd << ocf
    clang_cmd << " "

  tcf = tls_cflags
  if tcf != ""
    clang_cmd << tcf
    clang_cmd << " "

  if needs_zstd && runtime_objs == nil
    zcf = zstd_cflags

    if zcf != ""
      clang_cmd << zcf
      clang_cmd << " "

  # -I the runtime dir whenever this invocation compiles any C/ObjC source:
  # the gated companions (ssmr/metal/…) and any bit C includes below still
  # #include runtime.h and need the header search path. A pure link against
  # the native archive compiles nothing, and clang warns on the unused -I.
  runtime_dir = resolve_runtime_dir
  target_os = detect_target()[:os]
  compiles_c = runtime_objs == nil || prime_needed || lexchars_needed || unicode_needed || sci_io_needed || wtensor_needed || extra_c_includes.size() > 0
  if target_os == "macos" && (blas_needed || sparse_needed || bridges_needed)
    compiles_c = true
  if target_os == "linux" && blas_needed
    compiles_c = true
  if compiles_c
    clang_cmd << "-I"
    clang_cmd << runtime_dir
    clang_cmd << " "
  if runtime_objs != nil
    clang_cmd << runtime_objs
    clang_cmd << " "
  else
    clang_cmd << runtime_dir
    clang_cmd << "runtime.c "

    clang_cmd << runtime_dir
    clang_cmd << "terminal_input.c "

    clang_cmd << runtime_dir
    clang_cmd << runtime_event_source

    clang_cmd << " "
    clang_cmd << runtime_dir
    clang_cmd << "aks.c "

    clang_cmd << runtime_dir
    clang_cmd << tls_runtime_source()
    clang_cmd << " "

    if needs_zstd
      clang_cmd << runtime_dir
      clang_cmd << zstd_runtime_source()
      clang_cmd << " "

  # Gated companions apply on BOTH runtime paths (sources above, or a cached
  # archive via runtime_objs). They MUST be passed as explicit sources here:
  # runtime.o carries weak stand-ins for all of them, and a weak definition
  # satisfies the linker, so it never pulls the strong archive member — an
  # archive can not override a weak symbol. (Learned the hard way: stage 2
  # could not lex its own source.)
  gated_dir = resolve_runtime_dir
  if prime_needed
    clang_cmd << gated_dir
    clang_cmd << "ssmr_witness.c "
  if lexchars_needed
    clang_cmd << gated_dir
    clang_cmd << "lexchar_tables.c "
  if unicode_needed
    clang_cmd << gated_dir
    clang_cmd << "unicode_tables.c "
  if detect_target()[:os] == "macos"
    if blas_needed
      clang_cmd << gated_dir
      clang_cmd << "blas_bridge.c "
    if sparse_needed
      clang_cmd << gated_dir
      clang_cmd << "sparse_bridge.c "
    if mlx_needed
      mlx_inc = mlx_cflags()
      if mlx_inc == ""
        raise "this program uses MLX (w_mlx_* / bf16 conversion) but mlx-c is not installed — brew install mlx mlx-c"
      clang_cmd << gated_dir
      clang_cmd << "mlx_bridge.c "
      clang_cmd << mlx_inc
      clang_cmd << " "
    if bridges_needed
      clang_cmd << gated_dir
      clang_cmd << "metal.m "
      clang_cmd << gated_dir
      clang_cmd << "graphics.m "
      clang_cmd << gated_dir
      clang_cmd << "hid_bridge.m "
  # Pure-C sci I/O (no system HDF5/NetCDF/Arrow) — all platforms.
  if sci_io_needed
    clang_cmd << gated_dir
    clang_cmd << "sci_io_native.c "
  if wtensor_needed
    clang_cmd << gated_dir
    clang_cmd << "tensor_bridge.c "
  if detect_target()[:os] == "linux"
    if blas_needed
      # Portable CBLAS (OpenBLAS). Requires libopenblas-dev (or equivalent).
      clang_cmd << gated_dir
      clang_cmd << "openblas_bridge.c "
  # CUDA host bridge: only when IR needs it and nvcc is available.
  # Linking .cu is done via a separate nvcc step when TUNGSTEN_CUDA=1.
  if cuda_needed
    # Named launch still uses weak stubs unless the user links
    # runtime/cuda_bridge.cu via nvcc (see doc/scientific-computing/cuda.md).
    # Device availability reports 0 without the bridge — that is intentional.
    cuda_needed = cuda_needed

  includes = extra_c_includes

  includes -> clang_cmd << inc + " "

  if parallel_objs != nil
    clang_cmd << parallel_objs
  else
    clang_cmd << ll_path

  if needs_zstd
    zlf = zstd_ldflags

    if zlf != ""
      clang_cmd << " "
      clang_cmd << zlf

  olf = onig_ldflags
  if olf != ""
    clang_cmd << " "
    clang_cmd << olf

  h2lf = http2_ldflags
  if h2lf != ""
    clang_cmd << " "
    clang_cmd << h2lf

  tlf = tls_ldflags
  if tlf != ""
    clang_cmd << " "
    clang_cmd << tlf

  if cross_target == ""
    mif = mimalloc_link_flags()
    if mif != ""
      clang_cmd << " "
      clang_cmd << mif

  # Framework links. Accelerate links only when the IR references
  # @w_blas_ / @w_sparse_ (blas_needed || sparse_needed below — runtime.c
  # carries weak raising stubs otherwise); everything else only when the
  # bridges are linked — "harmless" turned out to cost ~1.5ms warm and most
  # of the first-run dyld closure on every plain CLI binary.
  if detect_target()[:os] == "macos"
    if bridges_needed
      clang_cmd << " -framework Metal -framework Foundation -framework AppKit -framework QuartzCore -framework CoreGraphics -framework IOKit -framework CoreFoundation"
    if blas_needed || sparse_needed
      clang_cmd << " -framework Accelerate"
    if mlx_needed
      clang_cmd << " "
      clang_cmd << mlx_ldflags()
      clang_cmd << " -framework Metal -framework Foundation"

  # Linux: libm is a separate library (macOS bundles it into libSystem), and
  # it must follow the objects that reference it.
  if detect_target()[:os] == "linux"
    clang_cmd << " -lm"
    if blas_needed
      clang_cmd << " -lopenblas"

  clang_cmd << " -o "
  clang_cmd << out_path
  result = system(clang_cmd.to_s())
  log_phase(verbose, "clang", link_started_at)
  # Warm macOS's first-exec malware-scan cache now rather than on the user's
  # first run (see w_preflight in runtime/runtime.c): exec the fresh binary
  # detached with TUNGSTEN_PREFLIGHT set; it exits at the top of main.
  on macos
    if result == true
      system("TUNGSTEN_PREFLIGHT=1 " + dev_runtime_shell_quote(out_path) + " </dev/null >/dev/null 2>&1 &")
  if result == true && link_cache_slot != nil
    link_artifact_cache_store(link_cache_slot, out_path)
  result == true

# Persistent NATIVE-object runtime archive for fast dev links. Linking against
# this skips recompiling the ~28k-line C runtime on every build (~5s -> ~0.1s).
# runtime.o keeps weak stubs for the gated companions, so link_binary still adds
# the strong ssmr/lexchar/metal/blas sources when a program needs them. The
# archive is rebuilt whenever any base runtime source is newer than it. The
# whole-program-LTO builds (--release / --lto) skip this and rebuild
# the runtime from source for a lean, cross-optimized binary.
-> dev_runtime_shell_quote(text)
  "'" + text.gsub("'", "'\\''") + "'"

# One selected content-addressed cache for runtime archives, loader artifacts,
# and incremental binaries. An explicit override wins. Otherwise a project
# checkout owns its build/cache; installed compilers fall back to their
# TUNGSTEN_ROOT rather than leaking artifacts into /tmp or an implicit home
# directory.
-> compiler_cache_dir
  override = env("TUNGSTEN_CACHE_DIR")
  if override != nil && override != ""
    return override
  if file?("Bitfile")
    cwd = capture("pwd -P 2>/dev/null").strip()
    if cwd != ""
      return cwd + "/build/cache"
  root = env("TUNGSTEN_ROOT")
  if root != nil && root != ""
    return root + "/build/cache"
  runtime_dir = resolve_runtime_dir
  parent = capture("cd " + dev_runtime_shell_quote(runtime_dir + "/..") + " && pwd -P 2>/dev/null").strip()
  if parent != ""
    return parent + "/build/cache"
  nil

-> delegate_compiler_image(kind)
  root = env("TUNGSTEN_ROOT")
  if root == nil || root == ""
    ccall("w_eputs", "the " + kind + " compiler image requires TUNGSTEN_ROOT; invoke it through bin/tungsten")
    exit 1

  source_name = kind == "repl" ? "repl" : "tungsten_" + kind
  source = root + "/compiler/" + source_name + ".w"
  if !file?(source)
    ccall("w_eputs", "missing compiler image source: " + source)
    exit 1

  cache = compiler_cache_dir()
  if cache == nil || cache == ""
    ccall("w_eputs", "could not select a cache directory for the " + kind + " compiler image")
    exit 1
  image_dir = cache + "/compiler-images"
  if system("mkdir -p " + dev_runtime_shell_quote(image_dir)) != true
    ccall("w_eputs", "could not create compiler image cache: " + image_dir)
    exit 1

  exe = ccall("w_executable_path")
  if exe == nil || exe == ""
    ccall("w_eputs", "compiler executable path is unavailable")
    exit 1
  image = image_dir + "/tungsten-" + kind

  # Invoke compile every time and let the existing manifest cache decide if
  # the wrapper or any transitive `use` changed. This avoids a second, subtly
  # different dependency freshness implementation for optional images.
  build_cmd = "TUNGSTEN_INCREMENTAL=1 TUNGSTEN_LL_PATH='' " + dev_runtime_shell_quote(exe) + " compile " + dev_runtime_shell_quote(source) + " --out " + dev_runtime_shell_quote(image) + " --release --native --no-debug --no-lto >/dev/null"
  if system(build_cmd) != true
    ccall("w_eputs", "failed to build the " + kind + " compiler image")
    exit 1

  run_cmd = StringBuffer(256)
  run_cmd << "TUNGSTEN_COMPILER_IMAGE="
  run_cmd << dev_runtime_shell_quote(kind)
  run_cmd << " "
  run_cmd << dev_runtime_shell_quote(image)
  image_args = argv()
  ai = 0
  while ai < image_args.size()
    run_cmd << " "
    run_cmd << dev_runtime_shell_quote(image_args[ai])
    ai += 1
  process = Process.spawn(["/bin/sh", "-c", run_cmd.to_s()])
  exit process.wait()

# Canonicalize the selected runtime root without making direct C-VM execution
# depend on File.expand_path (the C VM intentionally implements only the small
# bootstrap builtin set). Standard staged bootstrap passes --runtime and never
# executes this path, but direct `tungsten-c compiler/tungsten.w compile ...`
# should remain correct too.
-> dev_runtime_source_identity(runtime_dir, runtime_kind)
  if runtime_kind == "tungsten-c"
    resolved = capture("cd " + dev_runtime_shell_quote(runtime_dir) + " && pwd -P 2>/dev/null").strip()
    if resolved != ""
      return resolved
    if runtime_dir.starts_with?("/")
      return runtime_dir
    pwd = env("PWD")
    if pwd != nil && pwd != ""
      return pwd + "/" + runtime_dir
    return runtime_dir
  File.expand_path(runtime_dir)

# Extract the first executable word without evaluating the configured command.
# This covers quoted/escaped wrapper paths and command-plus-flags forms while
# avoiding a second execution of user shell syntax merely to build a cache key.
-> dev_runtime_first_command_word(command)
  if command == nil
    return nil
  i = 0
  while i < command.size()
    ch = command.slice(i, 1)
    break if !(ch in (" " "\t" "\n" "\r"))
    i += 1
  if i >= command.size()
    return nil

  out = StringBuffer(32)
  quote = ""
  escaped = false
  while i < command.size()
    ch = command.slice(i, 1)
    if escaped
      out << ch
      escaped = false
    elsif quote == "'"
      if ch == "'"
        quote = ""
      else
        out << ch
    elsif quote == "\""
      if ch == "\""
        quote = ""
      elsif ch == "\\"
        escaped = true
      else
        out << ch
    elsif ch in (" " "\t" "\n" "\r")
      break
    elsif ch == "'" || ch == "\""
      quote = ch
    elsif ch == "\\"
      escaped = true
    else
      out << ch
    i += 1

  if quote != "" || escaped
    return nil
  word = out.to_s()
  return nil if word == ""
  word

# Resolve the first executable of a compiler/archive command through PATH.
# If a command cannot be resolved safely, the dev archive is disabled for that
# invocation instead of reusing a cache with an incomplete identity.
-> dev_runtime_resolve_tool(command, runtime_kind)
  executable = dev_runtime_first_command_word(command)
  if executable == nil
    return nil

  if runtime_kind == "tungsten-c"
    resolved = capture("command -v " + dev_runtime_shell_quote(executable) + " 2>/dev/null").strip()
    if resolved == ""
      return nil
    return resolved

  if executable.index("/") != nil
    if file?(executable)
      return File.expand_path(executable)
    return nil

  raw_path = env("PATH")
  if raw_path == nil
    raw_path = ""
  parts = raw_path.split(":")
  i = 0
  while i < parts.size()
    dir = parts[i]
    if dir == ""
      dir = "."
    candidate = dir + "/" + executable
    if file?(candidate)
      return File.expand_path(candidate)
    i += 1
  nil

# A driver that already resolved/stat'ed a tool can avoid probing by exporting
# its supplied identity. Native execution keys path + size + ns-mtime and adds
# a content hash for small executables (normally wrappers). That catches even a
# same-size wrapper rewrite with restored timestamps without hashing a 100MB+
# compiler on every warm link. The rare C-VM path uses POSIX cksum instead.
-> dev_runtime_tool_identity(command, runtime_kind, supplied_env)
  supplied = env(supplied_env)
  if supplied != nil && supplied != ""
    return "supplied:" + supplied + "|command:" + command

  resolved = dev_runtime_resolve_tool(command, runtime_kind)
  if resolved == nil
    return nil

  if runtime_kind == "tungsten-c"
    version = capture(dev_runtime_shell_quote(resolved) + " --version 2>/dev/null | head -n 1").strip()
    checksum = capture("cksum " + dev_runtime_shell_quote(resolved) + " 2>/dev/null").strip()
    return "cvm:" + command + "|" + resolved + "|" + version + "|" + checksum

  size = File.size(resolved)
  mtime = File.mtime_ns(resolved)
  if size == nil || mtime == nil
    return nil
  content_identity = ""
  if size <= 1048576
    content = read_file(resolved)
    if content != nil
      content_identity = "|hash:" + wyhash64_hex_string(content)
  "native:" + command + "|" + resolved + "|" + size.to_s() + "|" + mtime.to_s() + content_identity

-> dev_runtime_cc_identity(command, runtime_kind)
  dev_runtime_tool_identity(command, runtime_kind, "TUNGSTEN_CC_ID")

-> dev_runtime_ar_identity(command, runtime_kind)
  dev_runtime_tool_identity(command, runtime_kind, "TUNGSTEN_AR_ID")

-> dev_runtime_append_env(config, name)
  value = env(name)
  if value == nil
    value = ""
  config << name
  config << "="
  config << value
  config << "\n"

# The runtime sources an archive build reads — shared by the archive's own
# mtime-freshness check and the incremental compile cache's manifest, so
# the two invalidation rules can never drift.
-> dev_runtime_base_files(ev, generated_thresholds, tls_source)
  bases = ["runtime.c", "terminal_input.c", "runtime.h", "wvalue.h",
           "event_loop.h", "ssmr_witness.h", "w_char_table.c", "aks.c", tls_source,
           "pdqsort.inc", "ipnsort.inc", "radixsort.inc", "timsort.inc",
           "skasort.inc", "wolfsort.inc"]
  if ev == "event_*.c"
    bases.push("event_kqueue.c")
    bases.push("event_epoll.c")
    bases.push("event_iouring.c")
  else
    bases.push(ev)
  if generated_thresholds == "present"
    bases.push("generated/bigint_thresholds.h")
  bases

-> dev_runtime_archive_path(cache_dir, runtime_root, cc_identity, ar_identity, compile_flags, event_source, generated_thresholds, tls_source)
  config = StringBuffer(0)
  config << "dev-runtime-archive-v5\n"
  config << runtime_root
  config << "\ncc="
  config << cc_identity
  config << "\nar="
  config << ar_identity
  config << "\nflags="
  config << compile_flags
  config << "\n"
  config << event_source
  config << "\nthresholds="
  config << generated_thresholds
  config << "\ntls="
  config << tls_source
  config << "\n"
  # Ambient compiler/header selection changes object code even when the clang
  # path and explicit flags are unchanged. Keep this list synchronized with
  # bin/commands/build.rb's ambient_toolchain_identity.
  dev_runtime_append_env(config, "SDKROOT")
  dev_runtime_append_env(config, "MACOSX_DEPLOYMENT_TARGET")
  dev_runtime_append_env(config, "CPATH")
  dev_runtime_append_env(config, "C_INCLUDE_PATH")
  dev_runtime_append_env(config, "CPLUS_INCLUDE_PATH")
  dev_runtime_append_env(config, "LIBRARY_PATH")
  dev_runtime_append_env(config, "PKG_CONFIG_PATH")
  dev_runtime_append_env(config, "PKG_CONFIG_LIBDIR")
  cache_dir + "/runtime-native-" + wyhash64_hex_string(config.to_s()) + ".a"

-> dev_runtime_archive(verbose = false)
  runtime_dir = resolve_runtime_dir
  ev = runtime_event_source
  runtime_kind = runtime_identity()
  runtime_root = dev_runtime_source_identity(runtime_dir, runtime_kind)
  cc_command = host_c_compiler()
  cc_identity = dev_runtime_cc_identity(cc_command, runtime_kind)
  ar_command = archive_tool()
  ar_identity = dev_runtime_ar_identity(ar_command, runtime_kind)
  if cc_identity == nil || ar_identity == nil
    return nil
  cache_dir = compiler_cache_dir()
  if cache_dir == nil || system("mkdir -p " + dev_runtime_shell_quote(cache_dir)) != true
    return nil
  compile_flags = profile_opt_flag() + " " + debug_compile_flag() + " " + march_flags()
  if frame_pointers
    compile_flags += " -fno-omit-frame-pointer"
  tcf = tls_cflags
  if tcf != ""
    compile_flags += " " + tcf
  thresholds_path = runtime_root + "/generated/bigint_thresholds.h"
  generated_thresholds = "absent"
  if file?(thresholds_path)
    generated_thresholds = "present"
  tls_source = tls_runtime_source()
  archive = dev_runtime_archive_path(cache_dir, runtime_root, cc_identity, ar_identity, compile_flags, ev, generated_thresholds, tls_source)
  evo = ev.replace(".c", ".o")

  # Freshness: reuse the cached archive iff it is newer than every base source.
  bases = dev_runtime_base_files(ev, generated_thresholds, tls_source)

  fresh = StringBuffer(0)
  fresh << "test -e "
  fresh << dev_runtime_shell_quote(archive)
  bi = 0
  while bi < bases.size()
    fresh << " && test "
    fresh << dev_runtime_shell_quote(archive)
    fresh << " -nt "
    fresh << dev_runtime_shell_quote(runtime_root + "/" + bases[bi])
    bi += 1
  if file?(archive) && system(fresh.to_s()) == true
    return archive

  if verbose
    << "Building native runtime archive (one-time)..."

  # Compile in a per-process directory so concurrent roots/configurations can
  # never exchange runtime.o files. Build the archive beside its final path and
  # publish with one same-filesystem rename; linkers see either the complete old
  # archive or the complete new one, never a partially written ar file.
  event_source_arg = dev_runtime_shell_quote(runtime_root + "/" + ev)
  event_object_arg = dev_runtime_shell_quote(evo)
  if ev == "event_*.c"
    event_source_arg = dev_runtime_shell_quote(runtime_root + "/event_") + "*.c"
    event_object_arg = "event_*.o"

  cc = StringBuffer(0)
  cc << "build_dir="
  cc << dev_runtime_shell_quote(archive + ".build.")
  cc << "$$; archive_tmp="
  cc << dev_runtime_shell_quote(archive + ".tmp.")
  cc << "$$; rm -rf \"$build_dir\" \"$archive_tmp\" && mkdir -p \"$build_dir\" && cd \"$build_dir\" && "
  cc << cc_command
  cc << " "
  cc << compile_flags
  cc << " -I"
  cc << dev_runtime_shell_quote(runtime_root)
  cc << " -c "
  cc << dev_runtime_shell_quote(runtime_root + "/runtime.c")
  cc << " "
  cc << dev_runtime_shell_quote(runtime_root + "/terminal_input.c")
  cc << " "
  cc << event_source_arg
  cc << " "
  cc << dev_runtime_shell_quote(runtime_root + "/aks.c")
  cc << " "
  cc << dev_runtime_shell_quote(runtime_root + "/" + tls_source)
  cc << " && "
  cc << ar_command
  cc << " rcs \"$archive_tmp\""
  cc << " runtime.o terminal_input.o "
  cc << event_object_arg
  cc << " aks.o "
  cc << tls_source.replace(".c", ".o")
  cc << " && mv -f \"$archive_tmp\" "
  cc << dev_runtime_shell_quote(archive)
  cc << "; status=$?; rm -rf \"$build_dir\" \"$archive_tmp\"; exit $status"
  if system(cc.to_s()) != true
    return nil
  archive

-> compile_runtime_objs(tmp_dir, needs_zstd = false, verbose = false)
  # Compile the shared runtime once into a private object bundle. Do not put
  # these objects in an archive: Apple clang emits a mixture of LTO bitcode
  # and native Mach-O for this source set, and Apple ar turns that mixture
  # into a universal archive whose host slice silently omits the bitcode.
  # Passing the objects directly lets clang consume both representations and
  # preserves LTO across the emitted program and the bitcode members.
  runtime_dir = File.expand_path(resolve_runtime_dir)
  object_glob = tmp_dir + "/*.o"

  cc = StringBuffer(0)
  cc << "cd "
  cc << dev_runtime_shell_quote(tmp_dir)
  cc << " && "
  cc << host_c_compiler()
  cc << " "
  cc << cross_compile_flags()
  cc << profile_opt_flag()
  cc << " "
  cc << debug_compile_flag()
  cc << " "
  cc << march_flags()
  cc << " "

  if needs_zstd
    zcf = zstd_cflags

    if zcf != ""
      cc << zcf
      cc << " "

  ocf = onig_cflags
  if ocf != ""
    cc << ocf
    cc << " "

  tcf = tls_cflags
  if tcf != ""
    cc << tcf
    cc << " "

  if (release_mode || explicit_lto) && !no_lto
    cc << (release_mode ? "-flto=full " : "-flto ")

  if frame_pointers
    cc << "-fno-omit-frame-pointer "

  cc << "-I"
  cc << dev_runtime_shell_quote(runtime_dir)
  cc << " -c "
  cc << dev_runtime_shell_quote(runtime_dir + "/runtime.c")
  cc << " "
  cc << dev_runtime_shell_quote(runtime_dir + "/terminal_input.c")
  cc << " "
  event_source = runtime_event_source
  if event_source == "event_*.c"
    cc << dev_runtime_shell_quote(runtime_dir + "/event_")
    cc << "*.c"
  else
    cc << dev_runtime_shell_quote(runtime_dir + "/" + event_source)
  cc << " "
  cc << dev_runtime_shell_quote(runtime_dir + "/" + tls_runtime_source())
  cc << " "
  cc << dev_runtime_shell_quote(runtime_dir + "/aks.c")
  cc << " "

  if needs_zstd
    cc << dev_runtime_shell_quote(runtime_dir + "/" + zstd_runtime_source())
    cc << " "

  << "Compiling runtime..."

  compile_started_at = clock
  result = system(cc.to_s())
  log_phase(verbose, "runtime compile", compile_started_at)

  if result != true
    return nil

  object_glob
