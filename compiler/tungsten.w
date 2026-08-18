use core/integer
use core/numeric/int
use core/numeric/float
use core/numeric/big_int
# String/Symbol#size and #length are source methods on the shared 0xF9 facade.
# Keep the self-host registration explicit for stage-0 loaders predating the
# broad dynamic-receiver autoload gate.
use core/string_native
# The self-host uses StringBuffer pervasively. Keep this explicit so a stage-0
# compiler whose loader predates the constructor-autoload trigger can build the
# first source-size stage after the native IC is removed.
use core/string_buffer
use lib/lexer
use lib/parser
use lib/interpreter
use lib/compiler
use lib/loader
use lib/error_formatter
use lib/return_inference
use lib/metal_emitter
use lib/repl
use lib/hashing

args = argv()
if args.size() == 0
  << "Usage: tungsten (run|check|compile) <file.w>"
  << ""
  << "Commands:"
  << "  run              Compile and run a .w file through WIRE"
  << "  check            Parse and lower a .w file without emitting code"
  << "  compile          Compile a .w file to a native binary"
  << "  compile-batch    Compile multiple .w files"
  << ""
  << "Options:"
  << "  --out FILE       Output path for compiled binary"
  << "  --emit-wire      Emit WIRE IR text instead of LLVM IR"
  << "  --intern ALGO    Static slab encoding (raw or zstd)"
  << "  --no-lto         Disable link-time optimization"
  << "  --frame-pointers Keep frame pointers (for profiling/debugging)"
  << "  --release        -O3, full LTO, no dev checks, reduced metadata"
  << "  --debug          Include symbols, safety checks, and runtime metadata"
  << "  --no-debug       Omit debug symbols and development checks"
  << "  --cpu CPU        Target CPU (v1/v2/v3/v4/native aliases accepted)"
  << "  --native         Shorthand for --cpu native"
  << "  --target TRIPLE  Generate code for a different target triple"
  << "  --fast, -fast    Fast FP: FMA + reassociation + reciprocals + nnan/ninf"
  << "  --strict-math    Strict IEEE 754: no FMA, no contraction"
  << "  --ll             Write LLVM IR (.ll) next to the binary"
  << "  --emit-ll        Write LLVM IR and skip native linking"
  << "  -j, --jobs N     Parallel compile-batch workers (default: auto)"
  << "  --ast            Print the AST and exit"
  << "  --canonical-ast  Print a stable machine-readable AST and exit"
  << "  --lex            Print tokens and exit"
  << "  --tags           Print the dispatch report and exit"
  << "  -e CODE          Evaluate a string of code"
  << "  --interpret      Use the legacy tree-walker for run / -e"
  << "  -v, --verbose    Verbose output / print version"
  << "  --help           Show this help"
  exit 0

command        = "compile"
out_path       = nil
file_path      = nil
eval_code      = nil
emit_wire      = false
tags_mode      = false
verbose        = false
show_ast       = false
show_canonical_ast = false
show_lex       = false
wit_mode       = false
jit_mode       = false
hot_mode       = false
interpret_mode = false
eval_source_alias = nil
no_lto         = false
explicit_lto   = false
frame_pointers = false
keep_ll        = false
emit_ll_only   = false
batch_jobs     = 0
batch_worker_dir = nil
cross_target   = ""
cross_sysroot  = ""
ast_stats      = false
g_ast_stats_counts = {}
g_ast_stats_varnames = {}
g_ast_stats_delta = {}
g_ast_stats_delta_cross = {}
g_ast_stats_meta = {same_arena_real: 0, cross_arena: 0, child_inline: 0, negative_delta: 0}
g_ast_stats_same_kind = {}
release_mode    = false
native_mode     = false
cpu_name        = nil
cpu_explicit    = false
cpu_target_mode = "native"
debug_requested = false
no_debug_requested = false
debug_enabled   = false
dev_mode        = false
fast_mode       = false
math_mode       = :precise
# Incremental-cache channel out of emit_ir (mutated, never reassigned —
# fn-body assignment to a top-level var would shadow, not write).
g_incremental  = {manifest: nil, core_cache_context_ready: false, target_cache_context_ready: false}
intern_algo    = "raw"
runtime_archive = nil
# Build-time defines from `-D NAME=VALUE` args. Accumulates across
# multiple -D flags. Passed through to lowering via mod[:build_defines].
build_defines  = {}
script_args    = []
parsing_script_args = false

# Parse flags
i = 0
while i < args.size()
  arg = args[i]
  if parsing_script_args
    script_args.push(arg)
  elsif arg == "--"
    parsing_script_args = true
  elsif arg in ("--help" "-h")
    << "Usage: tungsten (run|check|compile) <file.w>"
    << ""
    << "Commands:"
    << "  run              Compile and run a .w file through WIRE"
    << "  check            Parse and lower a .w file without emitting code"
    << "  compile          Compile a .w file to a native binary"
    << "  compile-batch    Compile multiple .w files"
    << ""
    << "Options:"
    << "  --out FILE       Output path for compiled binary"
    << "  --emit-wire      Emit WIRE IR text instead of LLVM IR"
    << "  --intern ALGO    Static slab encoding (raw or zstd)"
    << "  --no-lto         Disable link-time optimization"
    << "  --lto            Whole-program LTO (leaner binary; default links a fast native runtime archive)"
    << "  --frame-pointers Keep frame pointers (for profiling/debugging)"
    << "  --release        -O3, full LTO, no dev checks, reduced metadata"
    << "  --debug          Include symbols, safety checks, and runtime metadata"
    << "  --no-debug       Omit debug symbols and development checks"
    << "  --cpu CPU        Target CPU (v1/v2/v3/v4/native aliases accepted)"
    << "  --native         Shorthand for --cpu native"
    << "  --target TRIPLE  Generate code for a different target triple"
    << "  --dev            Fast edit-test builds: clang -O0 (~2.8x faster link; binary ~2x slower)"
    << "  --fast, -fast    Fast FP: FMA + reassociation + reciprocals + nnan/ninf"
    << "  --strict-math    Strict IEEE 754: no FMA, no contraction"
    << "  --ll             Write LLVM IR (.ll) next to the binary"
    << "  --emit-ll        Write LLVM IR and skip native linking"
    << "  -j, --jobs N     Parallel compile-batch workers (default: auto)"
    << "  --ast-stats      Print slab AST node counts after compiling"
    << "  --ast            Print the AST and exit"
    << "  --canonical-ast  Print a stable machine-readable AST and exit"
    << "  --lex            Print tokens and exit"
    << "  -e CODE          Evaluate a string of code"
    << "  --interpret      Use the legacy tree-walker for run / -e"
    << "  -v, --verbose    Verbose output / print version"
    << "  --help           Show this help"
    exit 0
  elsif arg in ("--out" "-o")
    i += 1
    out_path = args[i]
  elsif arg == "--emit-wire"
    emit_wire = true
  elsif arg == "--tags"
    emit_wire = true
    tags_mode = true
  elsif arg == "--no-lto"
    no_lto = true
  elsif arg == "--lto"
    explicit_lto = true
  elsif arg == "--intern"
    i += 1
    intern_algo = args[i]
    if intern_algo != "raw" && intern_algo != "zstd"
      << "Unknown --intern algorithm: " + intern_algo
      exit 1
  elsif arg == "--frame-pointers"
    frame_pointers = true
  elsif arg == "--release"
    release_mode = true
  elsif arg == "--debug"
    debug_requested = true
  elsif arg == "--no-debug"
    no_debug_requested = true
  elsif arg == "--cpu"
    i += 1
    cpu_name = args[i]
    cpu_explicit = true
  elsif arg.starts_with?("--cpu=")
    cpu_name = arg.slice(6, arg.size() - 6)
    cpu_explicit = true
  elsif arg == "--native"
    native_mode = true
    cpu_name = "native"
    cpu_explicit = true
  elsif arg == "--portable"
    ccall("w_eputs", "--portable builds the release matrix; use `tungsten build --portable` or select one binary with --cpu")
    exit 1
  elsif arg == "--dev"
    dev_mode = true
  elsif arg == "--fast" || arg == "-fast"
    fast_mode = true
    math_mode = :fast
  elsif arg == "--strict-math"
    math_mode = :strict
  elsif arg == "--runtime"
    i += 1
    runtime_archive = args[i]
  elsif arg == "--target"
    # Cross-compile to <triple> (e.g. x86_64-linux-gnu, aarch64-linux-gnu).
    # Retargets codegen (via TUNGSTEN_TARGET → detect_llvm_target) and the
    # clang link. A runnable binary also needs --sysroot pointing at the
    # target's libc/crt (LLVM does the codegen; the linker needs the libs).
    i += 1
    cross_target = args[i]
    if env("TUNGSTEN_TARGET") == nil
      ccall("w_setenv", "TUNGSTEN_TARGET", cross_target)
  elsif arg.starts_with?("--target=")
    cross_target = arg.slice(9, arg.size() - 9)
    if env("TUNGSTEN_TARGET") == nil
      ccall("w_setenv", "TUNGSTEN_TARGET", cross_target)
  elsif arg == "--sysroot"
    i += 1
    cross_sysroot = args[i]
  elsif arg.starts_with?("--sysroot=")
    cross_sysroot = arg.slice(10, arg.size() - 10)
  elsif arg == "--ll"
    keep_ll = true
  elsif arg == "--emit-ll"
    emit_ll_only = true
  elsif arg == "--jobs" || arg == "-j"
    i += 1
    batch_jobs = args[i].to_i()
    if batch_jobs < 1
      << "--jobs requires a positive integer"
      exit 1
  elsif arg.starts_with?("--jobs=")
    batch_jobs = arg.slice(7, arg.size() - 7).to_i()
    if batch_jobs < 1
      << "--jobs requires a positive integer"
      exit 1
  # Internal compile-batch worker contract. The parent assigns each entry a
  # deterministic explicit .ll path under this private directory.
  elsif arg == "--batch-worker-dir"
    i += 1
    batch_worker_dir = args[i]
  elsif arg == "--ast-stats"
    ast_stats = true
  elsif arg == "--verbose"
    verbose = true
  elsif arg == "-v"
    verbose = true
    << "tungsten version 2026.07.04"
  elsif arg == "--ast"
    show_ast = true
  elsif arg == "--canonical-ast"
    show_canonical_ast = true
  elsif arg == "--lex"
    show_lex = true
  elsif arg == "--wit"
    wit_mode = true
  elsif arg == "--repl"
    wit_mode = true
  elsif arg == "--jit"
    wit_mode = true
    jit_mode = true
  elsif arg == "--hot"
    wit_mode = true
    hot_mode = true
  elsif arg == "--interpret"
    interpret_mode = true
  elsif arg == "-e"
    i += 1
    eval_code = args[i]
  elsif arg == "run"
    command = "run"
  elsif arg == "check" || arg == "-c" || arg == "--check"
    command = "check"
  elsif arg == "compile"
    command = "compile"
  elsif arg == "compile-batch"
    command = "compile-batch"
  elsif arg.starts_with?("-D")
    # `-D NAME=VALUE` or `-DNAME=VALUE` — set a build-time constant
    # visible to .w source. The defines are passed through to lower_ast,
    # which stores them in mod[:build_defines]. lower_var consults that
    # map BEFORE normal var resolution; if a name is found its value is
    # emitted as an i64 literal so the optimizer can constant-fold any
    # branch that depends on it.
    define_str = nil
    if arg == "-D"
      i += 1
      define_str = args[i]
    else
      define_str = arg.slice(2, arg.size() - 2)
    if define_str != nil && define_str != ""
      eq = define_str.index("=")
      if eq != nil && eq > 0
        define_key = define_str.slice(0, eq)
        define_val = define_str.slice(eq + 1, define_str.size() - eq - 1)
        build_defines[define_key] = define_val
      else
        # `-D NAME` (no value) defaults to true — matches C's `-DNAME` form.
        build_defines[define_str] = "true"
  elsif arg.starts_with?("-")
    << "Unknown flag: " + arg
    exit 1
  elsif file_path == nil
    file_path = arg
  else
    script_args.push(arg)
  i += 1

# Process-parallel compile-batch children own independent source shards. Mark
# them before emission so per-function threading does not nest underneath the
# parent-selected process pool.
if batch_worker_dir != nil
  ccall("w_setenv", "TUNGSTEN_BATCH_WORKER_PROCESS", "1")

# Resolve profile and target after parsing every flag so order cannot affect
# them. Release defaults to no-debug; an explicit --debug keeps safety checks,
# source-location metadata, and debug symbols while retaining -O3/full-LTO.
if debug_requested && no_debug_requested
  ccall("w_eputs", "--debug and --no-debug are mutually exclusive")
  exit 1
if dev_mode && release_mode
  ccall("w_eputs", "--dev and --release are mutually exclusive")
  exit 1
debug_enabled = debug_requested || (!no_debug_requested && !release_mode)
# Symbolized Tungsten metadata is only useful when the native unwinder can
# reliably walk the machine stack. A debug-enabled build therefore implies
# physical frame pointers as well as keeping fn/call-site metadata. Release
# builds remain free to omit them unless the user asks for --frame-pointers.
if debug_enabled
  frame_pointers = true
if native_mode && cpu_name != "native"
  ccall("w_eputs", "--native conflicts with --cpu " + cpu_name)
  exit 1
if cross_target != "" && !cpu_name_safe?(cross_target)
  ccall("w_eputs", "invalid --target value: " + cross_target)
  exit 1
if cross_sysroot != "" && cross_target == ""
  ccall("w_eputs", "--sysroot requires --target")
  exit 1

# Configure the process/daily target cache before resolving `--native`: the
# native CPU probe itself may invoke clang to test a newly named Apple CPU.
configure_target_probe_cache()
configured_march = env("TUNGSTEN_MARCH_ARGS")
if cpu_explicit
  cpu_name = normalize_cpu_name(cpu_name)
  if !cpu_name_safe?(cpu_name)
    ccall("w_eputs", "invalid --cpu value: " + cpu_name)
    exit 1
  cpu_target_mode = cpu_name
  resolved_cpu_flags = cpu_flags(cpu_name)
  if configured_march != resolved_cpu_flags
    ccall("w_setenv", "TUNGSTEN_MARCH_ARGS", resolved_cpu_flags)
  configured_march = resolved_cpu_flags
elsif cross_target != ""
  # A cross target with no explicit CPU uses clang's baseline for that target;
  # never leak the local apple-m5/native configuration into it.
  cpu_target_mode = "target-default"
  configured_march = ""
  ccall("w_setenv", "TUNGSTEN_MARCH_ARGS", "")
elsif configured_march != nil && configured_march != ""
  cpu_target_mode = "custom"
else
  cpu_name = env("TUNGSTEN_CPU")
  if cpu_name == nil || cpu_name == ""
    cpu_name = "native"
  cpu_name = normalize_cpu_name(cpu_name)
  if !cpu_name_safe?(cpu_name)
    ccall("w_eputs", "invalid configured CPU: " + cpu_name)
    exit 1
  cpu_target_mode = cpu_name
  resolved_cpu_flags = cpu_flags(cpu_name)
  if configured_march != resolved_cpu_flags
    ccall("w_setenv", "TUNGSTEN_MARCH_ARGS", resolved_cpu_flags)
  configured_march = resolved_cpu_flags

# cpu_flags("native") may probe detect_target before the resolved march is in
# the environment. Recompute once so feature guards (for example CSSC) match
# the same target that clang will use for emitted Core and runtime code.
detect_target_memo.delete(:target)

# Apple cross-architecture builds share the installed macOS SDK. Clang does not
# infer that sysroot when an explicit --target is supplied, so make portable
# arm64→x86_64 builds work without forcing users to paste xcrun output.
if cross_target != "" && cross_sysroot == "" && (cross_target.index("apple") != nil || cross_target.index("darwin") != nil)
  detected_sysroot = capture("xcrun --sdk macosx --show-sdk-path 2>/dev/null").strip()
  if detected_sysroot != ""
    cross_sysroot = detected_sysroot

-> phase_elapsed(started_at)
  clock - started_at

-> log_phase(verbose, name, started_at)
  if verbose
    << fmt_elapsed(phase_elapsed(started_at)) + " " + name

-> ll_needs_zstd_text(text)
  if text == nil
    return false
  if text.index("@w_slab_init_static_zstd(") != nil
    return true
  text.index("@w_zstd_compress_llvm_escaped(") != nil

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

-> ll_needs_lexchars(text)
  if ll_text_has(text, "lchs") || ll_text_has(text, "lexchars")
    return true
  # Short method names are emitted as inline-string WValue constants, so an
  # ordinary `.lchs()` call may leave no readable "lchs" text in the module.
  # Recognize the exact SSO-5 method-name literal used by its inline cache.
  ll_text_has(text, wvalue_literal_text(sso5_wvalue("lchs")))

-> ll_needs_apple_bridges(text)
  if ll_text_has(text, "@w_metal_")
    return true
  if ll_text_has(text, "@w_gfx_")
    return true
  if ll_text_has(text, "@w_hid_")
    return true
  # Fused elementwise GPU auto-offload (metal.m); the runtime.c weak stub
  # keeps non-bridged links working, but the real impl needs metal.m.
  if ll_text_has(text, "@w_fused_gpu_run")
    return true
  ll_text_has(text, "@w_gpu_")

# Accelerate BLAS is a separate conditional: a matmul program should not
# pull the GUI/GPU frameworks, and a plain program should not pull
# Accelerate. Real impls in runtime/blas_bridge.c override the weak stubs.
-> ll_needs_blas(text)
  if ll_text_has(text, "@w_blas_")
    return true
  if ll_text_has(text, "@w_array_cos_")
    return true
  if ll_text_has(text, "@w_array_sin_")
    return true
  if ll_text_has(text, "@w_array_sqrt_")
    return true
  if ll_text_has(text, "@w_array_exp_")
    return true
  if ll_text_has(text, "@w_array_log_")
    return true
  ll_text_has(text, "@w_array_tan_")

-> ll_needs_sparse(text)
  ll_text_has(text, "@w_sparse_")

-> ll_needs_sci_io(text)
  ll_text_has(text, "@w_sci_")

-> ll_needs_wtensor(text)
  ll_text_has(text, "@w_tensor_")

-> ll_needs_cuda(text)
  ll_text_has(text, "@w_cuda_")

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
  ll_text_has(text, "@w_jit_load_object(")

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
      emit_gpu_kernels_metal(kernels, i)
    rescue err
      if type(err) == "Hash" && err[:rt] == :compile_error
        failure = err
      else
        raise err

    if failure == nil && selection[:cuda]
      dialect = "cuda"
      begin
        emit_gpu_kernels_cuda(kernels, i)
      rescue err
        if type(err) == "Hash" && err[:rt] == :compile_error
          failure = err
        else
          raise err

    if failure == nil && selection[:wgsl]
      dialect = "wgsl"
      begin
        emit_gpu_kernels_wgsl(kernels, i)
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
  kernels = collect_gpu_kernels(ast)
  if kernels.size() == 0
    return {kernels: kernels, metal: nil, cuda: nil, wgsl: nil}

  selection = gpu_dialect_selection(env("TUNGSTEN_GPU_DIALECTS"), file_path, kernels[0])
  begin
    metal_text = emit_gpu_kernels_metal(kernels)
    cuda_text = nil
    wgsl_text = nil
    if selection[:cuda]
      cuda_text = emit_gpu_kernels_cuda(kernels)
    if selection[:wgsl]
      wgsl_text = emit_gpu_kernels_wgsl(kernels)
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
  dynamic_exports_needed = ll_needs_dynamic_exports(ll_probe_text)
  bridges_needed = ll_needs_apple_bridges(ll_probe_text)
  blas_needed = ll_needs_blas(ll_probe_text)
  sparse_needed = ll_needs_sparse(ll_probe_text)
  sci_io_needed = ll_needs_sci_io(ll_probe_text)
  wtensor_needed = ll_needs_wtensor(ll_probe_text)
  cuda_needed = ll_needs_cuda(ll_probe_text)
  # Data-table gating (weak twins in runtime.c make absence safe):
  #   prime    → ssmr_witness.c (512KB witness table; absent = exact 4-base
  #              fallback over its range)
  #   lexchars → lexchar_tables.c (348KB SIMD-lexer tables; absent = clear
  #              raise if ever reached)
  prime_needed = ll_text_has(ll_probe_text, "prime")
  # The String API is `.lchs`; direct lexchars runtime calls are covered too.
  lexchars_needed = ll_needs_lexchars(ll_probe_text)
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
  compiles_c = runtime_objs == nil || prime_needed || lexchars_needed || sci_io_needed || wtensor_needed || extra_c_includes.size() > 0
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
  if detect_target()[:os] == "macos"
    if blas_needed
      clang_cmd << gated_dir
      clang_cmd << "blas_bridge.c "
    if sparse_needed
      clang_cmd << gated_dir
      clang_cmd << "sparse_bridge.c "
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

-> kind_is_inline(k)
  # Kinds whose schema entry maps a field to OFFSET_INLINE (256) — i.e.
  # the data lives in the W_PACKED_NODE's 32-bit offset bits, no arena
  # slot. Listed alphabetically; cross-check against ast_schema.w's
  # slab_offset_table_data when adding new inline kinds.
  if k == :char
    return true
  if k == :codepoint
    return true
  if k == :color
    return true
  if k == :lambda_arity
    return true
  if k == :parg
    return true
  if k == :regex_capture
    return true
  if k == :superscript
    return true
  false

-> bit_width_of(n)
  if n <= 0
    return 0
  bits = 0
  v = n
  while v > 0
    v = v >> 1
    bits = bits + 1
  bits

# --ast-stats: dump slab AST node counts after a compile. Wrapped in a
# function so the ccall_nobox is not at module top level (the C VM
# stage 0 that runs this during bootstrap is touchy about top-level
# ccall_nobox). The 0 is a placeholder — ccall_nobox has no zero-arg form.
# Recursively tally AST node kinds into `counts` (kind symbol -> count).
-> count_kinds(node, counts)
  k = ast_kind(node)
  if k == nil
    return nil
  if counts[k] == nil
    counts[k] = 0
  counts[k] = counts[k] + 1
  if k == :var
    g_ast_stats_varnames[node.name] = true
  kids = ast_children(node)
  if kids.size() == 2
    k1 = ast_kind(kids[0])
    k2 = ast_kind(kids[1])
    if g_ast_stats_same_kind[k] == nil
      g_ast_stats_same_kind[k] = {total: 0, same: 0}
    g_ast_stats_same_kind[k][:total] = g_ast_stats_same_kind[k][:total] + 1
    if k1 == k2
      g_ast_stats_same_kind[k][:same] = g_ast_stats_same_kind[k][:same] + 1
  parent_offset = ccall("w_node_offset_extern", node)
  parent_sclass = ccall_nobox("w_node_size_class_extern", node)
  i = 0
  while i < kids.size()
    kid = kids[i]
    kid_kind = ast_kind(kid)
    if kind_is_inline(kid_kind)
      g_ast_stats_meta[:child_inline] = g_ast_stats_meta[:child_inline] + 1
    else
      kid_sclass = ccall_nobox("w_node_size_class_extern", kid)
      kid_offset = ccall("w_node_offset_extern", kid)
      delta = parent_offset - kid_offset
      if kid_sclass != parent_sclass
        g_ast_stats_meta[:cross_arena] = g_ast_stats_meta[:cross_arena] + 1
        abs_delta = delta
        if abs_delta < 0
          abs_delta = 0 - abs_delta
        cbucket = bit_width_of(abs_delta)
        if g_ast_stats_delta_cross[cbucket] == nil
          g_ast_stats_delta_cross[cbucket] = 0
        g_ast_stats_delta_cross[cbucket] = g_ast_stats_delta_cross[cbucket] + 1
      else
        if delta < 0
          g_ast_stats_meta[:negative_delta] = g_ast_stats_meta[:negative_delta] + 1
        else
          g_ast_stats_meta[:same_arena_real] = g_ast_stats_meta[:same_arena_real] + 1
          bucket = bit_width_of(delta)
          if g_ast_stats_delta[bucket] == nil
            g_ast_stats_delta[bucket] = 0
          g_ast_stats_delta[bucket] = g_ast_stats_delta[bucket] + 1
    count_kinds(kid, counts)
    i += 1
  nil

-> dump_ast_stats
  ccall_nobox("w_ast_stats_dump", 0)
  << "--- AST stats: nodes by kind (loaded parse tree) ---"
  ks = g_ast_stats_counts.keys()
  i = 0
  while i < ks.size()
    << "KINDCOUNT " + ks[i].to_s() + " " + g_ast_stats_counts[ks[i]].to_s()
    i += 1
  << "DISTINCT var_names " + g_ast_stats_varnames.keys().size().to_s()
  << "--- AST stats: parent->child edges ---"
  << "META same_arena_real " + g_ast_stats_meta[:same_arena_real].to_s()
  << "META cross_arena " + g_ast_stats_meta[:cross_arena].to_s()
  << "META child_inline " + g_ast_stats_meta[:child_inline].to_s()
  << "META negative_delta " + g_ast_stats_meta[:negative_delta].to_s()
  bks = g_ast_stats_delta.keys()
  i = 0
  while i < bks.size()
    << "DELTA_BITS " + bks[i].to_s() + " " + g_ast_stats_delta[bks[i]].to_s()
    i += 1
  << "--- AST stats: cross-layout-class |delta| histogram ---"
  cbks = g_ast_stats_delta_cross.keys()
  i = 0
  while i < cbks.size()
    << "DELTA_CROSS_BITS " + cbks[i].to_s() + " " + g_ast_stats_delta_cross[cbks[i]].to_s()
    i += 1
  << "--- AST stats: 2-child same-kind by parent kind ---"
  sks = g_ast_stats_same_kind.keys()
  i = 0
  while i < sks.size()
    pk = sks[i]
    rec = g_ast_stats_same_kind[pk]
    << "SAMEKIND " + pk.to_s() + " " + rec[:same].to_s() + "/" + rec[:total].to_s()
    i += 1

# ── Incremental compile cache ─────────────────────────────────────────────
# `tungsten compile` / `-o` re-lowered and re-linked byte-identical inputs
# every run (identical self-compile retires an identical 53.6B instructions).
# Cache the final binary + sidemap keyed by (compiler binary identity,
# codegen-relevant flags, entry path) and validated by the loader's
# (path, mtime_ns) manifest of every file the build read — the same
# freshness rule the ruby AST cache uses. Compiled-runtime only (the C VM
# lacks the w_executable_path ccall, and bootstrap stages must not share
# entries across compiler binaries — exe path+mtime is part of the
# identity). TUNGSTEN_INCREMENTAL=0 disables (the PGO post-step sets it:
# a cache hit would skip the very work being profiled).

-> incremental_cache_enabled?
  if env("TUNGSTEN_INCREMENTAL") == "0"
    return false
  runtime_identity() == "compiled-runtime"

-> incremental_env_s(name)
  v = env(name)
  if v == nil
    return ""
  v

# Split the emitted module and compile the parts with parallel clang -c.
# Returns the space-joined .o paths, or nil for "use the single-TU path"
# (missing toolchain, or any split/compile failure). Uses Homebrew LLVM's
# llvm-split + clang: llvm-split without -preserve-locals promotes module-
# local symbols so partitions distribute (with it, every function glued to
# the shared globals lands in one partition and nothing parallelizes), and
# its bitcode output needs a matching-version clang to read.
-> parallel_codegen_objects(ll_path, verbose)
  llvm_prefix = driver_homebrew_prefix("llvm")
  if llvm_prefix == ""
    return nil
  llvm_bin = llvm_prefix + "/bin"
  if !file?(llvm_bin + "/llvm-split") || !file?(llvm_bin + "/clang")
    return nil
  parts = 14
  prefix = ll_path + ".part"
  q_ll = dev_runtime_shell_quote(ll_path)
  q_prefix = dev_runtime_shell_quote(prefix)
  if system(dev_runtime_shell_quote(llvm_bin + "/llvm-split") + " -j " + parts.to_s() + " -o " + q_prefix + " " + q_ll) != true
    return nil
  # Stale part objects from a previous run would satisfy the existence
  # check below even when a clang job fails (sh's bare `wait` exits 0
  # regardless of job status) — clear them so every .o linked was
  # produced by THIS spawn. Each job also touches a .ok marker AFTER its
  # clang succeeds; requiring the marker rejects truncated objects from
  # jobs killed mid-write, which still leave a .o on disk.
  system("rm -f " + q_prefix + "*.o " + q_prefix + "*.ok")
  flags = profile_opt_flag() + " " + debug_compile_flag() + " " + march_flags() + " -fmerge-all-constants "
  on macos
    flags = flags + "-fveclib=Darwin_libsystem_m "
  cmd = StringBuffer(1024)
  objs = StringBuffer(512)
  i = 0
  while i < parts
    part = prefix + i.to_s()
    if !file?(part)
      return nil
    cmd << dev_runtime_shell_quote(llvm_bin + "/clang")
    cmd << " "
    cmd << flags
    cmd << "-c -x ir "
    cmd << dev_runtime_shell_quote(part)
    cmd << " -o "
    cmd << dev_runtime_shell_quote(part + ".o")
    cmd << " && touch "
    cmd << dev_runtime_shell_quote(part + ".ok")
    cmd << " & "
    objs << dev_runtime_shell_quote(part + ".o")
    objs << " "
    i += 1
  cmd << "wait"
  if system(cmd.to_s()) != true
    return nil
  i = 0
  while i < parts
    if !file?(prefix + i.to_s() + ".o") || !file?(prefix + i.to_s() + ".ok")
      return nil
    i += 1
  # Success: the split bitcode inputs and job markers served their purpose;
  # only the .o files feed the link. Leaving parts behind leaked ~15 files
  # per build when ll_path is a stable (--ll / source-adjacent) location.
  i = 0
  while i < parts
    system("rm -f " + dev_runtime_shell_quote(prefix + i.to_s()) + " " + dev_runtime_shell_quote(prefix + i.to_s() + ".ok"))
    i += 1
  objs.to_s()

# Runtime source (path, mtime_ns) rows for the incremental manifest. The
# cached binary embeds the runtime archive, whose PATH is stable across
# runtime-source edits (dev_runtime_archive_path hashes config, not
# content) and whose rebuild happens AFTER the cache probe — so a touched
# runtime source must invalidate cached binaries here, over exactly the
# file set the archive's own freshness check watches.
-> incremental_runtime_entries
  runtime_dir = resolve_runtime_dir
  ev = runtime_event_source
  runtime_root = dev_runtime_source_identity(runtime_dir, runtime_identity())
  gt = file?(runtime_root + "/generated/bigint_thresholds.h") ? "present" : "absent"
  bases = dev_runtime_base_files(ev, gt, tls_runtime_source())
  entries = []
  bi = 0
  while bi < bases.size()
    p = runtime_root + "/" + bases[bi]
    mt = file_mtime_ns(p)
    if mt != nil
      entries.push([p, mt])
    bi += 1
  entries

-> incremental_abs_path(p)
  if p.starts_with?("/")
    return p
  pwd = capture("pwd -P 2>/dev/null").strip()
  if pwd == ""
    return p
  pwd + "/" + p

-> incremental_cache_slot(file_path, out_path, identity)
  dir = compiler_cache_dir()
  if dir == nil
    return nil
  if system("mkdir -p " + dev_runtime_shell_quote(dir)) != true
    return nil
  # Hash ABSOLUTE paths AND the full identity into the slot name: verbatim
  # paths overflowed NAME_MAX on deep trees (every store failed "File name
  # too long"), relative invocations from two projects must not share a
  # slot, and folding the identity in keeps differently-configured builds
  # (--dev vs default, -D defines, env knobs) in separate slots — two
  # concurrent writers can then never pair one config's manifest with the
  # other's binary. The identity line in the manifest stays as a self-check.
  key = incremental_abs_path(file_path) + "__" + incremental_abs_path(out_path) + "|" + identity
  dir + "/irbin-" + wyhash64_hex_string(key)

# Freshness is mtime-based for source manifests, while the identity covers the
# compiler/linker executables, target flags, optional features, and ambient SDK
# paths. `tungsten --clear-cache` remains the escape hatch for a tool that lies
# about both its contents and filesystem identity.
-> incremental_identity(file_path, out_path)
  exe = ccall("w_executable_path")
  em = file_mtime_ns(exe)
  if em == nil
    return nil
  runtime_kind = runtime_identity()
  cc_identity = dev_runtime_cc_identity(host_c_compiler(), runtime_kind)
  ar_identity = dev_runtime_ar_identity(archive_tool(), runtime_kind)
  if cc_identity == nil || ar_identity == nil
    return nil
  defs = ""
  # Sorted deliberately (NOT an iteration-order workaround): -D flags may
  # arrive in any order across invocations, and the cache identity string
  # must not change when they do.
  dk = build_defines.keys().sort()
  dki = 0
  while dki < dk.size()
    defs = defs + dk[dki] + "=" + build_defines[dk[dki]] + ";"
    dki += 1
  ra = runtime_archive == nil ? "" : runtime_archive
  ram = ""
  if ra != ""
    ramv = file_mtime_ns(ra)
    ram = ramv == nil ? "missing" : ramv.to_s()
  ["irbin-v5", incremental_abs_path(file_path), incremental_abs_path(out_path), exe, em.to_s(), cc_identity, ar_identity, release_mode.to_s(), debug_enabled.to_s(), cpu_target_mode, march_flags(), dev_mode.to_s(), fast_mode.to_s(), math_mode.to_s(), frame_pointers.to_s(), intern_algo, no_lto.to_s(), explicit_lto.to_s(), cross_target, cross_sysroot, ra, ram, incremental_env_s("SDKROOT"), incremental_env_s("MACOSX_DEPLOYMENT_TARGET"), incremental_env_s("CPATH"), incremental_env_s("C_INCLUDE_PATH"), incremental_env_s("CPLUS_INCLUDE_PATH"), incremental_env_s("LIBRARY_PATH"), incremental_env_s("PKG_CONFIG_PATH"), incremental_env_s("PKG_CONFIG_LIBDIR"), incremental_env_s("TLS"), incremental_env_s("TUNGSTEN_TLS"), incremental_env_s("TUNGSTEN_TLS_CFLAGS"), incremental_env_s("TUNGSTEN_TLS_LDFLAGS"), incremental_env_s("TUNGSTEN_GPU_DIALECTS"), incremental_env_s("TUNGSTEN_CLANG_OPT"), incremental_env_s("TUNGSTEN_MARCH_ARGS"), incremental_env_s("TUNGSTEN_CARRY_UNROLL"), incremental_env_s("TUNGSTEN_FREE"), incremental_env_s("TUNGSTEN_PARAM_INFER"), incremental_env_s("TUNGSTEN_DEMOTE_TOP_LEVEL"), incremental_env_s("TUNGSTEN_MIMALLOC"), incremental_env_s("TUNGSTEN_LLVM_FASTCC"), incremental_env_s("TUNGSTEN_PARALLEL_CODEGEN"), incremental_env_s("TUNGSTEN_CORE_REACHABILITY"), incremental_env_s("TUNGSTEN_LAZY_CONTENT_HASH"), incremental_env_s("TUNGSTEN_DYNAMIC_EXPORTS"), incremental_env_s("TUNGSTEN_C_INCLUDES"), incremental_env_s("TUNGSTEN_DEFINES"), incremental_env_s("TUNGSTEN_SERVICE_BINDINGS"), incremental_env_s("BIT_HOME"), incremental_env_s("TUNGSTEN_ROOT"), incremental_env_s("TUNGSTEN_CC"), incremental_env_s("TUNGSTEN_AR"), incremental_env_s("TUNGSTEN_SYMBOL_PREFIX_HEX"), defs].join("|")

# Content-addressed final-link cache. The early irbin cache deliberately keys
# source and output paths so it can skip every compiler phase. This cache keys
# the actual emitted LLVM instead, after lowering/emission have established
# that two builds are semantically the same link input.
-> link_artifact_cache_dependency_identity
  rows = []
  runtime = incremental_runtime_entries()
  i = 0
  while i < runtime.size()
    rows.push(runtime[i][0] + ":" + runtime[i][1].to_s())
    i += 1

  # Companions are linked only when referenced, but including every existing
  # source is a cheap conservative invalidation rule and avoids duplicating the
  # feature-gating logic here. Missing optional files are represented too.
  runtime_dir = resolve_runtime_dir()
  companions = ["ssmr_witness.c", "lexchar_tables.c", "blas_bridge.c",
                "sparse_bridge.c", "metal.m", "graphics.m", "hid_bridge.m",
                "sci_io_native.c", "tensor_bridge.c", "openblas_bridge.c",
                zstd_runtime_source()]
  i = 0
  while i < companions.size()
    path = runtime_dir + companions[i]
    mt = file_mtime_ns(path)
    rows.push(path + ":" + (mt == nil ? "missing" : mt.to_s()))
    i += 1
  rows.join("|")

-> link_artifact_cache_runtime_identity(runtime_objs)
  if runtime_objs == nil
    return "runtime-source"
  if runtime_objs.index("/*.o") != nil
    # compile-batch creates this private path afresh. Its selected sources,
    # compiler, flags, and mtimes are already represented by the identity.
    return "batch-runtime-objects"
  mt = file_mtime_ns(runtime_objs)
  incremental_abs_path(runtime_objs) + ":" + (mt == nil ? "missing" : mt.to_s())

-> link_artifact_cache_slot(ll_text, runtime_objs, needs_zstd)
  if !incremental_cache_enabled?() || env("TUNGSTEN_LINK_CACHE") == "0"
    return nil
  # A path-valued C include can itself include arbitrary headers. Reusing only
  # from its own mtime would be unsound, so leave FFI builds on the ordinary
  # linker path until a depfile-backed C graph exists.
  if extra_c_includes().size() > 0
    return nil
  base = incremental_identity("", "")
  cache_dir = compiler_cache_dir()
  if base == nil || cache_dir == nil
    return nil
  if system("mkdir -p " + dev_runtime_shell_quote(cache_dir)) != true
    return nil

  flags = [onig_cflags(), onig_ldflags(), tls_cflags(), tls_ldflags(),
           http2_ldflags(), mimalloc_link_flags()]
  if needs_zstd
    flags.push(zstd_cflags())
    flags.push(zstd_ldflags())
  identity = ["link-artifact-v1", ll_text.size().to_s(),
              wyhash64_hex_string(ll_text), base,
              link_artifact_cache_runtime_identity(runtime_objs),
              link_artifact_cache_dependency_identity(), flags.join("|")].join("|")
  cache_dir + "/linkbin-" + wyhash64_hex_string(identity) + ".bin"

-> link_artifact_cache_try_reuse(slot, out_path)
  if !file?(slot)
    return false
  q_out = dev_runtime_shell_quote(out_path)
  q_tmp = dev_runtime_shell_quote(out_path + ".link-install.") + "$$"
  if system("cp -p " + dev_runtime_shell_quote(slot) + " " + q_tmp + " && mv -f " + q_tmp + " " + q_out) != true
    return false
  # Active content survives the shared seven-day cache GC window.
  system("touch " + dev_runtime_shell_quote(slot))
  true

-> link_artifact_cache_store(slot, out_path)
  nonce = clock.to_s()
  tmp = slot + ".tmp." + nonce
  if system("cp -p " + dev_runtime_shell_quote(out_path) + " " + dev_runtime_shell_quote(tmp)) != true
    return nil
  if system("mv -f " + dev_runtime_shell_quote(tmp) + " " + dev_runtime_shell_quote(slot)) != true
    system("rm -f " + dev_runtime_shell_quote(tmp))
  nil

# Valid cached slot for this identity? Reads the manifest and revalidates
# every recorded (path, mtime_ns). Any surprise → miss (rebuild).
-> incremental_manifest_valid?(slot, identity)
  manifest = read_file(slot + ".manifest")
  if manifest == nil
    return false
  lines = manifest.split("\n")
  # >= 2: identity line plus at least one file row. A store always records
  # the runtime base sources, so a rowless manifest is truncation damage.
  if lines.size() < 2 || lines[0] != identity
    return false
  i = 1
  while i < lines.size()
    line = lines[i]
    if line != ""
      tab = line.index("\t")
      if tab == nil
        return false
      mt = line.slice(0, tab)
      pathpart = line.slice(tab + 1, line.size() - tab - 1)
      cur = file_mtime_ns(pathpart)
      if cur == nil || cur.to_s() != mt
        return false
    i += 1
  if !file?(slot + ".bin")
    return false
  true

# Manifest check plus install: on success the cached binary + sidemap land
# at out_path.
-> incremental_try_reuse(slot, identity, out_path, verbose)
  if !incremental_manifest_valid?(slot, identity)
    return false
  # Install via a unique temp + rename: an out_path that is currently
  # EXECUTING keeps its inode (an in-place cp truncates it — on macOS the
  # running process dies SIGKILL from code-sign invalidation). $$ stays
  # outside the quoting so the shell expands its own pid.
  q_out = dev_runtime_shell_quote(out_path)
  q_tmp = dev_runtime_shell_quote(out_path + ".install.") + "$$"
  if system("cp -p " + dev_runtime_shell_quote(slot + ".bin") + " " + q_tmp + " && mv -f " + q_tmp + " " + q_out) != true
    return false
  if file?(slot + ".sidemap")
    system("cp -p " + dev_runtime_shell_quote(slot + ".sidemap") + " " + dev_runtime_shell_quote(out_path + ".sidemap"))
  else
    # No cached sidemap: drop any stale one a previous non-cached build
    # left beside out_path, or crash reports symbolize against old code.
    system("rm -f " + dev_runtime_shell_quote(out_path + ".sidemap"))
  true

-> incremental_store(slot, identity, out_path, sidemap_path, file_path)
  files = g_incremental[:manifest]
  if files == nil
    return nil
  parts = [identity]
  i = 0
  while i < files.size()
    parts.push(files[i][1].to_s() + "\t" + incremental_abs_path(files[i][0]))
    i += 1
  rt = incremental_runtime_entries
  ri = 0
  while ri < rt.size()
    parts.push(rt[ri][1].to_s() + "\t" + rt[ri][0])
    ri += 1
  # @gpu sidecars are emitted next to the SOURCE; recording them as rows
  # means a deleted sidecar mtimes to nil at probe time and forces the
  # rebuild that regenerates it.
  gpu_exts = [".metal", ".cu"]
  gi = 0
  while gi < gpu_exts.size()
    gp = file_path.replace(".w", gpu_exts[gi])
    gm = file_mtime_ns(gp)
    if gm != nil
      parts.push(gm.to_s() + "\t" + incremental_abs_path(gp))
    gi += 1
  # Unique staging names (concurrent writers of the same slot must never
  # interleave into one temp file) and manifest-last, atomic-rename
  # publication: a reader sees either the old pair or the new pair.
  nonce = clock.to_s()
  q_slot_bin = dev_runtime_shell_quote(slot + ".bin")
  tmp = slot + ".bin.tmp." + nonce
  if system("cp -p " + dev_runtime_shell_quote(out_path) + " " + dev_runtime_shell_quote(tmp)) != true
    return nil
  if system("mv -f " + dev_runtime_shell_quote(tmp) + " " + q_slot_bin) != true
    system("rm -f " + dev_runtime_shell_quote(tmp))
    return nil
  if file?(sidemap_path)
    system("cp -p " + dev_runtime_shell_quote(sidemap_path) + " " + dev_runtime_shell_quote(slot + ".sidemap"))
  else
    system("rm -f " + dev_runtime_shell_quote(slot + ".sidemap"))
  mtmp = slot + ".manifest.tmp." + nonce
  write_file(mtmp, parts.join("\n") + "\n")
  if system("mv -f " + dev_runtime_shell_quote(mtmp) + " " + dev_runtime_shell_quote(slot + ".manifest")) != true
    system("rm -f " + dev_runtime_shell_quote(mtmp))
  nil

-> compile_one(file_path, out_path, emit_wire, verbose, intern_algo, emit_ll_only_arg = false, quiet = false)
  if out_path == nil
    out_path = file_path.replace(".w", ".wc")

  # Cache probe: full binary path only (no --emit-wire/--emit-ll/--ll and
  # no TUNGSTEN_LL_PATH/TUNGSTEN_LL_DONE_MARKER — those flows consume
  # intermediate artifacts a cache hit would never produce).
  incr_slot = nil
  incr_id = nil
  if !emit_wire && !emit_ll_only_arg && !keep_ll && incremental_env_s("TUNGSTEN_LL_PATH") == "" && incremental_env_s("TUNGSTEN_LL_DONE_MARKER") == "" && incremental_cache_enabled?
    incr_id = incremental_identity(file_path, out_path)
    if incr_id != nil
      incr_slot = incremental_cache_slot(file_path, out_path, incr_id)
    if incr_slot != nil && incr_id != nil
      if incremental_try_reuse(incr_slot, incr_id, out_path, verbose)
        if !quiet
          << ""
          << "Built [out_path] (cache)"
        return true

  implicit_ll = uses_implicit_ll_path() ## bool
  sidemap_path = out_path + ".sidemap"
  ll_path = emit_ir(file_path, emit_wire, verbose, intern_algo, sidemap_path, emit_ll_only_arg, build_defines)

  if ll_path == nil
    return true

  if emit_ll_only_arg
    if implicit_ll && !publish_implicit_ll_path(ll_path, file_path)
      return false
    return true

  ok = link_binary(ll_path, out_path, runtime_archive, verbose)
  if implicit_ll && !publish_implicit_ll_path(ll_path, file_path)
    ok = false

  if ok
    if !quiet
      << ""
      << "Built [out_path]"
    if incr_slot != nil && incr_id != nil
      incremental_store(incr_slot, incr_id, out_path, sidemap_path, file_path)

  ok

# `run` and `-e` use the ordinary lowering/WIRE/LLVM path. Stable per-source
# output names let the existing incremental binary cache make repeated runs
# cheap; only the tiny exit-status sidecar is invocation-specific.
-> compiled_run_dir
  dir = compiler_cache_dir() + "/run"
  if system("mkdir -p " + dev_runtime_shell_quote(dir)) != true
    raise "could not create compiled-run cache directory: [dir]"
  dir

-> compiled_run_output_path(source_path)
  identity = incremental_abs_path(source_path)
  compiled_run_dir() + "/" + wyhash64_hex_string(identity) + ".wc"

# The eval file is content-addressed, so every writer writes identical bytes;
# the temp + rename only guarantees a concurrent reader never sees a
# truncated file mid-write.
-> materialize_eval_source(code)
  dir = compiled_run_dir()
  path = dir + "/eval-" + wyhash64_hex_string(code) + ".w"
  if !file?(path) || read_file(path) != code
    tmp = path + ".tmp." + clock.to_s()
    write_file(tmp, code)
    system("mv -f " + dev_runtime_shell_quote(tmp) + " " + dev_runtime_shell_quote(path))
  path

# Serialize concurrent builds of one cache binary. mkdir is the portable
# atomic lock primitive (same as cache_gc.sh). A lock left behind by a
# crashed process is stolen after ~60s of waiting; after ~90s total we give
# up and proceed unlocked — a duplicate compile beats a deadlock.
-> acquire_run_lock(lock_path)
  attempts = 0
  while system("mkdir " + dev_runtime_shell_quote(lock_path) + " 2>/dev/null") != true
    attempts += 1
    if attempts == 600
      system("rmdir " + dev_runtime_shell_quote(lock_path) + " 2>/dev/null")
    if attempts > 900
      return false
    system("sleep 0.1")
  true

-> release_run_lock(lock_path)
  system("rmdir " + dev_runtime_shell_quote(lock_path) + " 2>/dev/null")
  nil

# The shared cache GC (bin/commands/cache_gc.sh) self-throttles to one sweep
# per day, so this background kick is almost always a no-op. It keeps
# run-cache binaries and eval sources bounded for users who only ever `run`.
-> kick_run_cache_gc
  script = resolve_runtime_dir + "../bin/commands/cache_gc.sh"
  if file?(script)
    system("(bash " + dev_runtime_shell_quote(script) + " " + dev_runtime_shell_quote(compiler_cache_dir()) + " >/dev/null 2>&1 &)")
  nil

# Warm-run fast path: when the incremental manifest says the slot is
# current AND that exact identity is what was last published onto the run
# binary, skip every copy and rename and exec the existing inode. macOS
# validates a binary's code signature on the first exec of fresh file
# content (~200ms); re-executing an already-validated inode costs ~4ms, so
# a warm run must not rewrite the published file at all.
-> run_cache_current?(source_path, stage, binary)
  if keep_ll || incremental_env_s("TUNGSTEN_LL_PATH") != "" || incremental_env_s("TUNGSTEN_LL_DONE_MARKER") != "" || !incremental_cache_enabled?
    return false
  id = incremental_identity(source_path, stage)
  if id == nil
    return false
  slot = incremental_cache_slot(source_path, stage, id)
  if slot == nil
    return false
  if !incremental_manifest_valid?(slot, id)
    return false
  if !file?(binary)
    return false
  read_file(binary + ".id") == id

-> publish_run_binary(source_path, stage, binary)
  if system("mv -f " + dev_runtime_shell_quote(stage) + " " + dev_runtime_shell_quote(binary)) != true
    return false
  system("mv -f " + dev_runtime_shell_quote(stage + ".sidemap") + " " + dev_runtime_shell_quote(binary + ".sidemap") + " 2>/dev/null")
  # Same guard as the compile_one probe: identity needs ccalls the stage-0
  # VM does not provide, and without the cache the .id stamp is useless.
  if incremental_cache_enabled?
    id = incremental_identity(source_path, stage)
    if id != nil
      write_file(binary + ".id", id)
  true

# Returns the child's exact exit code, or 128+signal for a signal death.
# Builds land in a sibling .stage file under the lock and are renamed onto
# the final name, so an already-running instance keeps its old inode — a
# concurrent `run` of the same script can never truncate a binary that is
# executing. The child is spawned directly from argv: no shell, no quoting,
# no job-control chatter on stderr.
-> run_compiled_program(source_path, run_args)
  binary = compiled_run_output_path(source_path)
  stage = binary + ".stage"
  lock_path = binary + ".lock"
  locked = acquire_run_lock(lock_path)
  ok = false
  begin
    if run_cache_current?(source_path, stage, binary)
      ok = true
    else
      ok = compile_one(source_path, stage, false, verbose, intern_algo, false, true)
      if ok
        ok = publish_run_binary(source_path, stage, binary)
  rescue err
    if locked
      release_run_lock(lock_path)
    raise err
  if locked
    release_run_lock(lock_path)
  if !ok
    return 1
  kick_run_cache_gc()

  child_argv = [binary]
  i = 0
  while i < run_args.size()
    child_argv.push(run_args[i])
    i += 1
  status = ccall("w_run_argv", child_argv)
  if status >= 256
    return 128 + (status - 256)
  if status < 0
    ccall("w_eputs", "run: could not execute [binary]")
    return 1
  status

# Parse the complete program and run lowering/type inference, but deliberately
# stop before CFG construction, ownership, LLVM emission, runtime compilation,
# or linking. This is the same stage-2 frontend used by executable builds, so
# `tungsten -c` cannot accept a different language from `tungsten compile`.
-> check_one(file_path, verbose = false)
  loader = Loader.new(verbose)
  ast = loader.load_program_ast(file_path)
  compile_to_wire(ast, file_path, verbose, fast_mode, math_mode, loader.manifest_files())
  gpu_preflight(ast, file_path)
  << "200 OK"
  true

# Frontend-only modes (`--lex` / `--ast`) run before the command dispatcher,
# so they need the same structured-error boundary as check/run/compile.
-> report_frontend_error(err, source_path)
  if type(err) == "Hash" && err[:rt] == :compile_error
    ccall("w_flush")
    ccall("w_eputs", emit_compile_error(err))
    return true
  if type(err) == "String"
    ccall("w_flush")
    ccall("w_eputs", format_runtime_error(err, source_path))
    return true
  false

# Choose deterministic process-level parallelism for compile-batch. Each
# worker owns a disjoint contiguous source shard and therefore its own parser,
# AST/WIRE arenas, and emitter metadata counters. The parent alone compiles a
# runtime (when needed) and links, so parallel lowering does not multiply the
# runtime build or change final link order.
-> batch_parallel_job_count(file_count)
  if file_count < 2 || batch_worker_dir != nil || runtime_identity() != "compiled-runtime"
    return 1
  if emit_wire || tags_mode || ast_stats || keep_ll
    return 1
  if incremental_env_s("TUNGSTEN_LL_PATH") != "" || incremental_env_s("TUNGSTEN_LL_DONE_MARKER") != "" || incremental_env_s("TUNGSTEN_METAL_PATH") != "" || incremental_env_s("TUNGSTEN_SSA_REPORT") != ""
    return 1
  if env("TUNGSTEN_BATCH_PARALLEL") == "0"
    return 1

  requested = batch_jobs
  explicit = requested > 0
  if !explicit
    configured = env("TUNGSTEN_BATCH_JOBS")
    if configured != nil && configured != "" && configured != "auto"
      requested = configured.to_i()
      explicit = requested > 0

  if !explicit
    cpus = ccall("w_cpu_count")
    if cpus < 1
      cpus = 1
    # One worker per ~16 entries amortizes compiler startup and preserves the
    # in-worker parsed-AST/render caches. Eight was the measured knee on the
    # 150-program suite and bounds aggregate memory on larger hosts.
    requested = (file_count + 15) / 16
    if requested > cpus
      requested = cpus
    if requested > 8
      requested = 8
  if requested < 1
    requested = 1
  if requested > file_count
    requested = file_count
  if requested > 32
    requested = 32
  requested

-> batch_parallel_worker_options
  options = []
  if no_lto
    options.push("--no-lto")
  if explicit_lto
    options.push("--lto")
  if frame_pointers
    options.push("--frame-pointers")
  if release_mode
    options.push("--release")
  if debug_requested
    options.push("--debug")
  if no_debug_requested
    options.push("--no-debug")
  if native_mode
    options.push("--native")
  elsif cpu_explicit
    options.push("--cpu")
    options.push(cpu_name)
  if cross_target != ""
    options.push("--target")
    options.push(cross_target)
  if cross_sysroot != ""
    options.push("--sysroot")
    options.push(cross_sysroot)
  if dev_mode
    options.push("--dev")
  if fast_mode
    options.push("--fast")
  if math_mode == :strict
    options.push("--strict-math")
  if intern_algo != "raw"
    options.push("--intern")
    options.push(intern_algo)
  if verbose
    options.push("--verbose")
  define_keys = build_defines.keys().sort()
  i = 0
  while i < define_keys.size()
    options.push("-D" + define_keys[i] + "=" + build_defines[define_keys[i]])
    i += 1
  options

-> batch_parallel_files_unique?(files)
  seen = {}
  i = 0
  while i < files.size()
    prior = seen[files[i]]
    if prior != nil && prior == files[i]
      return false
    seen[files[i]] = files[i]
    i += 1
  true

-> batch_parallel_emit(files, jobs, worker_options)
  root = capture("mktemp -d " + dev_runtime_shell_quote(implicit_ll_root() + "/batch-emit.XXXXXX") + " 2>/dev/null").strip()
  if root == ""
    return {ok: false, root: nil, jobs: [], message: "could not create parallel batch scratch directory"}
  exe = ccall("w_executable_path")
  if exe == nil || exe == ""
    return {ok: false, root: root, jobs: [], message: "compiler executable path is unavailable"}

  workers = []
  base = files.size() / jobs
  extra = files.size() % jobs
  start = 0
  wi = 0
  spawn_error = nil
  while wi < jobs && spawn_error == nil
    count = base
    if wi < extra
      count += 1
    dir = root + "/worker-" + wi.to_s()
    out_log = root + "/worker-" + wi.to_s() + ".out"
    err_log = root + "/worker-" + wi.to_s() + ".err"
    if system("mkdir -p " + dev_runtime_shell_quote(dir)) != true
      spawn_error = "could not create worker directory " + dir
    else
      argv = [exe, "compile-batch", "--emit-ll", "--jobs", "1", "--batch-worker-dir", dir]
      oi = 0
      while oi < worker_options.size()
        argv.push(worker_options[oi])
        oi += 1
      fi = 0
      while fi < count
        argv.push(files[start + fi])
        fi += 1
      cmd = StringBuffer(256 + count * 64)
      ai = 0
      while ai < argv.size()
        if ai > 0
          cmd << " "
        cmd << dev_runtime_shell_quote(argv[ai])
        ai += 1
      cmd << " >"
      cmd << dev_runtime_shell_quote(out_log)
      cmd << " 2>"
      cmd << dev_runtime_shell_quote(err_log)
      begin
        process = Process.spawn(["/bin/sh", "-c", cmd.to_s()])
        workers.push({process: process, dir: dir, out_log: out_log, err_log: err_log, start: start, count: count})
      rescue err
        spawn_error = err.to_s()
    start += count
    wi += 1

  if spawn_error != nil
    i = 0
    while i < workers.size()
      workers[i][:process].kill()
      workers[i][:process].wait()
      i += 1
    return {ok: false, root: root, jobs: [], message: "parallel worker spawn failed: " + spawn_error}

  failed = false
  i = 0
  while i < workers.size()
    status = workers[i][:process].wait()
    workers[i][:status] = status
    if status != 0
      failed = true
    i += 1

  # Replay worker logs in source-shard order, not completion order.
  i = 0
  while i < workers.size()
    out_log = workers[i][:out_log]
    if file?(out_log)
      out_text = read_file(out_log)
      if out_text != nil && out_text != ""
        ccall("w_print", out_text)
      ccall("__w_unlink", out_log)
    err_log = workers[i][:err_log]
    if file?(err_log)
      err_text = read_file(err_log)
      if err_text != nil && err_text != ""
        ccall("w_eputs", err_text)
      ccall("__w_unlink", err_log)
    i += 1

  emitted = []
  i = 0
  while i < workers.size()
    worker = workers[i]
    li = 0
    while li < worker[:count]
      source = files[worker[:start] + li]
      ll = worker[:dir] + "/" + li.to_s() + ".ll"
      if !file?(ll) || !file?(ll + ".done")
        failed = true
      emitted.push({ll: ll, bin: source.replace(".w", ".wc"), source: source, implicit_ll: true})
      li += 1
    i += 1

  if failed
    return {ok: false, root: root, jobs: emitted, message: "one or more parallel batch workers failed"}
  {ok: true, root: root, jobs: emitted, message: nil}

# Handle --wit / --repl (interactive pure-Tungsten REPL)
if wit_mode
  REPL.new(Interpreter.new([]), jit_mode, hot_mode).start()
  exit 0

# Handle -e (eval) mode
if eval_code != nil
  if show_lex
    begin
      eval_code = ccall("w_algebra_rewrite_source", eval_code)
      lexer = Lexer.new(eval_code, "(eval)")
      token_count = lexer.tokenize()

      packed = lexer.packed_tokens
      values = lexer.values
      i = 0
      while i < token_count
        p = packed[i]
        type_id = (p >> 38) & 0xFF
        << type_id.to_s() + " " + values[i].to_s()
        i += 1
    rescue err
      if report_frontend_error(err, "(eval)")
        exit 1
      raise err

    exit 0

  if show_ast || show_canonical_ast
    begin
      eval_code = ccall("w_algebra_rewrite_source", eval_code)
      lexer = Lexer.new(eval_code, "(eval)")
      token_count = lexer.tokenize()
      parser = Parser.new(token_count, lexer.packed_tokens, eval_code, lexer.values, lexer.line_at, lexer.col_at, lexer.file).set_chars(lexer.chars)
      ast = parser.parse()
      if show_canonical_ast
        << ast_to_canonical(ast)
      else
        << ast_to_tree(ast, "")
    rescue err
      if report_frontend_error(err, "(eval)")
        exit 1
      raise err
    exit 0

  eval_status = 0
  begin
    if interpret_mode
      interp = Interpreter.new(script_args)
      interp.run(eval_code, "(eval)")
    else
      eval_path = materialize_eval_source(eval_code)
      eval_source_alias = eval_path
      eval_status = run_compiled_program(eval_path, script_args)
      system("rm -f " + dev_runtime_shell_quote(eval_path))
  rescue err
    if type(err) == "Hash" && err[:rt] == :compile_error
      ccall("w_flush")
      msg = emit_compile_error(err)
      if eval_source_alias != nil
        msg = msg.replace(eval_source_alias, "(eval)")
      ccall("w_eputs", msg)
      exit 1
    if type(err) == "String"
      ccall("w_flush")
      ccall("w_eputs", format_runtime_error(err, "(eval)"))
      exit 1
    raise err
  # exit AFTER the begin/rescue, not as the last stmt inside `begin`: an in-block
  # exit leaves the begin body with no fall-through edge to the rescue merge,
  # which miscompiles on the Linux self-host backend (silent stage-2 SIGSEGV).
  exit eval_status

if file_path == nil && command != "compile-batch"
  << "Missing input file"
  exit 1

# Handle --lex and AST inspection for files
if show_lex
  begin
    source = read_file(file_path)
    source = ccall("w_algebra_rewrite_source", source)
    lexer = Lexer.new(source, file_path)
    token_count = lexer.tokenize()

    packed = lexer.packed_tokens
    values = lexer.values
    i = 0
    while i < token_count
      p = packed[i]
      type_id = (p >> 38) & 0xFF
      << type_id.to_s() + " " + values[i].to_s()
      i += 1
  rescue err
    if report_frontend_error(err, file_path)
      exit 1
    raise err

  exit 0

if show_ast || show_canonical_ast
  begin
    source = read_file(file_path)
    source = ccall("w_algebra_rewrite_source", source)
    lexer = Lexer.new(source, file_path)
    token_count = lexer.tokenize()
    parser = Parser.new(token_count, lexer.packed_tokens, source, lexer.values, lexer.line_at, lexer.col_at, lexer.file).set_chars(lexer.chars)
    ast = parser.parse()
    if show_canonical_ast
      << ast_to_canonical(ast)
    else
      << ast_to_tree(ast, "")
  rescue err
    if report_frontend_error(err, file_path)
      exit 1
    raise err
  exit 0

if command == "run"
  run_status = 0
  begin
    if interpret_mode
      source = read_file(file_path)
      interp = Interpreter.new(script_args)
      interp.run(source, file_path)
    else
      run_status = run_compiled_program(file_path, script_args)
  rescue err
    if type(err) == "Hash" && err[:rt] == :compile_error
      ccall("w_flush")
      ccall("w_eputs", emit_compile_error(err))
      exit 1
    if type(err) == "String"
      ccall("w_flush")
      ccall("w_eputs", format_runtime_error(err, file_path))
      exit 1
    raise err
  if !interpret_mode
    exit run_status

elsif command == "check"
  begin
    check_one(file_path, verbose)
  rescue err
    if type(err) == "Hash" && err[:rt] == :compile_error
      ccall("w_flush")
      ccall("w_eputs", emit_compile_error(err))
      exit 1
    if type(err) == "String"
      ccall("w_flush")
      ccall("w_eputs", format_runtime_error(err, file_path))
      exit 1
    raise err

elsif command == "compile"
  begin
    if !compile_one(file_path, out_path, emit_wire, verbose, intern_algo, emit_ll_only)
      exit 1
    if ast_stats
      dump_ast_stats()
  rescue err
    if type(err) == "Hash" && err[:rt] == :compile_error
      ccall("w_flush")
      ccall("w_eputs", emit_compile_error(err))
      exit 1
    raise err

elsif command == "compile-batch"
  # Batch compile: loads stage compiler once, compiles runtime once,
  # then emits IR + links each file individually
  files = []
  if file_path != nil
    files.push(file_path)
  i = 0
  while i < script_args.size()
    files.push(script_args[i])
    i += 1

  if files.size() == 0
    << "compile-batch: no files given"
    exit 1

  loader_enable_parse_cache()
  ll_jobs = []
  needs_zstd_runtime = false
  fail_count = 0
  parallel_root = nil
  parallel_count = batch_parallel_job_count(files.size())
  if parallel_count > 1 && !batch_parallel_files_unique?(files)
    parallel_count = 1
  parallel_result = nil

  if parallel_count > 1
    if verbose
      << "  parallel batch: " + parallel_count.to_s() + " deterministic workers"
    parallel_result = batch_parallel_emit(files, parallel_count, batch_parallel_worker_options())
    if parallel_result[:ok] != true
      << "Parallel batch emission failed: " + parallel_result[:message]
      exit 1
    parallel_root = parallel_result[:root]
    if !emit_ll_only
      ll_jobs = parallel_result[:jobs]
      ji = 0
      while ji < ll_jobs.size()
        if ll_needs_zstd_path(ll_jobs[ji][:ll])
          needs_zstd_runtime = true
        ji += 1

  else
    batch_file_index = 0
    files -> (fp)
      bin = fp.replace(".w", ".wc")
      << "--- Compiling [fp] ---"
      begin
        if batch_worker_dir != nil
          ccall("w_setenv", "TUNGSTEN_LL_PATH", batch_worker_dir + "/" + batch_file_index.to_s() + ".ll")
        implicit_ll = uses_implicit_ll_path() ## bool
        ll_path = emit_ir(fp, emit_wire, verbose, intern_algo, bin + ".sidemap", emit_ll_only, build_defines, no_static_slab)
        if ll_path != nil
          if !emit_ll_only
            ll_jobs.push({ll: ll_path, bin: bin, source: fp, implicit_ll: implicit_ll})
            if ll_needs_zstd_path(ll_path)
              needs_zstd_runtime = true
        else
          fail_count += 1
      rescue err
        fail_count += 1
        if type(err) == "Hash" && err[:rt] == :compile_error
          ccall("w_flush")
          ccall("w_eputs", emit_compile_error(err))
        else
          << "Unhandled exception compiling [fp]: [err]"
      batch_file_index += 1

  runtime_objs = nil

  # Runtime objects: link_binary's nil-runtime_objs default already serves a
  # cached native archive for ordinary and frame-pointer debug configurations,
  # so only pre-build a batch-local runtime when that default cannot (LTO
  # release links compile the runtime from source per link — amortize it once;
  # zstd needs the flag-compiled variant). The archive lands in a
  # private scratch dir, NEVER the first input's directory (the old
  # `files[0]`-derived path wrote `spec/numeric/runtime.a` into the
  # source tree and broke outside it).
  batch_lto = (release_mode || explicit_lto) && !no_lto
  if ll_jobs.size() > 0 && (batch_lto || needs_zstd_runtime)
    tmp_dir = capture("mktemp -d " + dev_runtime_shell_quote(implicit_ll_root() + "/batch-rt.XXXXXX") + " 2>/dev/null").strip()
    if tmp_dir == ""
      << "Failed to create batch runtime scratch directory"
      exit 1
    runtime_objs = compile_runtime_objs(tmp_dir, needs_zstd_runtime, verbose)

    if runtime_objs == nil
      << "Failed to compile runtime"
      ll_jobs -> (job)
        if job[:implicit_ll]
          z = publish_implicit_ll_path(job[:ll], job[:source])
      exit 1

  ll_jobs -> (job)
    ok = link_binary(job[:ll], job[:bin], runtime_objs, verbose)
    if job[:implicit_ll] && !publish_implicit_ll_path(job[:ll], job[:source])
      ok = false
    if !ok
      fail_count += 1

  if parallel_root != nil
    system("rmdir " + dev_runtime_shell_quote(parallel_root) + " 2>/dev/null")

  if fail_count > 0
    << "[fail_count] file(s) failed to compile"
    exit 1
