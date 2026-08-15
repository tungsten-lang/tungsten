
-> phase_elapsed(started_at)
  clock - started_at

-> log_phase(verbose, name, started_at)
  if verbose
    << fmt_elapsed(phase_elapsed(started_at)) + " " + name

-> ll_needs_zstd_text(text)
  if text == nil
    return false
  if ll_code_has(text, "@w_slab_init_static_zstd(")
    return true
  ll_code_has(text, "@w_zstd_compress_llvm_escaped(")

-> ll_needs_zstd_path(ll_path)
  ll_needs_zstd_text(read_file(ll_path))

-> zstd_runtime_source
  if cross_target != "" && env("TUNGSTEN_CROSS_ZSTD_LDFLAGS") == nil
    return "slab_zstd_stub.c"
  "slab_zstd.c"

# Does the emitted module reference any Apple GPU/graphics/HID bridge symbol?
# Only then are metal.m/graphics.m/hid_bridge.m (and, via their ObjC
# autolinking, the Metal/AppKit/QuartzCore/IOKit frameworks) linked; other
# programs use weak stubs in the runtime translation units and start ~2ms warm with a far
# cheaper first-run dyld closure.
-> ll_text_has(text, needle)
  if text == nil
    return false
  text.index(needle) != nil

# Search LLVM syntax while ignoring bytes embedded in quoted `c"..."`
# constants. The compiler contains its own linker probes as source strings;
# treating those bytes as symbol references made the lean image pull every
# optional bridge, framework, and dynamic export that it only knew how to
# link. LLVM escaped strings are single-line, so skipping the containing line
# is sufficient and avoids parsing the full module into an AST.
-> ll_code_has(text, needle)
  if text == nil
    return false
  search_from = 0
  while search_from < text.size()
    found = text.index(needle, search_from)
    if found == nil
      return false
    line_start = text.rindex("\n", found)
    if line_start == nil
      line_start = 0
    else
      line_start += 1
    line_end = text.index("\n", found)
    if line_end == nil
      line_end = text.size()
    quoted_constant = text.index("c\"", line_start)
    if quoted_constant == nil || quoted_constant >= line_end || quoted_constant > found
      return true
    search_from = line_end + 1
  false

-> ll_needs_lexchars(text)
  if ll_text_has(text, "lchs") || ll_text_has(text, "lexchars")
    return true
  # Short method names are emitted as inline-string WValue constants, so an
  # ordinary `.lchs()` call may leave no readable "lchs" text in the module.
  # Recognize the exact SSO-5 method-name literal used by its inline cache.
  ll_text_has(text, wvalue_literal_text(sso5_wvalue("lchs")))

-> ll_needs_unicode(text)
  # String normalization / grapheme segmentation ccalls, plus the approx
  # operator (its runtime handler NFC-compares string operands); long
  # extern names are always literal text in the module.
  ll_code_has(text, "@w_string_normalize") || ll_code_has(text, "@w_string_grapheme_next") || ll_code_has(text, "@w_approx_eq")

-> ll_needs_apple_bridges(text)
  if ll_code_has(text, "@w_metal_")
    return true
  if ll_code_has(text, "@w_gfx_")
    return true
  if ll_code_has(text, "@w_hid_")
    return true
  # Fused elementwise GPU auto-offload (metal.m); the runtime.c weak stub
  # keeps non-bridged links working, but the real impl needs metal.m.
  if ll_code_has(text, "@w_fused_gpu_run")
    return true
  ll_code_has(text, "@w_gpu_")

# Accelerate BLAS is a separate conditional: a matmul program should not
# pull the GUI/GPU frameworks, and a plain program should not pull
# Accelerate. Real impls in runtime/blas_bridge.c override the weak stubs.
-> ll_needs_blas(text)
  if ll_code_has(text, "@w_blas_")
    return true
  if ll_code_has(text, "@w_array_cos_")
    return true
  if ll_code_has(text, "@w_array_sin_")
    return true
  if ll_code_has(text, "@w_array_sqrt_")
    return true
  if ll_code_has(text, "@w_array_exp_")
    return true
  if ll_code_has(text, "@w_array_log_")
    return true
  ll_code_has(text, "@w_array_tan_")

-> ll_needs_sparse(text)
  ll_code_has(text, "@w_sparse_")

-> ll_needs_sci_io(text)
  ll_code_has(text, "@w_sci_")

-> ll_needs_wtensor(text)
  ll_code_has(text, "@w_tensor_")

-> ll_needs_cuda(text)
  ll_code_has(text, "@w_cuda_")

# MLX (Apple array framework, via mlx-c). The bf16/f16 conversion helpers
# also live in mlx_bridge.c, so their prefix gates the bridge too.
-> ll_needs_mlx(text)
  return true if ll_code_has(text, "@w_mlx_")
  ll_code_has(text, "@w_f32_to_")

# Standalone executables have no dynamic ABI: Tungsten functions/classes are
# already internal, and their runtime calls are resolved in the final link.
# The compiler's --jit/--hot host is the exception. Its snippets deliberately
# omit the runtime and resolve w_int/w_add/... from the host process, so that
# executable must publish its runtime symbols. A force-on escape hatch covers
# custom embedding hosts that use the same contract without calling the built-in
# object loader directly.
-> ll_needs_dynamic_exports(text)
  if env("TUNGSTEN_DYNAMIC_EXPORTS") == "1"
    return true
  ll_code_has(text, "@w_jit_load_object(")

# System library flag probes. Each shells out via capture() — fork+exec+pipe
# is ~10-30ms per call, and we do 9 of them per compile. To skip them on
# rebuilds, the driver (bin/commands/build.rb) caches the resolved flags in
# build/cache/system-deps.marshal and passes them down via TUNGSTEN_*
# env vars. When the env var is set (even to ""), we treat that as the
# resolved value and skip capture(). An unset env var means "no driver
# pre-resolved them, fall back to runtime probing" — preserves behavior
# when the compiler is invoked outside bin/tungsten build.

driver_homebrew_prefix_memo = {}

-> driver_homebrew_prefix(formula)
  key = formula == "" ? :root : formula.to_sym()
  cached = driver_homebrew_prefix_memo[key]
  if cached != nil
    return cached
  cmd = "brew --prefix"
  if formula != ""
    cmd = cmd + " " + formula
  prefix = capture(cmd + " 2>/dev/null").strip()
  driver_homebrew_prefix_memo[key] = prefix
  prefix

-> mlx_cflags
  brew = driver_homebrew_prefix("")
  if brew != "" && file?(brew + "/include/mlx/c/array.h")
    return "-I" + brew + "/include"
  ""

-> mlx_ldflags
  brew = driver_homebrew_prefix("")
  if brew != "" && file?(brew + "/lib/libmlxc.dylib")
    return "-L" + brew + "/lib -lmlxc -lmlx"
  ""

-> zstd_cflags
  if cross_target != ""
    cross_flags = env("TUNGSTEN_CROSS_ZSTD_CFLAGS")
    return cross_flags == nil ? "" : cross_flags
  cached = env("TUNGSTEN_ZSTD_CFLAGS")
  if cached != nil
    return cached
  flags = capture("pkg-config --cflags libzstd 2>/dev/null").strip()
  if flags != ""
    return flags
  brew = driver_homebrew_prefix("")
  if brew != "" && file?(brew + "/include/zstd.h")
    return "-I" + brew + "/include"
  ""

-> zstd_ldflags
  if cross_target != ""
    cross_flags = env("TUNGSTEN_CROSS_ZSTD_LDFLAGS")
    return cross_flags == nil ? "" : cross_flags
  cached = env("TUNGSTEN_ZSTD_LDFLAGS")
  if cached != nil
    return cached
  flags = capture("pkg-config --libs libzstd 2>/dev/null").strip()
  if flags != ""
    return flags
  brew = driver_homebrew_prefix("")
  if brew != "" && (file?(brew + "/lib/libzstd.dylib") || file?(brew + "/lib/libzstd.a"))
    return "-L" + brew + "/lib -lzstd"
  "-lzstd"

-> onig_cflags
  if cross_target != ""
    cross_flags = env("TUNGSTEN_CROSS_ONIG_CFLAGS")
    return cross_flags == nil ? "" : cross_flags
  cached = env("TUNGSTEN_ONIG_CFLAGS")
  if cached != nil
    return cached
  flags = capture("pkg-config --cflags oniguruma 2>/dev/null").strip()
  if flags != ""
    return flags + " -DTUNGSTEN_ONIG"
  brew = driver_homebrew_prefix("")
  if brew != "" && file?(brew + "/include/oniguruma.h")
    return "-I" + brew + "/include -DTUNGSTEN_ONIG"
  ""

-> onig_ldflags
  if cross_target != ""
    cross_flags = env("TUNGSTEN_CROSS_ONIG_LDFLAGS")
    return cross_flags == nil ? "" : cross_flags
  cached = env("TUNGSTEN_ONIG_LDFLAGS")
  if cached != nil
    return cached
  flags = capture("pkg-config --libs oniguruma 2>/dev/null").strip()
  if flags != ""
    return flags
  if onig_cflags != ""
    brew = driver_homebrew_prefix("")
    if brew != "" && (file?(brew + "/lib/libonig.dylib") || file?(brew + "/lib/libonig.a"))
      return "-L" + brew + "/lib -lonig"
    return "-lonig"
  ""

-> tls_requested?
  env("TLS") != nil || env("TUNGSTEN_TLS") != nil

-> tls_cflags
  return "" if !tls_requested?()
  if cross_target != ""
    flags = env("TUNGSTEN_CROSS_TLS_CFLAGS")
    if flags == nil || flags == ""
      raise "TLS cross-compilation requires TUNGSTEN_CROSS_TLS_CFLAGS"
    return flags + " -DTUNGSTEN_TLS"
  cached = env("TUNGSTEN_TLS_CFLAGS")
  if cached != nil && cached != ""
    return cached + " -DTUNGSTEN_TLS"
  flags = capture("pkg-config --cflags openssl 2>/dev/null").strip()
  if flags != ""
    return flags + " -DTUNGSTEN_TLS"
  prefix = driver_homebrew_prefix("openssl@3")
  if prefix != "" && file?(prefix + "/include/openssl/ssl.h")
    return "-I" + prefix + "/include -DTUNGSTEN_TLS"
  if file?("/usr/include/openssl/ssl.h")
    return "-DTUNGSTEN_TLS"
  raise "TLS requested but OpenSSL headers were not found"

-> tls_ldflags
  return "" if !tls_requested?()
  if cross_target != ""
    flags = env("TUNGSTEN_CROSS_TLS_LDFLAGS")
    if flags == nil || flags == ""
      raise "TLS cross-compilation requires TUNGSTEN_CROSS_TLS_LDFLAGS"
    return flags
  cached = env("TUNGSTEN_TLS_LDFLAGS")
  if cached != nil && cached != ""
    return cached
  flags = capture("pkg-config --libs openssl 2>/dev/null").strip()
  if flags != ""
    return flags
  prefix = driver_homebrew_prefix("openssl@3")
  if prefix != "" && file?(prefix + "/lib/libssl.dylib")
    return "-L" + prefix + "/lib -lssl -lcrypto"
  "-lssl -lcrypto"

-> tls_runtime_source
  tls_requested?() ? "tls.c" : "tls_stub.c"

# mimalloc for compiled binaries — OPT-IN via TUNGSTEN_MIMALLOC=1. The
# runtime is malloc-heavy and mimalloc measured -15.5% on new_string /
# -11% on new_hash (macOS: zone registration; Linux: link-order malloc
# interposition, validated in ubuntu:24.04 docker). NOT the default:
# on macOS 26 (xzone malloc) homebrew mimalloc 3.4's zone interposition
# SIGSEGVs when LIBC-INTERNAL allocation runs through it — a two-line C
# repro is just realpath(path, NULL) linked against libmimalloc.a
# (crash in mi_theap_malloc_zero_aligned_at_generic). Any binary touching
# realpath/getaddrinfo-style paths would be a landmine, so the measured
# alloc-family win stays behind an explicit flag until a fixed mimalloc
# release is verified.
-> mimalloc_link_flags
  if env("TUNGSTEN_MIMALLOC") != "1"
    return ""
  candidates = ["/usr/local/lib/libmimalloc.a", "/usr/lib/libmimalloc.a"]
  brew = driver_homebrew_prefix("")
  if brew != ""
    candidates.unshift(brew + "/lib/libmimalloc.a")
  found = ""
  candidates.each ->(c)
    if found == "" && file?(c)
      found = c
  if found != ""
    return found
  # Debian/Ubuntu multiarch ships only the shared lib
  # (/usr/lib/<triple>/libmimalloc.so, package libmimalloc-dev). Linking the
  # .so ahead of libc interposes malloc for this binary. Validated on
  # ubuntu:24.04 arm64 (glibc 6.34 -> mimalloc 5.70 ns/op on a malloc micro
  # -- a smaller win than macOS's xzone 11 -> 4 ns, but still positive).
  on linux
    found = capture("ls /usr/lib/*/libmimalloc.a /usr/lib/*/libmimalloc.so 2>/dev/null | head -1").strip()
    if found != ""
      return found
  ""

-> archive_tool
  ar = env("TUNGSTEN_AR")
  if ar == nil || ar == ""
    return "ar"
  ar

-> ranlib_tool
  ranlib = env("TUNGSTEN_RANLIB")
  if ranlib == nil || ranlib == ""
    return ""
  ranlib

-> rewrite_ir_static_slab_zstd(ir)
  global_prefix = "@__static_slab = private constant \["
  global_pos = ir.index(global_prefix)

  if global_pos == nil
    return ir

  raw_call_prefix = "call void @w_slab_init_static(ptr @__static_slab, i32 "
  raw_call_pos = ir.index(raw_call_prefix)

  if raw_call_pos == nil
    return ir

  slot_start = raw_call_pos + raw_call_prefix.size()
  slot_tail = ir.slice(slot_start, ir.size() - slot_start)
  slot_end = slot_tail.index(")")

  if slot_end == nil
    return ir

  total_slots = slot_tail.slice(0, slot_end)

  quote = "\""
  blob_marker = " x i8] c" + quote
  bytes_start = global_pos + global_prefix.size()
  bytes_tail = ir.slice(bytes_start, ir.size() - bytes_start)
  blob_marker_pos = bytes_tail.index(blob_marker)

  if blob_marker_pos == nil
    return ir

  blob_start = bytes_start + blob_marker_pos + blob_marker.size()
  blob_tail = ir.slice(blob_start, ir.size() - blob_start)
  blob_end = blob_tail.index(quote)

  if blob_end == nil
    return ir

  escaped_blob = blob_tail.slice(0, blob_end)
  packed = ccall("w_zstd_compress_llvm_escaped", escaped_blob)
  escaped_zstd = packed[0]
  compressed_bytes = packed[1]

  line_tail = ir.slice(global_pos, ir.size() - global_pos)
  line_end = line_tail.index("\n")

  if line_end == nil
    old_global_len = ir.size() - global_pos
  else
    old_global_len = line_end

  new_global = "@__static_slab_zstd = private constant \[" + compressed_bytes.to_s() + " x i8] c" + quote + escaped_zstd + quote + ", align 8"
  ir = ir.slice(0, global_pos) + new_global + ir.slice(global_pos + old_global_len, ir.size() - global_pos - old_global_len)

  old_call = "call void @w_slab_init_static(ptr @__static_slab, i32 " + total_slots + ")"
  new_call = "call void @w_slab_init_static_zstd(ptr @__static_slab_zstd, i32 " + compressed_bytes.to_s() + ", i32 " + total_slots + ")"
  ir = ir.replace(old_call, new_call)
  ir.replace("declare void @w_slab_init_static(ptr, i32)", "declare void @w_slab_init_static_zstd(ptr, i32, i32)")

# Ordinary native compiles used to share `/tmp/tungsten/<basename>.ll`.
# Distinct entry points such as `bin/metaflip.w` and `lib/metaflip.w` could
# therefore overwrite one another between IR emission and clang opening the
# file. Give every compiler process an atomically-created private directory;
# after the link we publish the complete IR back to the historical diagnostic
# path so existing tooling that reads `/tmp/tungsten/<basename>.ll` keeps
# working. Explicit TUNGSTEN_LL_PATH and `--ll` paths remain caller-owned.
-> implicit_ll_root
  ll_dir = env("TUNGSTEN_LL_DIR")
  if ll_dir == nil || ll_dir == ""
    ll_dir = "/tmp/tungsten"
  if system("mkdir -p " + dev_runtime_shell_quote(ll_dir)) != true
    raise "Could not create LLVM scratch directory " + ll_dir
  ll_dir

-> implicit_ll_path(file_path)
  ll_dir = implicit_ll_root()
  build_dir = capture("mktemp -d " + dev_runtime_shell_quote(ll_dir + "/compile.XXXXXX") + " 2>/dev/null").strip()
  if build_dir == ""
    raise "Could not create a private LLVM scratch directory under " + ll_dir
  build_dir + "/" + file_path.split("/").last().replace(".w", ".ll")

-> uses_implicit_ll_path
  explicit = env("TUNGSTEN_LL_PATH")
  (explicit == nil || explicit == "") && !keep_ll

-> publish_implicit_ll_path(ll_path, file_path)
  stable_path = implicit_ll_root() + "/" + file_path.split("/").last().replace(".w", ".ll")
  ok = system("mv -f " + dev_runtime_shell_quote(ll_path) + " " + dev_runtime_shell_quote(stable_path)) == true
  done_path = ll_path + ".done"
  if file?(done_path)
    ok = system("mv -f " + dev_runtime_shell_quote(done_path) + " " + dev_runtime_shell_quote(stable_path + ".done")) == true && ok
  parts = ll_path.split("/")
  parts.pop()
  z = system("rmdir " + dev_runtime_shell_quote(parts.join("/")) + " 2>/dev/null")
  ok

-> gpu_dialect_selection(raw, file_path, node)
  if raw == nil
    return {cuda: true, wgsl: false}
  if raw == ""
    return {cuda: false, wgsl: false}
  if raw.starts_with?(",") || raw.ends_with?(",") || raw.include?(",,")
    raise compile_error_for_node(
      :E_GPU_DIALECTS,
      "empty GPU dialect in TUNGSTEN_GPU_DIALECTS value '" + raw + "'",
      file_path,
      node)

  requested = raw.split(",")
  seen = {}
  i = 0
  while i < requested.size()
    name = requested[i].strip()
    if name == "" || !(name in ("metal" "cuda" "wgsl" "none"))
      raise compile_error_for_node(
        :E_GPU_DIALECTS,
        "invalid TUNGSTEN_GPU_DIALECTS value '" + raw + "' (expected a comma list of metal, cuda, wgsl, or none)",
        file_path,
        node)
    if seen[name] == true
      raise compile_error_for_node(
        :E_GPU_DIALECTS,
        "duplicate GPU dialect '" + name + "' in TUNGSTEN_GPU_DIALECTS",
        file_path,
        node)
    seen[name] = true
    i += 1

  if seen["none"] == true && requested.size() != 1
    raise compile_error_for_node(
      :E_GPU_DIALECTS,
      "GPU dialect 'none' cannot be combined with another dialect",
      file_path,
      node)
  {cuda: seen["cuda"] == true, wgsl: seen["wgsl"] == true}

# Validate and render every selected GPU dialect immediately after parsing.
# Compile reuses these strings later, so this is a real pre-pass rather than a
# second emitter run; check calls the same path without writing any sidecars.
-> gpu_preflight_validate(kernels, selection, file_path)
  failures = []
  i = 0
  while i < kernels.size()
    failure = nil
    dialect = "metal"
    begin
      gpu_emitter.emit_metal(kernels, i)
    rescue err
      if type(err) == "Hash" && err[:rt] == :compile_error
        failure = err
      else
        raise err

    if failure == nil && selection[:cuda]
      dialect = "cuda"
      begin
        gpu_emitter.emit_cuda(kernels, i)
      rescue err
        if type(err) == "Hash" && err[:rt] == :compile_error
          failure = err
        else
          raise err

    if failure == nil && selection[:wgsl]
      dialect = "wgsl"
      begin
        gpu_emitter.emit_wgsl(kernels, i)
      rescue err
        if type(err) == "Hash" && err[:rt] == :compile_error
          failure = err
        else
          raise err

    if failure != nil
      if failure[:file] == nil
        failure[:file] = file_path
      failures.push({node: kernels[i], dialect: dialect, error: failure})
    i += 1

  if failures.size() == 1
    raise failures[0][:error]
  if failures.size() > 1
    message = StringBuffer(256)
    message << failures.size().to_s()
    message << " independent @gpu functions failed preflight:"
    i = 0
    while i < failures.size()
      entry = failures[i]
      message << "\n  "
      message << (i + 1).to_s()
      message << ". `"
      message << entry[:node].name.to_s()
      message << "` \["
      message << entry[:dialect]
      message << "\] at line "
      message << entry[:node].line.to_s()
      message << ": "
      detail = entry[:error][:message].to_s().replace("\n", "\n     ")
      message << detail
      i += 1
    first = failures[0][:error]
    first[:message] = message.to_s()
    raise first
  nil

-> gpu_preflight(ast, file_path)
  if !gpu_emitter.available?() && gpu_emitter.contains_kernel?(ast)
    delegate_compiler_image("metal")
  kernels = gpu_emitter.collect(ast)
  if kernels.size() == 0
    return {kernels: kernels, metal: nil, cuda: nil, wgsl: nil}

  selection = gpu_dialect_selection(env("TUNGSTEN_GPU_DIALECTS"), file_path, kernels[0])
  begin
    metal_text = gpu_emitter.emit_metal(kernels)
    cuda_text = nil
    wgsl_text = nil
    if selection[:cuda]
      cuda_text = gpu_emitter.emit_cuda(kernels)
    if selection[:wgsl]
      wgsl_text = gpu_emitter.emit_wgsl(kernels)
  rescue err
    if type(err) == "Hash" && err[:rt] == :compile_error && err[:file] == nil
      err[:file] = file_path
    # Keep valid compilation on the one-pass fast path. Only after a selected
    # dialect rejects the program do we isolate each function, retaining the
    # full helper signature registry, so one check can report independent
    # failures without making every successful GPU build emit N extra times.
    if type(err) == "Hash" && err[:rt] == :compile_error
      gpu_preflight_validate(kernels, selection, file_path)
    raise err

  {kernels: kernels, metal: metal_text, cuda: cuda_text, wgsl: wgsl_text}

# `-e` compiles a materialized cache file, but users wrote "(eval)". The
# loader keeps the real path (it must read the file); only the path handed
# to lowering — and therefore embedded in runtime diagnostics — is aliased.
-> display_source_path(p)
  if eval_source_alias != nil && p == eval_source_alias
    return "(eval)"
  p

# Persistent lowered-Core snapshots are scoped to the exact compiler
# executable.  Core source contents and lowering flags live in the cache key;
# path + nanosecond metadata + size keep two compiler builds from exchanging
# WIRE without hashing the whole executable on every fresh invocation.
-> configure_persistent_core_cache
  if g_incremental[:core_cache_context_ready] == true
    return nil
  g_incremental[:core_cache_context_ready] = true
  if runtime_identity() != "compiled-runtime" || env("TUNGSTEN_CORE_DISK_CACHE") == "0"
    return nil
  dir = compiler_cache_dir()
  if dir == nil || system("mkdir -p " + dev_runtime_shell_quote(dir)) != true
    return nil
  exe = ccall("w_executable_path")
  stat = File.stat(exe)
  if stat == nil || stat.mtime_ns() == nil || stat.ctime_ns() == nil || stat.size() == nil
    return nil
  identity_text = ["core-wire-executable-v1", exe, stat.mtime_ns().to_s(), stat.ctime_ns().to_s(), stat.size().to_s(), incremental_env_s("TUNGSTEN_VERSION")].join("|")
  identity = wyhash64_hex_string(identity_text)
  incremental_core_cache_configure_persistent(dir, identity)
  if env("TUNGSTEN_LIBRARY_WIRE_DISK_CACHE") != "0"
    incremental_library_cache_configure_persistent(dir, identity)
  function_emit_cache_configure_persistent(dir, identity)
  nil

-> configure_target_probe_cache
  if g_incremental[:target_cache_context_ready] == true
    return nil
  g_incremental[:target_cache_context_ready] = true
  if runtime_identity() != "compiled-runtime" || env("TUNGSTEN_TARGET_DISK_CACHE") == "0"
    return nil
  dir = compiler_cache_dir()
  if dir == nil || system("mkdir -p " + dev_runtime_shell_quote(dir)) != true
    return nil
  target_probe_cache_configure(dir)
  nil

-> emit_ir(file_path, emit_wire, verbose, intern_algo, sidemap_path = nil, emit_ll_only_arg = false, build_defines = nil, no_static_slab = false)
  # Emit LLVM IR (or WIRE text) for a single file, return ll_path or nil
  configure_target_probe_cache()
  configure_persistent_core_cache()
  loader = Loader.new(verbose)
  load_started_at = clock
  ast = loader.load_program_ast(file_path)
  gpu_artifacts = gpu_preflight(ast, file_path)
  g_incremental[:manifest] = loader.manifest_files()
  if ast_stats
    count_kinds(ast, g_ast_stats_counts)
  if env("TUNGSTEN_STOP_AFTER_LOAD_PARSE") == "1"
    if verbose
      << ""
      << fmt_elapsed(phase_elapsed(load_started_at)) + " load+parse"
    exit 0
  if env("TUNGSTEN_SPINEL_STAGE0_CALL_TRACE") == "1"
    test_h = {expressions: [1]}
    if test_h["expressions"] == nil
      write_file("/tmp/tungsten-stage0-test-hash-string-nil", "x")
    else
      write_file("/tmp/tungsten-stage0-test-hash-string-present", "x")
    if test_h[:expressions] == nil
      write_file("/tmp/tungsten-stage0-test-hash-symbol-nil", "x")
    else
      write_file("/tmp/tungsten-stage0-test-hash-symbol-present", "x")
    if ast == nil
      write_file("/tmp/tungsten-stage0-ast-nil", "x")
    else
      write_file("/tmp/tungsten-stage0-ast-not-nil", "x")
      if ast == 0
        write_file("/tmp/tungsten-stage0-ast-zero", "x")
      exprs = ast.expressions
      if exprs == nil
        write_file("/tmp/tungsten-stage0-ast-expressions-nil", "x")
      else
        write_file("/tmp/tungsten-stage0-ast-expressions-present", "x")
        if exprs.size() == 0
          write_file("/tmp/tungsten-stage0-ast-expressions-empty", "x")
        else
          write_file("/tmp/tungsten-stage0-ast-expressions-nonempty", "x")
  t_load = phase_elapsed(load_started_at)

  if emit_wire
    wire_started_at = clock
    mod = compile_to_wire(ast, display_source_path(file_path), verbose, fast_mode, math_mode, loader.manifest_files())

    if verbose
      << fmt_elapsed(phase_elapsed(wire_started_at)) + " lower to wire"

    if optimizations_mode
      report = optimization_report(mod)
      << (optimizations_json ? JSON.encode(report) : optimization_report_text(report))
      return nil

    if tags_mode
      # `--tags`: the dispatch report instead of the wire dump — which
      # typed-overload gates lowered exact-tag vs ancestry (and why), and
      # how every infix +/-/* site routed (static direct worker call,
      # near-miss with one typed operand, or the polymorphic entry).
      << tag_report_text(mod, file_path)
      return nil

    emit_started_at = clock

    << emit_wire_text(mod)

    if verbose
      << fmt_elapsed(phase_elapsed(emit_started_at)) + " emit wire"
    return nil

  if verbose
    << ""
    parse_cache_text = loader.parse_cache_verbose_text()
    if parse_cache_text != nil
      << parse_cache_text
    << fmt_elapsed(t_load) + " load+parse"

  strip_runtime_metadata = release_mode && !debug_enabled
  ir = compile(ast, display_source_path(file_path), verbose, frame_pointers, sidemap_path, strip_runtime_metadata, fast_mode, build_defines, math_mode, no_static_slab, loader.manifest_files())
  if intern_algo == "zstd"
    ir = rewrite_ir_static_slab_zstd(ir)

  explicit_ll_path = env("TUNGSTEN_LL_PATH")
  if explicit_ll_path != nil && explicit_ll_path != ""
    ll_path = explicit_ll_path
  elsif keep_ll
    ll_path = file_path.replace(".w", ".ll")
  else
    ll_path = implicit_ll_path(file_path)

  write_started_at = clock
  write_file(ll_path, ir)
  ll_done_marker = env("TUNGSTEN_LL_DONE_MARKER")
  if ll_done_marker != nil && ll_done_marker != ""
    write_file(ll_done_marker, "done")
  t_write = phase_elapsed(write_started_at)

  if verbose
    << ""
    << fmt_elapsed(t_write) + " write .ll file"
    if keep_ll
      << "Wrote " + ll_path

  if emit_ll_only_arg
    write_file(ll_path + ".done", "done")
    return ll_path

  # Emit a sibling .metal file for each `@gpu fn` found in the program.
  # Runtime dispatch wiring is compile→library→pipeline→dispatch; the
  # .metal file is the artifact we verify: source → MSL → dispatch.
  kernels = gpu_artifacts[:kernels]
  if kernels.size() > 0
    metal_text = gpu_artifacts[:metal]
    # Emit the .metal (and the opt-in .cu/.wgsl sidecars) next to the SOURCE,
    # not next to the .ll. For `-o` the .ll lands in a temp build dir, but the
    # runtime loads the kernel via a source-relative path (read_file →
    # metal_compile_source), so a source-adjacent .metal is what actually runs;
    # deriving from ll_path left `-o` writing a temp .metal and running a stale
    # kernel. Now every rebuild of the source refreshes its companion .metal.
    metal_path = file_path.replace(".w", ".metal")
    explicit_metal_path = env("TUNGSTEN_METAL_PATH")
    if explicit_metal_path != nil && explicit_metal_path != ""
      metal_path = explicit_metal_path
    write_file(metal_path, metal_text)
    if verbose
      << "Wrote " + metal_path + " (" + kernels.size().to_s() + " @gpu fn)"
    # Additional GPU dialects: CUDA C and WGSL sidecars.
    # TUNGSTEN_GPU_DIALECTS is a validated comma list, e.g. "cuda,wgsl" or
    # "none". Invalid/contradictory lists fail before any sidecar is written.
    # Default: emit CUDA always (cross-platform kernel source). WGSL stays
    # opt-in. Set TUNGSTEN_GPU_DIALECTS=none to suppress extras; Metal is
    # always written when kernels are present.
    cuda_text = gpu_artifacts[:cuda]
    wgsl_text = gpu_artifacts[:wgsl]
    if cuda_text != nil
      cuda_path = file_path.replace(".w", ".cu")
      write_file(cuda_path, cuda_text)
      if verbose
        << "Wrote " + cuda_path + " (" + kernels.size().to_s() + " @gpu fn → CUDA)"
    if wgsl_text != nil
      wgsl_path = file_path.replace(".w", ".wgsl")
      write_file(wgsl_path, wgsl_text)
      if verbose
        << "Wrote " + wgsl_path

  return ll_path
