use core/integer
use core/numeric/int
use core/numeric/float
use core/numeric/big_int
# String/Symbol#size and #length are source methods on the shared 0xF9 facade.
# Keep the self-host registration explicit for stage-0 loaders predating the
# broad dynamic-receiver autoload gate.
use core/string
# The self-host uses StringBuffer pervasively. Keep this explicit so a stage-0
# compiler whose loader predates the constructor-autoload trigger can build the
# first source-size stage after the native IC is removed.
use core/string_buffer
use lib/lexer
use lib/parser
use lib/compiler
use lib/loader
use lib/error_formatter
use lib/return_inference
use lib/compiler_gpu_emitter
use lib/hashing
use lib/optimization_report
use lib/driver/ir
use lib/driver/link
use lib/driver/pipeline

gpu_emitter = CompilerGPUEmitter.new()
if env("TUNGSTEN_COMPILER_IMAGE") in ("metal" "repl")
  gpu_emitter = MetalCompilerGPUEmitter.new()

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
  << "  --optimizations  Explain lowering costs in the entry source"
  << "  --optimizations-json  Emit the explanation as JSON"
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
optimizations_mode = false
optimizations_json = false
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
batch_link_worker = false
batch_out_dir = nil
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
    << "  --optimizations  Explain lowering costs in the entry source"
    << "  --optimizations-json  Emit the explanation as JSON"
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
  elsif arg in ("--optimizations" "--optimizations-json")
    emit_wire = true
    optimizations_mode = true
    optimizations_json = arg == "--optimizations-json"
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
  elsif arg == "--batch-link-worker"
    # Internal: parent already emitted .ll; this process only links
    # ll/bin pairs so clang can run in parallel.
    batch_link_worker = true
    command = "compile-batch"
  elsif arg == "--batch-runtime-objs"
    i += 1
    runtime_archive = args[i]
  elsif arg == "--batch-out-dir"
    i += 1
    batch_out_dir = args[i]
  elsif arg == "--ast-stats"
    ast_stats = true
  elsif arg == "--verbose"
    verbose = true
  elsif arg == "-v"
    verbose = true
    if !args.include?("--optimizations-json")
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

if optimizations_json
  verbose = false

# The default compiler image deliberately excludes the legacy tree walker and
# REPL. Interactive/interpret modes are rare and carry thousands of source
# lines that do not contribute to compile, check, or WIRE-run. Re-enter through
# the thin feature image, whose wrapper `use`s those classes before loading this
# driver. The inner process marks its image to prevent recursive delegation.
if env("TUNGSTEN_COMPILER_IMAGE") != "repl" && (wit_mode || interpret_mode)
  delegate_compiler_image("repl")

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
  if batch_out_dir != nil && batch_out_dir != ""
    if system("mkdir -p " + dev_runtime_shell_quote(batch_out_dir)) != true
      << "compile-batch: could not create --batch-out-dir " + batch_out_dir
      exit 1

  if batch_link_worker
    if (files.size() % 2) != 0
      << "compile-batch --batch-link-worker expects ll/bin path pairs"
      exit 1
    fail_count = 0
    pi = 0
    while pi < files.size()
      if !link_binary(files[pi], files[pi + 1], runtime_archive, verbose)
        fail_count += 1
      pi += 2
    if fail_count > 0
      << "[fail_count] file(s) failed to compile"
      exit 1
    exit 0

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
      bin = batch_output_binary(fp)
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

  link_parallel = nil
  if !batch_link_worker && ll_jobs.size() > 1 && env("TUNGSTEN_BATCH_PARALLEL_LINK") != "0"
    link_jobs = batch_parallel_job_count(ll_jobs.size())
    if link_jobs > 1
      if verbose
        << "  parallel link: " + link_jobs.to_s() + " clang workers"
      link_parallel = batch_parallel_link(ll_jobs, runtime_objs, link_jobs, verbose)
  if link_parallel != nil
    if link_parallel[:ok] != true
      if link_parallel[:message] != nil
        << "Parallel batch link failed: " + link_parallel[:message]
      fail_count += link_parallel[:failed]
    ll_jobs -> (job)
      if job[:implicit_ll] && !publish_implicit_ll_path(job[:ll], job[:source])
        fail_count += 1
  else
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
