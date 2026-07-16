use core/integer
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

args = argv()
if args.size() == 0
  << "Usage: tungsten (run|compile) <file.w>"
  << ""
  << "Commands:"
  << "  run              Interpret a .w file"
  << "  compile          Compile a .w file to a native binary"
  << "  compile-batch    Compile multiple .w files"
  << ""
  << "Options:"
  << "  --out FILE       Output path for compiled binary"
  << "  --emit-wire      Emit WIRE IR text instead of LLVM IR"
  << "  --intern ALGO    Static slab encoding (raw or zstd)"
  << "  --no-lto         Disable link-time optimization"
  << "  --frame-pointers Keep frame pointers (for profiling/debugging)"
  << "  --release        Skip debug safety checks and stacktrace metadata"
  << "  --fast, -fast    Fast FP: FMA + reassociation + reciprocals + nnan/ninf"
  << "  --strict-math    Strict IEEE 754: no FMA, no contraction"
  << "  --ll             Write LLVM IR (.ll) next to the binary"
  << "  --emit-ll        Write LLVM IR and skip native linking"
  << "  --ast            Print the AST and exit"
  << "  --lex            Print tokens and exit"
  << "  -e CODE          Evaluate a string of code"
  << "  -v, --verbose    Verbose output / print version"
  << "  --help           Show this help"
  exit 0

command        = "compile"
out_path       = nil
file_path      = nil
eval_code      = nil
emit_wire      = false
verbose        = false
show_ast       = false
show_lex       = false
wit_mode       = false
jit_mode       = false
hot_mode       = false
no_lto         = false
explicit_lto   = false
frame_pointers = false
keep_ll        = false
emit_ll_only   = false
cross_target   = ""
cross_sysroot  = ""
ast_stats      = false
g_ast_stats_counts = {}
g_ast_stats_varnames = {}
g_ast_stats_delta = {}
g_ast_stats_delta_cross = {}
g_ast_stats_meta = {same_arena_real: 0, cross_arena: 0, child_inline: 0, negative_delta: 0}
g_ast_stats_same_kind = {}
release_mode   = false
fast_mode      = false
math_mode      = :precise
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
    << "Usage: tungsten (run|compile) <file.w>"
    << ""
    << "Commands:"
    << "  run              Interpret a .w file"
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
    << "  --release        Skip debug safety checks and stacktrace metadata"
    << "  --fast, -fast    Fast FP: FMA + reassociation + reciprocals + nnan/ninf"
    << "  --strict-math    Strict IEEE 754: no FMA, no contraction"
    << "  --ll             Write LLVM IR (.ll) next to the binary"
    << "  --emit-ll        Write LLVM IR and skip native linking"
    << "  --ast-stats      Print slab AST node counts after compiling"
    << "  --ast            Print the AST and exit"
    << "  --lex            Print tokens and exit"
    << "  -e CODE          Evaluate a string of code"
    << "  -v, --verbose    Verbose output / print version"
    << "  --help           Show this help"
    exit 0
  elsif arg in ("--out" "-o")
    i += 1
    out_path = args[i]
  elsif arg == "--emit-wire"
    emit_wire = true
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
    # Portable ISA baseline for a distributed binary. Set once so link, runtime
    # compile, and the target-features probe (target.w) all agree. The guard lets
    # the bootstrap pre-set it via env (the stage-0 C VM can't ccall setenv),
    # while a standalone compiled `tungsten compile --release` sets it itself.
    if env("TUNGSTEN_MARCH_ARGS") == nil
      ccall("w_setenv", "TUNGSTEN_MARCH_ARGS", portable_march_flags())
  elsif arg == "--native"
    release_mode = true
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
  elsif arg == "--sysroot"
    i += 1
    cross_sysroot = args[i]
  elsif arg == "--ll"
    keep_ll = true
  elsif arg == "--emit-ll"
    emit_ll_only = true
  elsif arg == "--ast-stats"
    ast_stats = true
  elsif arg == "--verbose"
    verbose = true
  elsif arg == "-v"
    verbose = true
    << "tungsten version 2026.07.04"
  elsif arg == "--ast"
    show_ast = true
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
  elsif arg == "-e"
    i += 1
    eval_code = args[i]
  elsif arg == "run"
    command = "run"
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

# Does the emitted module reference any Apple GPU/graphics/HID bridge symbol?
# Only then are metal.m/graphics.m/hid_bridge.m (and, via their ObjC
# autolinking, the Metal/AppKit/QuartzCore/IOKit frameworks) linked; other
# programs use weak stubs in the runtime translation units and start ~2ms warm with a far
# cheaper first-run dyld closure.
-> ll_text_has(text, needle)
  if text == nil
    return false
  text.index(needle) != nil

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
  ll_text_has(text, "@w_blas_")

-> ll_needs_sparse(text)
  ll_text_has(text, "@w_sparse_")

-> ll_needs_sci_io(text)
  ll_text_has(text, "@w_sci_")

-> ll_needs_wtensor(text)
  ll_text_has(text, "@w_tensor_")

-> ll_needs_cuda(text)
  ll_text_has(text, "@w_cuda_")

# System library flag probes. Each shells out via capture() — fork+exec+pipe
# is ~10-30ms per call, and we do 9 of them per compile. To skip them on
# rebuilds, the driver (bin/commands/build.rb) caches the resolved flags in
# build/cache/system-deps.marshal and passes them down via TUNGSTEN_*
# env vars. When the env var is set (even to ""), we treat that as the
# resolved value and skip capture(). An unset env var means "no driver
# pre-resolved them, fall back to runtime probing" — preserves behavior
# when the compiler is invoked outside bin/tungsten build.

-> zstd_cflags
  cached = env("TUNGSTEN_ZSTD_CFLAGS")
  if cached != nil
    return cached
  flags = capture("pkg-config --cflags libzstd 2>/dev/null").strip()
  if flags != ""
    return flags
  if capture("test -f /opt/homebrew/include/zstd.h && echo yes").strip() == "yes"
    return "-I/opt/homebrew/include"
  ""

-> zstd_ldflags
  cached = env("TUNGSTEN_ZSTD_LDFLAGS")
  if cached != nil
    return cached
  flags = capture("pkg-config --libs libzstd 2>/dev/null").strip()
  if flags != ""
    return flags
  if capture("test -f /opt/homebrew/lib/libzstd.dylib -o -f /opt/homebrew/lib/libzstd.a && echo yes").strip() == "yes"
    return "-L/opt/homebrew/lib -lzstd"
  "-lzstd"

-> onig_cflags
  cached = env("TUNGSTEN_ONIG_CFLAGS")
  if cached != nil
    return cached
  flags = capture("pkg-config --cflags oniguruma 2>/dev/null").strip()
  if flags != ""
    return flags + " -DTUNGSTEN_ONIG"
  if capture("test -f /opt/homebrew/include/oniguruma.h && echo yes").strip() == "yes"
    return "-I/opt/homebrew/include -DTUNGSTEN_ONIG"
  ""

-> onig_ldflags
  cached = env("TUNGSTEN_ONIG_LDFLAGS")
  if cached != nil
    return cached
  flags = capture("pkg-config --libs oniguruma 2>/dev/null").strip()
  if flags != ""
    return flags
  if onig_cflags != ""
    if capture("test -f /opt/homebrew/lib/libonig.dylib -o -f /opt/homebrew/lib/libonig.a && echo yes").strip() == "yes"
      return "-L/opt/homebrew/lib -lonig"
    return "-lonig"
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

-> emit_ir(file_path, emit_wire, verbose, intern_algo, sidemap_path = nil, emit_ll_only_arg = false, build_defines = nil, no_static_slab = false)
  # Emit LLVM IR (or WIRE text) for a single file, return ll_path or nil
  loader = Loader.new(verbose)
  load_started_at = clock
  ast = loader.load_program_ast(file_path)
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
    mod = compile_to_wire(ast, file_path, verbose, fast_mode, math_mode)

    if verbose
      << fmt_elapsed(phase_elapsed(wire_started_at)) + " lower to wire"

    emit_started_at = clock

    << emit_wire_text(mod)

    if verbose
      << fmt_elapsed(phase_elapsed(emit_started_at)) + " emit wire"
    return nil

  if verbose
    << ""
    << fmt_elapsed(t_load) + " load+parse"

  ir = compile(ast, file_path, verbose, frame_pointers, sidemap_path, release_mode, fast_mode, build_defines, math_mode, no_static_slab)
  if intern_algo == "zstd"
    ir = rewrite_ir_static_slab_zstd(ir)

  explicit_ll_path = env("TUNGSTEN_LL_PATH")
  if explicit_ll_path != nil && explicit_ll_path != ""
    ll_path = explicit_ll_path
  elsif keep_ll
    ll_path = file_path.replace(".w", ".ll")
  else
    ll_dir = env("TUNGSTEN_LL_DIR")
    if ll_dir == nil || ll_dir == ""
      ll_dir = "/tmp/tungsten"
    system("mkdir -p " + ll_dir)
    ll_path = ll_dir + "/" + file_path.split("/").last().replace(".w", ".ll")

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
  # Runtime dispatch wiring (compile→library→pipeline→dispatch) lands
  # in Phase 1; for the Phase 0 provenance smoke, the .metal file is
  # the artifact we verify: source → MSL → (later) dispatch.
  kernels = collect_gpu_kernels(ast)
  if kernels.size() > 0
    metal_text = emit_gpu_kernels_metal(kernels)
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
    # TUNGSTEN_GPU_DIALECTS is a comma list, e.g. "cuda,wgsl" or "none".
    # Default: emit CUDA always (cross-platform kernel source). WGSL stays
    # opt-in. Set TUNGSTEN_GPU_DIALECTS=none to suppress extras; Metal is
    # always written when kernels are present.
    dialects = env("TUNGSTEN_GPU_DIALECTS")
    emit_cuda = true
    emit_wgsl = false
    if dialects != nil
      if dialects == "none" || dialects == ""
        emit_cuda = false
        emit_wgsl = false
      else
        emit_cuda = dialects.include?("cuda")
        emit_wgsl = dialects.include?("wgsl")
    if emit_cuda
      cuda_text = emit_gpu_kernels_cuda(kernels)
      if cuda_text != nil
        cuda_path = file_path.replace(".w", ".cu")
        write_file(cuda_path, cuda_text)
        if verbose
          << "Wrote " + cuda_path + " (" + kernels.size().to_s() + " @gpu fn → CUDA)"
    if emit_wgsl
      wgsl_text = emit_gpu_kernels_wgsl(kernels)
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

# The portable ISA baseline for a distributed binary, so a release artifact never
# hits an illegal instruction on a CPU older than the build machine: x86-64-v2 on
# x86, armv8-a on arm, both with generic tuning.
-> portable_march_flags
  if detect_target()[:arch] == "x86_64"
    return "-march=x86-64-v2 -mtune=generic"
  "-march=armv8-a -mtune=generic"

# march/tune flags for the C compiler. Driven by TUNGSTEN_MARCH_ARGS, which the
# --release arg sets to portable_march_flags() so link, runtime compile, and the
# target-features probe (target.w) all agree. Default: host-tuned native. march
# is a post-.ll clang flag, so this never affects the stage1==stage2 identity.
-> march_flags
  m = env("TUNGSTEN_MARCH_ARGS")
  if m != nil && m != ""
    return m
  "-march=native -mtune=native"

-> link_binary(ll_path, out_path, runtime_objs, verbose = false)
  ll_probe_text = read_file(ll_path)
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
  # the String API is `.lchs` (IC name "lchs"); "lexchars" additionally covers
  # direct @w_string_to_lexchars ccall users
  lexchars_needed = ll_text_has(ll_probe_text, "lchs") || ll_text_has(ll_probe_text, "lexchars")
  link_started_at = clock
  needs_zstd = ll_needs_zstd_text(ll_probe_text)
  # LTO is opt-in: whole-program LTO (lean binary, slow link) only for
  # --release / --native / --lto; the default is a native-object runtime
  # archive (fatter binary, ~0.1s link vs ~5s recompiling the C runtime).
  doing_lto = (release_mode || explicit_lto) && !no_lto
  # Fast dev link (default): reuse the cached native-object runtime archive
  # rather than recompiling the ~28k-line runtime every build. runtime.o's weak
  # companion stubs keep the gated ssmr/lexchar/metal/blas adds below valid.
  # Configs the shared archive can't represent (cross-target, frame pointers,
  # zstd) fall through to the from-source path.
  if runtime_objs == nil && !doing_lto && cross_target == "" && !frame_pointers && !needs_zstd
    runtime_objs = dev_runtime_archive(verbose)
  clang_opt = env("TUNGSTEN_CLANG_OPT")
  if clang_opt == nil || clang_opt == ""
    clang_opt = "-O3"

  clang_cmd = StringBuffer(0)
  clang_cmd << host_c_compiler()
  clang_cmd << " "
  clang_cmd << clang_opt
  clang_cmd << " -DNDEBUG "
  # Host -march=native (e.g. -mcpu=apple-m4) is wrong for a cross target and the
  # target clang rejects it — the --target triple already selects the arch, so
  # let clang use the target's default baseline. Native builds keep host tuning.
  if cross_target == ""
    clang_cmd << march_flags()
  clang_cmd << " -fmerge-all-constants "

  if !frame_pointers && doing_lto
    clang_cmd << "-flto "

  if frame_pointers
    clang_cmd << "-fno-omit-frame-pointer "

  # ld64 (macOS) vs GNU/lld (Linux): -dead_strip and -stack_size are ld64-only;
  # GNU ld also can't read LTO-bitcode archives, so Linux links through lld.
  # -export_dynamic/-rdynamic: keep the runtime symbols in the dynamic symbol
  # table so a dlopen'd JIT snippet can resolve w_int/w_add/… from this binary
  # (the --jit/--hot REPL links tiny snippet dylibs that resolve against the
  # host instead of relinking the 1.4MB runtime — ~15x faster per line).
  if cross_target != ""
    # Cross-link: drive clang at the target triple + sysroot with lld. Assumes
    # a non-macOS (ELF) target — the -dead_strip/-stack_size ld64 flags below
    # are macOS-only. The sysroot supplies the target's libc/crt/system libs.
    clang_cmd << "--target=" + cross_target + " "
    if cross_sysroot != ""
      clang_cmd << "--sysroot=" + cross_sysroot + " "
    clang_cmd << "-fuse-ld=lld -Wl,--gc-sections -rdynamic "
  elsif detect_target()[:os] == "macos"
    # -fveclib: the LLVM loop vectorizer may replace scalar libm calls in
    # vectorizable loops (e.g. the compiler's fused elementwise loops) with
    # libsystem_m's NEON SIMD variants (_simd_sin_d2 & co). Post-.ll clang
    # flag — never affects stage1==stage2 identity. Linux is left alone:
    # libmvec coverage varies by glibc version/arch and a missing _ZGV*
    # symbol would break the link.
    clang_cmd << "-fveclib=Darwin_libsystem_m "
    clang_cmd << "-Wl,-dead_strip -Wl,-stack_size,0x8000000 -Wl,-export_dynamic "
  else
    clang_cmd << "-fuse-ld=lld -Wl,--gc-sections -rdynamic "

  ocf = onig_cflags
  if ocf != ""
    clang_cmd << ocf
    clang_cmd << " "

  if needs_zstd && runtime_objs == nil
    zcf = zstd_cflags

    if zcf != ""
      clang_cmd << zcf
      clang_cmd << " "

  # -I the runtime dir on BOTH paths: the native archive omits the .c sources,
  # but the gated companions (ssmr/metal/…) and any bit C includes below still
  # #include runtime.h and need the header search path.
  runtime_dir = resolve_runtime_dir
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
    clang_cmd << "tls_stub.c "

    if needs_zstd
      clang_cmd << runtime_dir
      clang_cmd << "slab_zstd.c "

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
  on macos
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
  on linux
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

  # Framework links. Accelerate is unconditional (runtime.c calls
  # cblas_sgemm/dgemm directly); everything else only when the bridges are
  # linked — "harmless" turned out to cost ~1.5ms warm and most of the
  # first-run dyld closure on every plain CLI binary.
  on macos
    if bridges_needed
      clang_cmd << " -framework Metal -framework Foundation -framework AppKit -framework QuartzCore -framework CoreGraphics -framework IOKit -framework CoreFoundation"
    if blas_needed || sparse_needed
      clang_cmd << " -framework Accelerate"

  # Linux: libm is a separate library (macOS bundles it into libSystem), and
  # it must follow the objects that reference it.
  on linux
    clang_cmd << " -lm"
    if blas_needed
      clang_cmd << " -lopenblas"

  clang_cmd << " -o "
  clang_cmd << out_path
  result = system(clang_cmd.to_s())
  log_phase(verbose, "clang", link_started_at)
  result == true

# Persistent NATIVE-object runtime archive for fast dev links. Linking against
# this skips recompiling the ~28k-line C runtime on every build (~5s -> ~0.1s).
# runtime.o keeps weak stubs for the gated companions, so link_binary still adds
# the strong ssmr/lexchar/metal/blas sources when a program needs them. The
# archive is rebuilt whenever any base runtime source is newer than it. The
# whole-program-LTO builds (--release / --native / --lto) skip this and rebuild
# the runtime from source for a lean, cross-optimized binary.
-> dev_runtime_shell_quote(text)
  "'" + text.gsub("'", "'\\''") + "'"

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

-> dev_runtime_archive_path(runtime_root, cc_identity, ar_identity, compile_flags, event_source, generated_thresholds)
  config = StringBuffer(0)
  config << "dev-runtime-archive-v4\n"
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
  "/tmp/tungsten-runtime-native-" + wyhash64_hex_string(config.to_s()) + ".a"

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
  compile_flags = "-O3 -DNDEBUG " + march_flags()
  thresholds_path = runtime_root + "/generated/bigint_thresholds.h"
  generated_thresholds = "absent"
  if file?(thresholds_path)
    generated_thresholds = "present"
  archive = dev_runtime_archive_path(runtime_root, cc_identity, ar_identity, compile_flags, ev, generated_thresholds)
  evo = ev.replace(".c", ".o")

  # Freshness: reuse the cached archive iff it is newer than every base source.
  bases = ["runtime.c", "terminal_input.c", "runtime.h", "wvalue.h",
           "event_loop.h", "ssmr_witness.h", "w_char_table.c", "aks.c", "tls_stub.c"]
  if ev == "event_*.c"
    bases.push("event_kqueue.c")
    bases.push("event_epoll.c")
    bases.push("event_iouring.c")
  else
    bases.push(ev)
  if generated_thresholds == "present"
    bases.push("generated/bigint_thresholds.h")

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
  cc << dev_runtime_shell_quote(runtime_root + "/tls_stub.c")
  cc << " && "
  cc << ar_command
  cc << " rcs \"$archive_tmp\""
  cc << " runtime.o terminal_input.o "
  cc << event_object_arg
  cc << " aks.o tls_stub.o && mv -f \"$archive_tmp\" "
  cc << dev_runtime_shell_quote(archive)
  cc << "; status=$?; rm -rf \"$build_dir\" \"$archive_tmp\"; exit $status"
  if system(cc.to_s()) != true
    return nil
  archive

-> compile_runtime_objs(tmp_dir, needs_zstd = false, verbose = false)
  # Compile all runtime .c files into a single combined .o
  runtime_dir = resolve_runtime_dir
  archive = tmp_dir + "/runtime.a"

  cc = StringBuffer(0)
  cc << "cd "
  cc << runtime_dir
  cc << " && "
  cc << host_c_compiler()
  cc << " -O3 -DNDEBUG "
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

  if (release_mode || explicit_lto) && !no_lto && !frame_pointers
    cc << "-flto "

  if frame_pointers
    cc << "-fno-omit-frame-pointer "

  cc << "-c runtime.c terminal_input.c "
  cc << runtime_event_source
  cc << " ssmr_witness.c tls_stub.c aks.c "

  if needs_zstd
    cc << "slab_zstd.c "

  # On macOS, also compile the Obj-C Metal bridge so @gpu fn dispatch
  # symbols (w_metal_*) resolve at link time, plus the graphics.m
  # windowing bridge (w_gfx_*). Linux/Windows skip this — those
  # platforms get the no-Metal stubs in runtime.c.
  on macos
    cc << "&& "
    cc << host_c_compiler()
    cc << " -O3 -DNDEBUG "
    cc << march_flags()
    cc << " -x objective-c -c metal.m graphics.m hid_bridge.m "

  cc << "&& "
  cc << archive_tool()
  cc << " rcs "
  cc << archive
  cc << " *.o"
  if ranlib_tool() != ""
    cc << " && "
    cc << ranlib_tool()
    cc << " "
    cc << archive
  cc << " && rm -f *.o"

  << "Compiling runtime..."

  compile_started_at = clock
  result = system(cc.to_s())
  log_phase(verbose, "runtime compile", compile_started_at)

  if result != true
    return nil

  archive

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
  parent_offset = ccall_nobox("w_node_offset_extern", node)
  parent_sclass = ccall_nobox("w_node_size_class_extern", node)
  i = 0
  while i < kids.size()
    kid = kids[i]
    kid_kind = ast_kind(kid)
    if kind_is_inline(kid_kind)
      g_ast_stats_meta[:child_inline] = g_ast_stats_meta[:child_inline] + 1
    else
      kid_sclass = ccall_nobox("w_node_size_class_extern", kid)
      kid_offset = ccall_nobox("w_node_offset_extern", kid)
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
  << "--- AST stats: cross-arena |delta| histogram ---"
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

-> compile_one(file_path, out_path, emit_wire, verbose, intern_algo, emit_ll_only_arg = false)
  if out_path == nil
    out_path = file_path.replace(".w", ".wc")

  sidemap_path = out_path + ".sidemap"
  ll_path = emit_ir(file_path, emit_wire, verbose, intern_algo, sidemap_path, emit_ll_only_arg, build_defines)

  if ll_path == nil
    return true

  if emit_ll_only_arg
    return true

  ok = link_binary(ll_path, out_path, runtime_archive, verbose)

  if ok
    << ""
    << "Built [out_path]"

  ok

# Handle --wit / --repl (interactive pure-Tungsten REPL)
if wit_mode
  REPL.new(Interpreter.new([]), jit_mode, hot_mode).start()
  exit 0

# Handle -e (eval) mode
if eval_code != nil
  if show_lex
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

    exit 0

  if show_ast
    lexer = Lexer.new(eval_code, "(eval)")
    token_count = lexer.tokenize()
    parser = Parser.new(token_count, lexer.packed_tokens, source, lexer.values, lexer.line_at, lexer.col_at, lexer.file).set_chars(lexer.chars)
    ast = parser.parse()
    << ast_to_tree(ast, "")
    exit 0

  begin
    interp = Interpreter.new(script_args)
    interp.run(eval_code, "(eval)")
  rescue err
    if type(err) == "Hash" && err[:rt] == :compile_error
      ccall("w_eputs", format_compile_error(err))
      exit 1
    if type(err) == "String"
      ccall("w_eputs", format_runtime_error(err, "(eval)"))
      exit 1
    raise err
  # exit AFTER the begin/rescue, not as the last stmt inside `begin`: an in-block
  # exit leaves the begin body with no fall-through edge to the rescue merge,
  # which miscompiles on the Linux self-host backend (silent stage-2 SIGSEGV).
  exit 0

if file_path == nil && command != "compile-batch"
  << "Missing input file"
  exit 1

# Handle --lex and --ast for files
if show_lex
  source = read_file(file_path)
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

  exit 0

if show_ast
  source = read_file(file_path)
  lexer = Lexer.new(source, file_path)
  token_count = lexer.tokenize()
  parser = Parser.new(token_count, lexer.packed_tokens, source, lexer.values, lexer.line_at, lexer.col_at, lexer.file).set_chars(lexer.chars)
  ast = parser.parse()
  << ast_to_tree(ast, "")
  exit 0

if command == "run"
  begin
    source = read_file(file_path)
    interp = Interpreter.new(script_args)
    interp.run(source, file_path)
  rescue err
    if type(err) == "Hash" && err[:rt] == :compile_error
      ccall("w_eputs", format_compile_error(err))
      exit 1
    if type(err) == "String"
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
      ccall("w_eputs", format_compile_error(err))
      exit 1
    raise err

elsif command == "compile-batch"
  # Batch compile: loads stage compiler once, compiles runtime once,
  # then emits IR + links each file individually
  files = []
  skip_next = false

  args -> (a)
    if skip_next
      skip_next = false
    elsif a in ("--out" "-o" "--intern" "-e")
      skip_next = true
    elsif a != "compile-batch" && a != "--emit-wire" && a != "--no-lto" && a != "--frame-pointers" && a != "--release" && a != "--fast" && a != "-fast" && a != "--verbose" && a != "-v" && a != "--ll"
      files.push(a)

  if files.size() == 0
    << "compile-batch: no files given"
    exit 1

  ll_jobs = []
  needs_zstd_runtime = false
  fail_count = 0

  files -> (fp)
    bin = fp.replace(".w", ".wc")
    << "--- Compiling [fp] ---"
    begin
      ll_path = emit_ir(fp, emit_wire, verbose, intern_algo, bin + ".sidemap")
      if ll_path != nil
        ll_jobs.push({ll: ll_path, bin: bin})
        if ll_needs_zstd_path(ll_path)
          needs_zstd_runtime = true
      else
        fail_count += 1
    rescue err
      fail_count += 1
      if type(err) == "Hash" && err[:rt] == :compile_error
        ccall("w_eputs", format_compile_error(err))
      else
        << "Unhandled exception compiling [fp]: [err]"

  runtime_objs = nil

  if ll_jobs.size() > 0
    tmp_dir = files[0].split("/").copy(0, files[0].split("/").size() - 1).join("/")
    runtime_objs = compile_runtime_objs(tmp_dir, needs_zstd_runtime, verbose)

    if runtime_objs == nil
      << "Failed to compile runtime"
      exit 1

  ll_jobs -> (job)
    ok = link_binary(job[:ll], job[:bin], runtime_objs, verbose)
    if !ok
      fail_count += 1

  if fail_count > 0
    << "[fail_count] file(s) failed to compile"
    exit 1
