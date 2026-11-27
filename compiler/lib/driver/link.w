
# The platform the runtime's event backend is compiled for, as
# runtime/sources.txt names it: the OS in TUNGSTEN_OS (the build driver's
# probe) or this host's.
-> runtime_platform
  cached = env("TUNGSTEN_OS")
  if cached != nil && cached != ""
    os = cached
  else
    memo = driver_probe_memo[:os]
    if memo != nil
      os = memo
    else
      os = capture("uname -s").strip()
      driver_probe_memo[:os] = os
  if os == "Darwin"
    return "darwin"
  if os == "Linux"
    return "linux"
  os.downcase()

-> runtime_event_set
  use_uring = env("USE_IOURING")
  if runtime_platform() == "linux" && use_uring != nil && use_uring != ""
    return "event-iouring"
  "event"

# runtime/sources.txt is the one list of the runtime's translation units;
# every build of the runtime reads it (runtime/sources.sh is the reader for
# the shell, make and Ruby builds, scripts/test-runtime-sources.sh keeps the
# two in step). Rows [file, extra cflags] of the files in any of `sets` on
# `platform`, in manifest order, each once. A runtime directory without the
# manifest is older than this compiler and cannot be linked by it.
-> runtime_manifest_rows(runtime_dir)
  path = runtime_dir.ends_with?("/") ? runtime_dir + "sources.txt" : runtime_dir + "/sources.txt"
  key = "rtmanifest:" + path
  cached = driver_probe_memo[key]
  if cached != nil
    return cached
  text = read_file(path)
  if text == nil
    raise "runtime source manifest " + path + " is missing: that runtime directory does not belong to this compiler"
  rows = []
  lines = text.split("\n")
  li = 0
  while li < lines.size()
    line = lines[li].gsub("\t", " ").strip()
    li += 1
    if line != "" && !line.starts_with?("#")
      fields = []
      parts = line.split(" ")
      pi = 0
      while pi < parts.size()
        if parts[pi] != ""
          fields.push(parts[pi])
        pi += 1
      if fields.size() < 3
        raise "runtime source manifest " + path + ": expected FILE SETS PLATFORM in: " + line
      cflags = ""
      fi = 3
      while fi < fields.size()
        cflags = cflags == "" ? fields[fi] : cflags + " " + fields[fi]
        fi += 1
      rows.push([fields[0], fields[1].split(","), fields[2], cflags])
  driver_probe_memo[key] = rows
  rows

-> runtime_manifest_files(runtime_dir, platform, sets)
  rows = runtime_manifest_rows(runtime_dir)
  out = []
  seen = {}
  ri = 0
  while ri < rows.size()
    row = rows[ri]
    ri += 1
    hit = false
    if (row[2] == "any" || row[2] == platform) && seen[row[0]] != true
      member = row[1]
      mi = 0
      while mi < member.size() && !hit
        si = 0
        while si < sets.size() && !hit
          if member[mi] == sets[si]
            hit = true
          si += 1
        mi += 1
    if hit
      seen[row[0]] = true
      out.push([row[0], row[3]])
  out

# The base translation units of a program's runtime: set `program`, the
# event backend, TLS or its stub, and the zstd slab codec when the program
# needs it. The runtime archive and LTO bundle are keyed by this list.
-> program_runtime_sources(runtime_dir, with_zstd)
  sets = ["program", runtime_event_set(), tls_requested?() ? "tls" : "tls-stub"]
  if with_zstd
    sets.push(zstd_runtime_set())
  rows = runtime_manifest_files(runtime_dir, runtime_platform(), sets)
  files = []
  ri = 0
  while ri < rows.size()
    files.push(rows[ri][0])
    ri += 1
  files

# The sources' paths under the runtime directory, quoted for a shell.
-> runtime_source_args(runtime_root, files)
  out = StringBuffer(files.size() * 64)
  fi = 0
  while fi < files.size()
    if fi > 0
      out << " "
    out << dev_runtime_shell_quote(runtime_root + "/" + files[fi])
    fi += 1
  out.to_s()

# "a.c b.m" -> "a.o b.o": the objects `clang -c` leaves in its directory.
-> runtime_object_names(files)
  out = StringBuffer(files.size() * 24)
  fi = 0
  while fi < files.size()
    name = files[fi].split("/").last()
    if name.ends_with?(".c") || name.ends_with?(".m")
      name = name.slice(0, name.size() - 2)
    if fi > 0
      out << " "
    out << dev_runtime_shell_quote(name + ".o")
    fi += 1
  out.to_s()

-> parallel_runtime_compile_shell(cc_prefix, runtime_root, sources)
  out = StringBuffer(sources.size() * 192 + 64)
  out << "{ "
  fi = 0
  while fi < sources.size()
    name = sources[fi].split("/").last()
    if name.ends_with?(".c") || name.ends_with?(".m")
      name = name.slice(0, name.size() - 2)
    obj = name + ".o"
    ok = obj + ".ok"
    out << "( "
    out << cc_prefix
    out << " -c "
    out << dev_runtime_shell_quote(runtime_root + "/" + sources[fi])
    out << " -o "
    out << dev_runtime_shell_quote(obj)
    out << " && touch "
    out << dev_runtime_shell_quote(ok)
    out << " ) & "
    fi += 1
  out << "wait; }"
  fi = 0
  while fi < sources.size()
    name = sources[fi].split("/").last()
    if name.ends_with?(".c") || name.ends_with?(".m")
      name = name.slice(0, name.size() - 2)
    out << " && test -f "
    out << dev_runtime_shell_quote(name + ".o.ok")
    fi += 1
  out << " && rm -f *.o.ok"
  out.to_s()

-> extra_c_includes
  raw = env("TUNGSTEN_C_INCLUDES")

  if raw == nil || raw == ""
    return []

  parts = raw.split(":")
  out = []

  parts -> (part)
    out.push(part) if part != "" && !out.include?(part)

  out

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

-> lto_mode_flag
  if full_lto
    return "-flto=full"
  if release_mode
    return "-flto=thin"
  "-flto"

-> profile_opt_flag
  if opt_level_override != ""
    return opt_level_override == "-Ofast" ? "-O3" : opt_level_override
  if dev_mode
    return "-O0"
  "-O3"

-> clang_extra_pass_flags
  return "" if extra_opt_flags.size() == 0
  mapped = []
  i = 0
  while i < extra_opt_flags.size()
    f = extra_opt_flags[i]
    if f == "-finline" || f == "-finline-functions"
      mapped.push("-finline-functions")
    elsif f == "-fno-inline" || f == "-fno-inline-functions"
      mapped.push("-fno-inline")
    elsif f == "-funroll-loops" || f == "-fno-unroll-loops" || f == "-ffast-math" || f == "-fno-fast-math"
      mapped.push(f)
    i += 1
  mapped.join(" ")

# Optimization flags for the cached LTO runtime bundle. TUNGSTEN_CLANG_OPT is
# the emitted module's flag set, and `--fast` puts -ffast-math in it; the C
# runtime keeps IEEE semantics in every profile (its NaN/Inf checks, float
# parsing and formatting are not the program's fast-FP code), so the value-
# changing FP flags are dropped here. `--release --fast` therefore shares the
# bundle of `--release`.
-> runtime_lto_opt_flag(clang_opt)
  if clang_opt == nil || clang_opt == ""
    return profile_opt_flag()
  kept = []
  parts = clang_opt.split(" ")
  i = 0
  while i < parts.size()
    part = parts[i]
    fp_only = part in ("-ffast-math" "-ffinite-math-only" "-funsafe-math-optimizations" "-fassociative-math" "-freciprocal-math" "-fno-signed-zeros" "-fno-honor-nans" "-fno-honor-infinities" "-fapprox-func")
    if part == "-Ofast"
      kept.push("-O3")
    elsif part != "" && !fp_only
      kept.push(part)
    i += 1
  if kept.size() == 0
    return profile_opt_flag()
  kept.join(" ")

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
  same_process_ir = g_incremental[:last_emitted_ll_path] == ll_path && g_incremental[:last_emitted_ll_text] != nil
  ll_probe_text = same_process_ir ? g_incremental[:last_emitted_ll_text] : read_file(ll_path)
  precomputed_lf = same_process_ir ? g_incremental[:last_emitted_link_features] : nil
  if precomputed_lf != nil
    compiler_image_runtime_profile = precomputed_lf[:compiler_image_runtime_profile] == true
    dynamic_exports_needed = precomputed_lf[:dynamic_exports_needed] == true || env("TUNGSTEN_DYNAMIC_EXPORTS") == "1"
    bridges_needed = precomputed_lf[:bridges_needed] == true
    blas_needed = precomputed_lf[:blas_needed] == true
    sparse_needed = precomputed_lf[:sparse_needed] == true
    quartz_needed = precomputed_lf[:quartz_needed] == true
    media_needed = precomputed_lf[:media_needed] == true
    credentials_needed = precomputed_lf[:credentials_needed] == true
    sci_io_needed = precomputed_lf[:sci_io_needed] == true
    wtensor_needed = precomputed_lf[:wtensor_needed] == true
    cuda_needed = precomputed_lf[:cuda_needed] == true
    mlx_needed = precomputed_lf[:mlx_needed] == true
    prime_needed = precomputed_lf[:prime_needed] == true
    lexchars_needed = precomputed_lf[:lexchars_needed] == true
    unicode_needed = precomputed_lf[:unicode_needed] == true
    needs_zstd = precomputed_lf[:needs_zstd] == true
    needs_gc = precomputed_lf[:needs_gc] == true
  else
    compiler_image_runtime_profile = ll_code_has(ll_probe_text, "@w_compiler_image_lean_profile(")
    dynamic_exports_needed = ll_needs_dynamic_exports(ll_probe_text)
    bridges_needed = ll_needs_apple_bridges(ll_probe_text)
    blas_needed = ll_needs_blas(ll_probe_text)
    sparse_needed = ll_needs_sparse(ll_probe_text)
    quartz_needed = ll_needs_quartz(ll_probe_text)
    media_needed = ll_needs_media(ll_probe_text)
    credentials_needed = ll_needs_credentials(ll_probe_text)
    sci_io_needed = ll_needs_sci_io(ll_probe_text)
    wtensor_needed = ll_needs_wtensor(ll_probe_text)
    cuda_needed = ll_needs_cuda(ll_probe_text)
    mlx_needed = ll_needs_mlx(ll_probe_text)
    prime_needed = ll_code_has(ll_probe_text, "@w_prime_") || ll_code_has(ll_probe_text, "@w_primes_") || ll_code_has(ll_probe_text, "@w_bigint_prime")
    lexchars_needed = ll_needs_lexchars(ll_probe_text)
    unicode_needed = ll_needs_unicode(ll_probe_text)
    needs_zstd = ll_needs_zstd_text(ll_probe_text)
    needs_gc = ll_code_has(ll_probe_text, "@w_gc_enable(")
  link_started_at = clock
  # LTO is opt-in: whole-program LTO (lean binary, slow link) only for
  # --release / --lto; the default is a target-matched object runtime
  # archive (fatter binary, ~0.1s link vs ~5s recompiling the C runtime).
  # --release means LTO for every program, not only compiler images: the
  # runtime side is the cached bitcode bundle below, so the per-link cost is
  # the merged-module optimization alone. --no-lto is the one opt-out.
  # scripts/test-compile-profiles.sh pins the flags of each profile.
  use_cinder = cinder_mode || env("TUNGSTEN_BACKEND") == "cinder"
  doing_lto = (release_mode || explicit_lto || full_lto) && !no_lto && !use_cinder
  full_runtime_lto = doing_lto
  # Fast native-archive link (default): reuse the cached runtime objects
  # rather than recompiling the ~28k-line runtime every build. runtime.o's weak
  # companion stubs keep the gated ssmr/lexchar/metal/blas adds below valid.
  # Configs the shared archive can't represent (cross-target and zstd) fall
  # through to the from-source path. Frame-pointer mode is part of the archive
  # flags and identity, so debug builds can reuse it without losing backtraces.
  store_entries = []
  if runtime_objs == nil && !full_runtime_lto && cross_target == ""
    runtime_objs = dev_runtime_archive(verbose, needs_zstd, needs_gc)
    if runtime_objs != nil
      store_entries.push(runtime_objs)
  clang_opt = env("TUNGSTEN_CLANG_OPT")
  if clang_opt == nil || clang_opt == ""
    # --dev: clang -O0 on the emitted module. Measured on the self-hosted
    # compiler: link 19.5s -> 5.2s (-O1 is no cheaper than -O3's 18s; only
    # -O0 skips the expensive passes), full build 2.8x faster, produced
    # binary ~2.2x slower — the right trade for edit-test loops. Its
    # separately keyed runtime archive uses the same -O0 profile.
    clang_opt = profile_opt_flag()
    extra_cf = clang_extra_pass_flags()
    if extra_cf != ""
      clang_opt = clang_opt + " " + extra_cf

  # The source/output-path incremental cache runs before lowering. This second
  # cache sits at the other end of the pipeline: if two builds emit identical
  # LLVM under the same complete link contract, reuse the already linked
  # executable without introducing an object/LTO boundary. This catches a new
  # -o path, comment-only edits, and identical release batch entries. Arbitrary
  # user C includes are deliberately ineligible because their transitive header
  # graph is opaque to this driver.
  link_cache_slot = nil
  if doing_lto || (ll_probe_text != nil && ll_probe_text.size() >= 4194304) || env("TUNGSTEN_LINK_CACHE") == "1"
    link_cache_slot = link_artifact_cache_slot(ll_probe_text, runtime_objs, needs_zstd)
  if link_cache_slot != nil && link_artifact_cache_try_reuse(link_cache_slot, out_path)
    if verbose
      << fmt_elapsed(phase_elapsed(link_started_at)) + (use_cinder ? " cinder (link cache)" : " clang (link cache)")
    return true

  if use_cinder
    owner_root = compiler_image_owner_root()
    cinder_bin = owner_root + "/bits/tungsten-cinder/bin/cinder"
    if !file?(cinder_bin)
      cinder_bin = owner_root + "/bin/cinder"
    cinder_cmd = StringBuffer(256)
    cinder_cmd << "TUNGSTEN_ROOT="
    cinder_cmd << dev_runtime_shell_quote(owner_root)
    cinder_cmd << " "
    cinder_cmd << dev_runtime_shell_quote(cinder_bin)
    cinder_cmd << " compile"
    if opt_level_override != ""
      cinder_cmd << " "
      cinder_cmd << dev_runtime_shell_quote(opt_level_override)
    elsif dev_mode
      cinder_cmd << " -O0"
    elsif release_mode
      cinder_cmd << " -O3"
    if fast_mode
      cinder_cmd << " --fast"
    if math_mode == :strict
      cinder_cmd << " --strict-math"
    if debug_enabled
      cinder_cmd << " --debug"
    else
      cinder_cmd << " --no-debug"
    if frame_pointers
      cinder_cmd << " --frame-pointers"
    ef_i = 0
    while ef_i < extra_opt_flags.size()
      cinder_cmd << " "
      cinder_cmd << dev_runtime_shell_quote(extra_opt_flags[ef_i])
      ef_i += 1
    if verbose
      cinder_cmd << " -v"
    if cross_target != ""
      cinder_cmd << " --target "
      cinder_cmd << dev_runtime_shell_quote(cross_target)
    cinder_cmd << " "
    cinder_cmd << dev_runtime_shell_quote(ll_path)
    cinder_cmd << " -o "
    cinder_cmd << dev_runtime_shell_quote(out_path)
    c_res = system(cinder_cmd.to_s())
    log_phase(verbose, "cinder", link_started_at)
    on macos
      if c_res == true
        system("TUNGSTEN_PREFLIGHT=1 " + dev_runtime_shell_quote(out_path) + " </dev/null >/dev/null 2>&1 &")
    if c_res == true && link_cache_slot != nil
      link_artifact_cache_store(link_cache_slot, out_path)
    if c_res == true
      dev_runtime_renew(store_entries)
    return c_res == true
  if runtime_objs == nil && full_runtime_lto && cross_target == ""
    runtime_objs = dev_runtime_lto_objects(compiler_image_runtime_profile, verbose, needs_zstd, needs_gc)
    if runtime_objs != nil
      store_entries.push(runtime_objs.slice(0, runtime_objs.size() - 4))

  g_incremental[:temp_shard_dir] = nil
  parallel_objs = nil
  if cross_target == "" && !full_runtime_lto
    if clang_opt == "-O3" && !frame_pointers && env("TUNGSTEN_PARALLEL_CODEGEN") == "1"
      parallel_objs = parallel_codegen_objects(ll_path, verbose)
    if parallel_objs == nil
      parallel_objs = native_sharded_codegen_objects(ll_path, clang_opt, store_entries, verbose)
  elsif cross_target == "" && full_runtime_lto && !full_lto && release_mode && env("TUNGSTEN_SHARD_THINLTO") != "0"
    parallel_objs = native_sharded_codegen_objects(ll_path, clang_opt, store_entries, verbose, "-flto=thin")

  clang_cmd = StringBuffer(0)
  if extra_opt_flags.include?("--print-passes")
    << "\[tungsten:clang\] opt=" + clang_opt + " debug=" + debug_enabled.to_s() + " fast=" + fast_mode.to_s() + " lto=" + full_runtime_lto.to_s()
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

  if full_runtime_lto
    clang_cmd << lto_mode_flag()
    clang_cmd << " "
    if !full_lto && release_mode && cross_target == "" && env("TUNGSTEN_THINLTO_CACHE") != "0"
      tlto_cache_root = compiler_cache_dir()
      if tlto_cache_root != nil
        tlto_cache_dir = tlto_cache_root + "/thinlto-cache"
        if ensure_driver_dir(tlto_cache_dir)
          if detect_target()[:os] == "macos"
            clang_cmd << "-Wl,-cache_path_lto,"
            clang_cmd << dev_runtime_shell_quote(tlto_cache_dir)
            clang_cmd << " "
          elsif detect_target()[:os] == "linux"
            clang_cmd << "-Wl,--thinlto-cache-dir="
            clang_cmd << dev_runtime_shell_quote(tlto_cache_dir)
            clang_cmd << " "

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
    # --info-plist: the bundle keys of a bare executable (CFBundleName names
    # it in the menu bar). The plist's contents are in incremental_identity,
    # which keys both the irbin and the link-artifact caches.
    if info_plist_path != ""
      clang_cmd << "-Wl,-sectcreate,__TEXT,__info_plist,"
      clang_cmd << dev_runtime_shell_quote(incremental_abs_path(info_plist_path))
      clang_cmd << " "
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
  gated_dir = runtime_dir
  # Which companion files implement a feature, on which platform and with
  # which extra flags, is runtime/sources.txt's `companion:<feature>` rows
  # (e.g. blas is blas_bridge.c with -fno-finite-math-only on macOS, so that
  # slogdet's singular -Inf survives --fast, and openblas_bridge.c on Linux).
  companion_gates = []
  if prime_needed
    companion_gates.push("prime")
  if lexchars_needed
    companion_gates.push("lexchars")
  if unicode_needed
    companion_gates.push("unicode")
  if blas_needed
    companion_gates.push("blas")
  if sparse_needed
    companion_gates.push("sparse")
  mlx_inc = ""
  if mlx_needed && target_os == "macos"
    mlx_inc = mlx_cflags()
    if mlx_inc == ""
      raise "this program uses MLX (w_mlx_* / bf16 conversion) but mlx-c is not installed — brew install mlx mlx-c"
    companion_gates.push("mlx")
  if bridges_needed
    companion_gates.push("bridges")
  if quartz_needed
    companion_gates.push("quartz")
  if media_needed
    companion_gates.push("media")
  if credentials_needed
    companion_gates.push("credentials")
  if sci_io_needed
    companion_gates.push("sci_io")
  if wtensor_needed
    companion_gates.push("wtensor")
  if cuda_needed
    cuda_needed = cuda_needed
  companion_platform = target_os == "macos" ? "darwin" : target_os
  companion_reqs = []
  gi = 0
  while gi < companion_gates.size()
    gate_rows = runtime_manifest_files(runtime_dir, companion_platform, ["companion:" + companion_gates[gi]])
    gri = 0
    while gri < gate_rows.size()
      gate_flags = gate_rows[gri][1]
      if companion_gates[gi] == "mlx" && mlx_inc != ""
        gate_flags = gate_flags == "" ? mlx_inc : gate_flags + " " + mlx_inc
      companion_reqs.push([gate_rows[gri][0], gate_flags])
      gri += 1
    gi += 1

  companion_cmd = StringBuffer(0)
  companion_compiles_c = false
  ci = 0
  while ci < companion_reqs.size()
    req = companion_reqs[ci]
    rel_src = req[0]
    req_cflags = req[1]
    cached_obj = dev_runtime_companion_object(rel_src, false, req_cflags)
    if cached_obj != nil
      store_entries.push(cached_obj)
      companion_cmd << dev_runtime_shell_quote(cached_obj)
      companion_cmd << " "
    else
      companion_compiles_c = true
      companion_cmd << gated_dir
      companion_cmd << rel_src
      companion_cmd << " "
      if req_cflags != ""
        companion_cmd << req_cflags
        companion_cmd << " "
    ci += 1

  compiles_c = runtime_objs == nil || companion_compiles_c || extra_c_includes.size() > 0
  if compiles_c
    clang_cmd << "-I"
    clang_cmd << runtime_dir
    clang_cmd << " "
    # A build that names everything relatively (the stage compilers, compiler
    # images and bits the build store shares: started from the toolchain root
    # with TUNGSTEN_ROOT unset, so runtime_dir is "runtime/") must not record
    # the directory it happened to be compiled in either: clang writes the
    # cwd into the debug info of every C source compiled here, and the linker
    # copies it into the executable.
    if !runtime_dir.starts_with?("/")
      clang_cmd << "-ffile-prefix-map=\"$PWD\"=. "
  if runtime_objs != nil
    clang_cmd << runtime_objs
    clang_cmd << " "
  else
    base_sources = program_runtime_sources(runtime_dir, needs_zstd)
    bi = 0
    while bi < base_sources.size()
      clang_cmd << runtime_dir
      clang_cmd << base_sources[bi]
      clang_cmd << " "
      bi += 1

  clang_cmd << companion_cmd.to_s()

  includes = extra_c_includes

  includes -> clang_cmd << dev_runtime_shell_quote(inc) + " "

  if parallel_objs != nil
    clang_cmd << parallel_objs
  else
    clang_cmd << ll_path

  if needs_zstd
    zlf = zstd_ldflags

    if zlf != ""
      clang_cmd << " "
      clang_cmd << zlf

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
      clang_cmd << " -framework Metal -framework Foundation -framework AppKit -framework QuartzCore -framework CoreGraphics -framework CoreVideo -framework IOKit -framework CoreFoundation"
    if blas_needed || sparse_needed
      clang_cmd << " -framework Accelerate"
    if quartz_needed
      clang_cmd << " -framework CoreGraphics -framework CoreText -framework ImageIO -framework CoreFoundation"
    if credentials_needed
      clang_cmd << " -framework Foundation -framework Security -framework CoreFoundation"
    if media_needed
      clang_cmd << " -framework VideoToolbox -framework CoreMedia -framework CoreVideo -framework AVFoundation -framework AudioToolbox -framework Foundation -framework CoreFoundation"
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
  if g_incremental[:temp_shard_dir] != nil
    system("rm -rf " + dev_runtime_shell_quote(g_incremental[:temp_shard_dir]))
    g_incremental[:temp_shard_dir] = nil
  log_phase(verbose, "clang", link_started_at)
  # Warm macOS's first-exec malware-scan cache now rather than on the user's
  # first run (see w_preflight in runtime/runtime.c): exec the fresh binary
  # detached with TUNGSTEN_PREFLIGHT set; it exits at the top of main.
  on macos
    if result == true
      system("TUNGSTEN_PREFLIGHT=1 " + dev_runtime_shell_quote(out_path) + " </dev/null >/dev/null 2>&1 &")
  if result == true && link_cache_slot != nil
    link_artifact_cache_store(link_cache_slot, out_path)
  if result == true
    dev_runtime_renew(store_entries)
  result == true

# Persistent NATIVE-object runtime archive for fast dev links. Linking against
# this skips recompiling the ~28k-line C runtime on every build (~5s -> ~0.1s).
# runtime.o keeps weak stubs for the gated companions, so link_binary still adds
# the strong ssmr/lexchar/metal/blas sources when a program needs them. The
# archive is rebuilt whenever any base runtime source is newer than it. The
# whole-program-LTO builds (--release / --lto) skip this and link the cached
# bitcode bundle (dev_runtime_lto_objects) for a lean, cross-optimized binary.
-> dev_runtime_shell_quote(text)
  "'" + text.gsub("'", "'\\''") + "'"

-> ensure_driver_dir(dir)
  if dir == nil || dir == ""
    return false
  key = "dir:" + dir
  if driver_probe_memo[key] == true
    return true
  if system("mkdir -p " + dev_runtime_shell_quote(dir)) != true
    return false
  driver_probe_memo[key] = true
  true

# The build store: one directory shared by every checkout, worktree and
# installed toolchain of one user, so identical work is done once.
#   TUNGSTEN_BUILD_STORE   the store root, when set
#   TUNGSTEN_HOME/cache    otherwise (the launcher exports TUNGSTEN_HOME)
#   HOME/.tungsten/cache   otherwise
# Without a home directory the store sits under the toolchain root, as the
# launcher's TUNGSTEN_HOME default does. The same policy is implemented by
# bin/commands/store.sh (launcher, hook, GC), bin/commands/build.w, the
# Loader's cache_dir, and bin/commands/compile.rb; keep them in step.
-> tungsten_build_store_dir
  override = env("TUNGSTEN_BUILD_STORE")
  if override != nil && override != ""
    return override
  home = env("TUNGSTEN_HOME")
  if home != nil && home != ""
    return home + "/cache"
  home = env("HOME")
  if home != nil && home != ""
    return home + "/.tungsten/cache"
  root = env("TUNGSTEN_ROOT")
  if root != nil && root != ""
    return root + "/.tungsten/cache"
  parent = capture("cd " + dev_runtime_shell_quote(resolve_runtime_dir + "/..") + " && pwd -P 2>/dev/null").strip()
  if parent != ""
    return parent + "/.tungsten/cache"
  nil

# The compiler's own artifacts (runtime archives and companion objects,
# incremental binaries, parse and Core snapshots, the compiled-run binaries)
# live in the store's compile/ directory. Because every checkout shares it, an
# entry's name must cover everything that determines its bytes: content for
# what is shared (runtime objects), the absolute paths and the toolchain root
# for what embeds them (programs). TUNGSTEN_CACHE_DIR replaces the directory
# outright; the spec and parity suites isolate themselves that way.
-> compiler_cache_dir
  override = env("TUNGSTEN_CACHE_DIR")
  if override != nil && override != ""
    return override
  store = tungsten_build_store_dir()
  if store == nil
    return nil
  store + "/compile"

# Optional compiler images (repl for bin/wit, metal for @gpu programs) are
# products of `bin/tungsten build`, never of a launch: bin/wit must start on
# whatever was last built in well under a second. `build-image KIND` compiles
# one through the ordinary incremental compile path (an unchanged image is a
# link-cache hit); delegate_compiler_image only execs an existing image and
# otherwise points at the build.
-> compiler_image_root(kind)
  root = env("TUNGSTEN_ROOT")
  if root == nil || root == ""
    ccall("w_eputs", "the " + kind + " compiler image requires TUNGSTEN_ROOT; invoke it through bin/tungsten")
    exit 1
  root

# Images are installed beside the compiler executable they belong to, in its
# checkout's build/compiler-images: a launch must find the image built for
# exactly this compiler and these sources, whatever cache a run selects
# (TUNGSTEN_CACHE_DIR isolates incremental artifacts only). `bin/tungsten
# build` produces them and keeps a copy in the build store under a
# fingerprint of the compiler and its sources, so a second checkout with the
# same compiler installs them instead of compiling them. The owner is the
# checkout (or package) root that holds the compiler's runtime/.
-> compiler_image_owner_root
  root = env("TUNGSTEN_ROOT")
  if root == nil || root == ""
    root = capture("cd " + dev_runtime_shell_quote(resolve_runtime_dir + "/..") + " && pwd -P 2>/dev/null").strip()
  root

-> compiler_image_dir(kind)
  root = compiler_image_owner_root()
  if root == ""
    ccall("w_eputs", "could not locate the checkout that owns the " + kind + " compiler image")
    exit 1
  root + "/build/compiler-images"

-> compiler_image_path(kind)
  compiler_image_dir(kind) + "/tungsten-" + kind

-> build_compiler_image(kind)
  if !(kind in ("repl" "metal"))
    ccall("w_eputs", "unknown compiler image kind: " + kind + " (expected repl or metal)")
    exit 1
  root = compiler_image_root(kind)
  source_name = kind == "repl" ? "repl" : "tungsten_" + kind
  relative_source = "compiler/" + source_name + ".w"
  source = root + "/" + relative_source
  if !file?(source)
    ccall("w_eputs", "missing compiler image source: " + source)
    exit 1
  image_dir = compiler_image_dir(kind)
  if system("mkdir -p " + dev_runtime_shell_quote(image_dir)) != true
    ccall("w_eputs", "could not create compiler image directory: " + image_dir)
    exit 1
  exe = ccall("w_executable_path")
  if exe == nil || exe == ""
    ccall("w_eputs", "compiler executable path is unavailable")
    exit 1
  image = compiler_image_path(kind)
  # The existing manifest/link caches decide whether the wrapper or any
  # transitive `use` changed; there is no second freshness implementation.
  # Compiled from the checkout root with a relative entry and no TUNGSTEN_ROOT,
  # the image names its sources relatively (core/array.w), as the stage
  # compilers do: its bytes do not depend on where the checkout lives, which
  # is what lets the build store share it.
  build_cmd = "cd " + dev_runtime_shell_quote(root) + " && env -u TUNGSTEN_ROOT TUNGSTEN_INCREMENTAL=1 TUNGSTEN_LL_PATH='' " + dev_runtime_shell_quote(exe) + " compile " + dev_runtime_shell_quote(relative_source) + " --out " + dev_runtime_shell_quote(image) + " --release --native --no-debug --no-lto >/dev/null"
  if system(build_cmd) != true
    ccall("w_eputs", "failed to build the " + kind + " compiler image")
    exit 1
  image

-> delegate_compiler_image(kind)
  # Running needs only the image directory (compiler_image_dir falls back to
  # the executable's checkout), so `tungsten-compiler --repl` works from any
  # cwd and env; TUNGSTEN_ROOT is required only to BUILD an image.
  image = compiler_image_path(kind)
  if !file?(image)
    ccall("w_eputs", "the " + kind + " compiler image is not built: " + image)
    ccall("w_eputs", "run bin/tungsten build (compiler images are built with the compiler, never on launch)")
    exit 1

  # An image sits in build/compiler-images, not in bin/, so it cannot
  # find core/, data/ and runtime/ from its own path the way this compiler
  # does. Unless the caller chose a root, hand it the one that owns the image:
  # without it a packaged or directly invoked `tungsten-compiler --repl` dies
  # looking for data/unit_names.txt, and a delegated @gpu compile links
  # against a runtime directory that does not exist.
  caller_root = env("TUNGSTEN_ROOT")
  if caller_root == nil || caller_root == ""
    ccall("w_setenv", "TUNGSTEN_ROOT", compiler_image_owner_root())

  # exec, not spawn: Process.spawn puts the child in its own process group,
  # and an interactive image (bin/wit) is then stopped by the terminal on its
  # first read. exec keeps the image as the foreground job and its exit
  # status is ours. The inner process sees its kind to prevent re-delegation.
  ccall("w_setenv", "TUNGSTEN_COMPILER_IMAGE", kind)
  exec_args = [image]
  image_args = argv()
  ai = 0
  while ai < image_args.size()
    exec_args.push(image_args[ai])
    ai += 1
  err = Process.exec(exec_args)
  ccall("w_eputs", "could not exec the " + kind + " compiler image " + image + " (errno " + (0 - err).to_s() + ")")
  exit 1

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

# Every C source, header and include fragment under the runtime directory
# (tests aside), and the source manifest that says which of them a build
# compiles (sources.txt), relative and sorted. This is the set the runtime objects are
# keyed and invalidated by: the archive, the LTO objects and each companion
# object take a content digest of all of it, and the incremental binary
# manifest records each file's mtime. A hand-kept list of "the files
# runtime.c includes" had already fallen behind (prime_lut.inc,
# ast_schema_generated.h), and in a store shared between checkouts a missed
# file would hand one checkout another's runtime.
-> dev_runtime_tree_files(runtime_root)
  key = "rtfiles:" + runtime_root
  cached = driver_probe_memo[key]
  if cached != nil
    return cached
  listing = capture("cd " + dev_runtime_shell_quote(runtime_root) + " 2>/dev/null && find . -path ./tests -prune -o -type f \\( -name '*.c' -o -name '*.h' -o -name '*.inc' -o -name '*.m' -o -name sources.txt \\) -print 2>/dev/null | LC_ALL=C sort")
  files = []
  rows = listing.split("\n")
  i = 0
  while i < rows.size()
    row = rows[i].strip()
    if row.starts_with?("./")
      row = row.slice(2, row.size() - 2)
    if row != ""
      files.push(row)
    i += 1
  driver_probe_memo[key] = files
  files

# Content identity of the runtime sources. nil when it cannot be computed:
# callers then compile the runtime from source for this one program instead of
# trusting a shared object. The compiled compiler hashes each file natively;
# the stage-0 C VM, which has no file digest builtin, asks POSIX cksum.
-> dev_runtime_sources_digest(runtime_root, runtime_kind)
  key = "rtdigest:" + runtime_root
  cached = driver_probe_memo[key]
  if cached != nil
    return cached
  files = dev_runtime_tree_files(runtime_root)
  if files.size() == 0
    return nil
  digest = nil
  if runtime_kind == "compiled-runtime"
    text = StringBuffer(files.size() * 48)
    i = 0
    while i < files.size()
      file_digest = digest_file64(runtime_root + "/" + files[i])
      if file_digest == nil
        return nil
      text << files[i]
      text << "="
      text << u64_hex(file_digest)
      text << "\n"
      i += 1
    digest = wyhash64_hex_string(text.to_s())
  else
    cmd = StringBuffer(files.size() * 32)
    cmd << "cd "
    cmd << dev_runtime_shell_quote(runtime_root)
    cmd << " && cksum"
    i = 0
    while i < files.size()
      cmd << " "
      cmd << dev_runtime_shell_quote(files[i])
      i += 1
    cmd << " 2>/dev/null"
    sums = capture(cmd.to_s()).strip()
    # One "crc size name" row per file: a file that vanished mid-listing
    # prints nothing, and a short answer must not become a key.
    if sums == "" || sums.split("\n").size() != files.size()
      return nil
    digest = wyhash64_hex_string(sums)
  driver_probe_memo[key] = digest
  digest

# Runtime objects are compiled with the checkout's absolute runtime path on
# the command line, in whatever directory the compiler was started from.
# These two maps make the bytes clang writes (__FILE__ in assert messages,
# the source names and compilation directory in debug info, which the linker
# copies into every program's debug map) say `runtime/...` and `.` instead,
# so an object is the same whichever checkout compiled it, from wherever.
# "$PWD" is expanded by the shell that runs the compile, after any `cd`.
-> dev_runtime_path_map_flag(runtime_root)
  " -ffile-prefix-map=" + dev_runtime_shell_quote(runtime_root) + "=runtime -ffile-prefix-map=\"$PWD\"=."

# Store entries are swept by age (bin/commands/cache_gc.sh), so what a build
# used must look recent or it is rebuilt every week however often it is used.
# After a link, one background `find` renews (at most once a day each: only
# files older than a day are touched) the runtime objects it linked, the
# parsed-source entries the loader restored, and this compiler's Core,
# library and function-text snapshots and target probes. Nothing in the
# store compares these mtimes with a source's, so renewing is always safe.
-> dev_runtime_renew(paths)
  cmd = StringBuffer(paths.size() * 96 + 512)
  cmd << "("
  used = loader_parse_cache_state[:disk_used]
  if paths.size() > 0 || used.size() > 0
    cmd << "find"
    i = 0
    while i < paths.size()
      cmd << " "
      cmd << dev_runtime_shell_quote(paths[i])
      i += 1
    i = 0
    while i < used.size()
      cmd << " "
      cmd << dev_runtime_shell_quote(used[i])
      i += 1
    cmd << " -type f -mtime +0 -exec touch {} + ; "
  cache_dir = compiler_cache_dir()
  identity = g_incremental[:persistent_identity]
  if cache_dir != nil
    cmd << "find "
    cmd << dev_runtime_shell_quote(cache_dir)
    cmd << " -maxdepth 1 -type f \\( -name 'target-probe-*' -o -name 'native-arm-cpu-*'"
    if identity != nil
      cmd << " -o -name 'core-wire-" + identity + "-*' -o -name 'library-wire-v1-" + identity + "-*' -o -name 'core-render-v1-" + identity + "-*'"
    cmd << " \\) -mtime +0 -exec touch {} + ; "
  cmd << "true) >/dev/null 2>&1 &"
  system(cmd.to_s())
  nil

-> dev_runtime_archive_path(cache_dir, sources_digest, cc_identity, ar_identity, compile_flags, source_list, generated_thresholds)
  config = StringBuffer(0)
  config << "dev-runtime-archive-v8\n"
  config << sources_digest
  config << "\ncc="
  config << cc_identity
  config << "\nar="
  config << ar_identity
  config << "\nflags="
  config << compile_flags
  config << "\nsources="
  config << source_list
  config << "\nthresholds="
  config << generated_thresholds
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

-> dev_runtime_archive(verbose = false, needs_zstd = false, needs_gc = false)
  runtime_dir = resolve_runtime_dir
  runtime_kind = runtime_identity()
  runtime_root = dev_runtime_source_identity(runtime_dir, runtime_kind)
  cc_command = host_c_compiler()
  cc_identity = dev_runtime_cc_identity(cc_command, runtime_kind)
  ar_command = archive_tool()
  ar_identity = dev_runtime_ar_identity(ar_command, runtime_kind)
  if cc_identity == nil || ar_identity == nil
    return nil
  cache_dir = compiler_cache_dir()
  if cache_dir == nil
    return nil
  compile_flags = profile_opt_flag() + " " + debug_compile_flag() + " " + march_flags()
  if !needs_gc
    compile_flags += " -DW_COMPILE_NO_GC"
  if frame_pointers
    compile_flags += " -fno-omit-frame-pointer"
  tcf = tls_cflags
  if tcf != ""
    compile_flags += " " + tcf
  if needs_zstd
    zcf = zstd_cflags
    if zcf != ""
      compile_flags += " " + zcf
  thresholds_path = runtime_root + "/generated/bigint_thresholds.h"
  generated_thresholds = "absent"
  if file?(thresholds_path)
    generated_thresholds = "present"
  sources = program_runtime_sources(runtime_root, needs_zstd)
  sources_digest = dev_runtime_sources_digest(runtime_root, runtime_kind)
  if sources_digest == nil
    return nil
  archive = dev_runtime_archive_path(cache_dir, sources_digest, cc_identity, ar_identity, compile_flags, sources.join(" "), generated_thresholds)

  # The name is a digest of the sources' contents, the tools and the flags,
  # so an archive that exists is the right one, for any checkout.
  if file?(archive)
    return archive

  if !ensure_driver_dir(cache_dir)
    return nil

  if verbose
    << "Building native runtime archive (one-time)..."

  # Compile in a per-process directory so concurrent builders can never
  # exchange runtime.o files. Build the archive beside its final path and
  # publish with one same-filesystem rename; linkers see either no archive or
  # a complete one, never a partially written ar file, and two builders of
  # the same name publish the same bytes.
  compile_flags += dev_runtime_path_map_flag(runtime_root)

  cc_prefix = cc_command + " " + compile_flags + " -I" + dev_runtime_shell_quote(runtime_root)
  cc = StringBuffer(0)
  cc << "build_dir="
  cc << dev_runtime_shell_quote(archive + ".build.")
  cc << "$$; archive_tmp="
  cc << dev_runtime_shell_quote(archive + ".tmp.")
  cc << "$$; rm -rf \"$build_dir\" \"$archive_tmp\" && mkdir -p \"$build_dir\" && cd \"$build_dir\" && "
  cc << parallel_runtime_compile_shell(cc_prefix, runtime_root, sources)
  cc << " && "
  cc << ar_command
  cc << " rcs \"$archive_tmp\" "
  cc << runtime_object_names(sources)
  cc << " && mv -f \"$archive_tmp\" "
  cc << dev_runtime_shell_quote(archive)
  cc << "; status=$?; rm -rf \"$build_dir\" \"$archive_tmp\"; exit $status"
  if system(cc.to_s()) != true
    return nil
  archive

-> dev_runtime_lto_objects_path(cache_dir, sources_digest, cc_identity, compile_flags, source_list, generated_thresholds)
  config = StringBuffer(0)
  config << "dev-runtime-lto-v4\n"
  config << sources_digest
  config << "\ncc="
  config << cc_identity
  config << "\nflags="
  config << compile_flags
  config << "\nsources="
  config << source_list
  config << "\nthresholds="
  config << generated_thresholds
  config << "\n"
  dev_runtime_append_env(config, "SDKROOT")
  dev_runtime_append_env(config, "MACOSX_DEPLOYMENT_TARGET")
  dev_runtime_append_env(config, "CPATH")
  dev_runtime_append_env(config, "C_INCLUDE_PATH")
  dev_runtime_append_env(config, "CPLUS_INCLUDE_PATH")
  dev_runtime_append_env(config, "LIBRARY_PATH")
  dev_runtime_append_env(config, "PKG_CONFIG_PATH")
  dev_runtime_append_env(config, "PKG_CONFIG_LIBDIR")
  cache_dir + "/runtime-lto-" + wyhash64_hex_string(config.to_s())

-> dev_runtime_lto_objects(compiler_image_runtime_profile = false, verbose = false, needs_zstd = false, needs_gc = false)
  clang_opt = env("TUNGSTEN_CLANG_OPT")
  if clang_opt != nil && clang_opt.index("-fprofile") != nil
    return nil
  runtime_dir = resolve_runtime_dir
  runtime_kind = runtime_identity()
  runtime_root = dev_runtime_source_identity(runtime_dir, runtime_kind)
  cc_command = host_c_compiler()
  cc_identity = dev_runtime_cc_identity(cc_command, runtime_kind)
  if cc_identity == nil
    return nil
  cache_dir = compiler_cache_dir()
  if cache_dir == nil
    return nil
  opt_flag = runtime_lto_opt_flag(clang_opt)
  compile_flags = opt_flag + " " + debug_compile_flag() + " " + march_flags() + " -fmerge-all-constants"
  compile_flags += " " + lto_mode_flag()
  if !needs_gc
    compile_flags += " -DW_COMPILE_NO_GC"
  if frame_pointers
    compile_flags += " -fno-omit-frame-pointer"
  if compiler_image_runtime_profile
    compile_flags += " -DTUNGSTEN_RUNTIME_COMPILER_IMAGE=1"
  if detect_target()[:os] == "macos"
    compile_flags += " -fveclib=Darwin_libsystem_m"
  tcf = tls_cflags
  if tcf != ""
    compile_flags += " " + tcf
  if needs_zstd
    zcf = zstd_cflags
    if zcf != ""
      compile_flags += " " + zcf
  thresholds_path = runtime_root + "/generated/bigint_thresholds.h"
  generated_thresholds = file?(thresholds_path) ? "present" : "absent"
  sources = program_runtime_sources(runtime_root, needs_zstd)
  sources_digest = dev_runtime_sources_digest(runtime_root, runtime_kind)
  if sources_digest == nil
    return nil
  bundle_dir = dev_runtime_lto_objects_path(cache_dir, sources_digest, cc_identity, compile_flags, sources.join(" "), generated_thresholds)
  # Content-named: a bundle whose .ready marker exists is complete and right.
  if file?(bundle_dir + "/.ready")
    return bundle_dir + "/*.o"

  if !ensure_driver_dir(cache_dir)
    return nil

  if verbose
    << "Building LTO runtime objects (one-time)..."

  compile_flags += dev_runtime_path_map_flag(runtime_root)

  cc_prefix = cc_command + " " + compile_flags + " -I" + dev_runtime_shell_quote(runtime_root)
  cc = StringBuffer(0)
  # Build in a private directory and publish it with one rename. A published
  # bundle is never replaced or moved aside: a linker may be reading it, and
  # a second builder of the same name made the same objects. If that builder
  # lost the race its rename lands inside the winner's directory (where no
  # *.o glob sees it) and is removed again.
  cc << "bundle="
  cc << dev_runtime_shell_quote(bundle_dir)
  cc << "; build_dir=\"$bundle.build.$$\"; rm -rf \"$build_dir\" && mkdir -p \"$build_dir\" && cd \"$build_dir\" && "
  cc << parallel_runtime_compile_shell(cc_prefix, runtime_root, sources)
  cc << " && touch .ready && cd / && { test -e \"$bundle/.ready\" || mv \"$build_dir\" \"$bundle\" 2>/dev/null || true; }"
  cc << "; rm -rf \"$build_dir\" \"$bundle/$(basename \"$build_dir\")\"; test -e \"$bundle/.ready\""
  if system(cc.to_s()) != true
    return nil
  bundle_dir + "/*.o"

-> dev_runtime_companion_object(rel_source, doing_lto, extra_cflags = "")
  if cross_target != ""
    return nil
  clang_opt = env("TUNGSTEN_CLANG_OPT")
  if clang_opt != nil && clang_opt.index("-fprofile") != nil
    return nil
  runtime_dir = resolve_runtime_dir
  runtime_kind = runtime_identity()
  runtime_root = dev_runtime_source_identity(runtime_dir, runtime_kind)
  cc_command = host_c_compiler()
  cc_identity = dev_runtime_cc_identity(cc_command, runtime_kind)
  if cc_identity == nil
    return nil
  cache_dir = compiler_cache_dir()
  if cache_dir == nil
    return nil
  opt_flag = (clang_opt != nil && clang_opt != "") ? clang_opt : profile_opt_flag()
  compile_flags = opt_flag + " " + debug_compile_flag() + " " + march_flags() + " -fmerge-all-constants"
  if doing_lto
    compile_flags += " " + lto_mode_flag()
  if frame_pointers
    compile_flags += " -fno-omit-frame-pointer"
  if detect_target()[:os] == "macos"
    compile_flags += " -fveclib=Darwin_libsystem_m"
  tcf = tls_cflags
  if tcf != ""
    compile_flags += " " + tcf
  if extra_cflags != ""
    compile_flags += " " + extra_cflags
  sources_digest = dev_runtime_sources_digest(runtime_root, runtime_kind)
  if sources_digest == nil
    return nil
  config = StringBuffer(256)
  config << "companion-obj-v3\n"
  config << sources_digest
  config << "\nsrc="
  config << rel_source
  config << "\ncc="
  config << cc_identity
  config << "\nflags="
  config << compile_flags
  config << "\n"
  dev_runtime_append_env(config, "SDKROOT")
  dev_runtime_append_env(config, "MACOSX_DEPLOYMENT_TARGET")
  dev_runtime_append_env(config, "CPATH")
  dev_runtime_append_env(config, "C_INCLUDE_PATH")
  dev_runtime_append_env(config, "CPLUS_INCLUDE_PATH")
  safe_name = rel_source.gsub("/", "_").gsub(".", "_")
  obj_path = cache_dir + "/companion-" + safe_name + "-" + wyhash64_hex_string(config.to_s()) + ".o"
  src_path = runtime_root + "/" + rel_source
  # Content-named (the digest covers the source and every runtime header):
  # an object that exists is the right one, for any checkout.
  if file?(obj_path)
    return obj_path
  if !ensure_driver_dir(cache_dir)
    return nil
  tmp_obj = dev_runtime_shell_quote(obj_path + ".tmp.") + "$$"
  cmd = cc_command + " " + compile_flags + dev_runtime_path_map_flag(runtime_root) + " -I" + dev_runtime_shell_quote(runtime_root) + " -c " + dev_runtime_shell_quote(src_path) + " -o " + tmp_obj + " && mv -f " + tmp_obj + " " + dev_runtime_shell_quote(obj_path) + "; status=$?; rm -f " + tmp_obj + "; exit $status"
  if system(cmd) != true
    return nil
  obj_path

-> compile_runtime_objs(tmp_dir, needs_zstd = false, verbose = false)
  # Compile the shared runtime once into a private object bundle. Do not put
  # these objects in an archive: Apple clang emits a mixture of LTO bitcode
  # and native Mach-O for this source set, and Apple ar turns that mixture
  # into a universal archive whose host slice silently omits the bitcode.
  # Passing the objects directly lets clang consume both representations and
  # preserves LTO across the emitted program and the bitcode members.
  runtime_dir = File.expand_path(resolve_runtime_dir)
  object_glob = tmp_dir + "/*.o"

  cc_prefix = StringBuffer(0)
  cc_prefix << host_c_compiler()
  cc_prefix << " "
  cc_prefix << cross_compile_flags()
  cc_prefix << profile_opt_flag()
  cc_prefix << " "
  cc_prefix << debug_compile_flag()
  cc_prefix << " "
  cc_prefix << march_flags()
  cc_prefix << " "

  if needs_zstd
    zcf = zstd_cflags

    if zcf != ""
      cc_prefix << zcf
      cc_prefix << " "

  tcf = tls_cflags
  if tcf != ""
    cc_prefix << tcf
    cc_prefix << " "

  if (release_mode || explicit_lto || full_lto) && !no_lto
    cc_prefix << lto_mode_flag()
    cc_prefix << " "

  if frame_pointers
    cc_prefix << "-fno-omit-frame-pointer "

  cc_prefix << "-I"
  cc_prefix << dev_runtime_shell_quote(runtime_dir)

  cc = StringBuffer(0)
  cc << "cd "
  cc << dev_runtime_shell_quote(tmp_dir)
  cc << " && "
  cc << parallel_runtime_compile_shell(cc_prefix.to_s(), runtime_dir, program_runtime_sources(runtime_dir, needs_zstd))

  << "Compiling runtime..."

  compile_started_at = clock
  result = system(cc.to_s())
  log_phase(verbose, "runtime compile", compile_started_at)

  if result != true
    return nil

  object_glob
