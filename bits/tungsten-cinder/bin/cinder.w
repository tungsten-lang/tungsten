# bin/cinder.w — CLI entry point for Cinder (`bits/tungsten-cinder`).

use ../lib/cinder

-> cinder_usage
  << "cinder " + CINDER_VERSION + " — Pure-Tungsten Native Backend, JIT & Mach-O/ELF64 Compiler"
  << ""
  << "Usage:"
  << "  cinder compile <input.w|input.ll> \[options\] \[-c\] \[-o <output>\]"
  << "  cinder run <input.w> \[options\] \[-- <args...>\]"
  << "  cinder verify-stages <input.w|input.ll> \[options\]"
  << "  cinder info"
  << ""
  << "Optimization & Codegen Options:"
  << "  -O0, -O1, -O2, -O3   Optimization level (default: -O2; -O0 blazing-fast baseline)"
  << "  -Ofast, --fast       Fast FP math (FMA contraction, reciprocal const fdiv)"
  << "  -ffast-math / -fno-fast-math"
  << "  --strict-math        Strict IEEE 754 floating-point (disable FP contraction)"
  << "  --debug, -g          Keep frame pointers, symbols, and un-stripped internal helpers"
  << "  --no-debug           Omit debug metadata, allow leaf frame elim & dead helper GC"
  << "  --\[no-\]frame-pointers, -f\[no-\]omit-frame-pointer"
  << "  -f<pass>, -fno-<pass>  Enable or disable individual optimization passes:"
  << "                         always-inline, inline, const-fold, sroa, jump-threading,"
  << "                         gvn, licm, strength-reduce, carry-chains, simd,"
  << "                         unroll-loops, dce, peephole, reg-promote, leaf-frame-elim"
  << "  --opt-passes=LIST    Comma-separated explicit pass list or +/-pass overrides"
  << "  --print-passes       Print enabled pass pipeline and per-pass transformation counts"
  << ""
  << "Driver Options:"
  << "  -c                   Emit relocatable object file (.o) only, skip linking"
  << "  -o, --out FILE       Output binary or object path"
  << "  --target TRIPLE      Target triple (arm64-apple-macosx, x86_64-unknown-linux-gnu, aarch64-unknown-linux-gnu)"
  << "  -v, --verbose        Print phase timings and output sizes"
  << "  -h, --help           Show this help"
  nil

args = argv()
if args.size() == 0
  cinder_usage()
  exit 0

cmd = "compile"
in_path = nil
out_path = nil
emit_obj = false
target_triple = ""
verbose = false
run_args = []
in_run_args = false
opt_cfg = cinder_opt_from_env(2)

i = 0
while i < args.size()
  a = args[i]
  if in_run_args
    run_args.push(a)
  elsif a == "--"
    in_run_args = true
  elsif a == "-h" || a == "--help" || a == "help"
    cinder_usage()
    exit 0
  elsif a == "--version"
    << "cinder " + CINDER_VERSION
    exit 0
  elsif a == "info" && in_path == nil
    << "cinder " + CINDER_VERSION
    << "  host_os:        " + cinder_host_os()
    << "  host_arch:      " + cinder_host_arch()
    << "  default_target: " + cinder_default_target()
    << "  jit_ready:      " + cinder_jit_ready?().to_s()
    << "  default_opt:    " + opt_cfg.summary()
    exit 0
  elsif (a == "compile" || a == "run" || a == "verify-stages") && in_path == nil
    cmd = a
  elsif a == "-c"
    emit_obj = true
  elsif a == "-v" || a == "--verbose"
    verbose = true
  elsif a == "-o" || a == "--out"
    i += 1
    out_path = args[i]
  elsif a.starts_with?("-o=")
    out_path = a.slice(3, a.size() - 3)
  elsif a.starts_with?("--out=")
    out_path = a.slice(6, a.size() - 6)
  elsif a == "--target"
    i += 1
    target_triple = args[i]
  elsif a.starts_with?("--target=")
    target_triple = a.slice(9, a.size() - 9)
  elsif opt_cfg.apply_arg(a)
    nil
  elsif a.starts_with?("-")
    ccall("w_eputs", "cinder: unknown option: " + a)
    exit 1
  elsif in_path == nil
    in_path = a
  else
    run_args.push(a)
  i += 1

if in_path == nil
  if opt_cfg.print_passes
    << opt_cfg.summary()
    exit 0
  ccall("w_eputs", "cinder: missing input file")
  exit 1

if cmd == "verify-stages"
  ok = cinder_verify_stage_determinism(in_path, opt_cfg, target_triple, true)
  exit(ok ? 0 : 1)

if cmd == "run"
  tmp_bin = "/tmp/cinder_run_" + (ccall_nobox("__w_clock_ns_raw") ## i64).to_s()
  if !cinder_compile_input(in_path, tmp_bin, false, target_triple, verbose, opt_cfg)
    exit 1
  exec_cmd = cinder_shq(tmp_bin)
  ri = 0
  while ri < run_args.size()
    exec_cmd = exec_cmd + " " + cinder_shq(run_args[ri])
    ri += 1
  ok = system(exec_cmd)
  system("rm -f " + cinder_shq(tmp_bin) + " " + cinder_shq(tmp_bin + ".sidemap"))
  exit(ok ? 0 : 1)

if out_path == nil
  base = in_path
  if base.ends_with?(".w")
    base = base.slice(0, base.size() - 2)
  elsif base.ends_with?(".ll")
    base = base.slice(0, base.size() - 3)
  out_path = emit_obj ? (base + ".o") : base

if !cinder_compile_input(in_path, out_path, emit_obj, target_triple, verbose, opt_cfg)
  exit 1
exit 0
