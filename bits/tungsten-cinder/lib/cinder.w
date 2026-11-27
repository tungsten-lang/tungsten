# cinder — Pure-Tungsten Native Backend, In-Process JIT (ARM64 & x86_64),
# and Direct Binary Mach-O 64 / ELF64 Object & Executable Compiler.

use ./version
use ./buf
use ./jit_mem
use ./a64
use ./x64
use ./macho64
use ./elf64
use ./opt_config
use ./wire_ir
use ./wire_opt
use ./wire_a64
use ./wire_x64
use ./c_to_wire
use ./a64_asm
use ./ll_parser
use ./ll_opt
use ./ll_a64
use ./ll_x64
use ./lto
use ./driver

# Compile a `WireFunc` into executable JIT memory for the current host architecture
# using an explicit `CinderOptConfig` (`-O0..-O3`, `--fast`, `-f[no-]<pass>`, etc.)
# and optional `WireModule` context (`wmod`, used for cross-function inlining).
# Returns `[fn_ptr_i64, code_bytes_i64, compile_us_i64]`.
-> wire_compile_func_opt(wf, opt_cfg, wmod = nil)
  cfg = opt_cfg != nil ? opt_cfg : CinderOptConfig.new(2)
  need_clone = cfg.opt_level > 0 || cfg.pass_enabled?("always-inline")
  wf_in = need_clone ? wf.clone() : wf
  tier = cfg.opt_level >= 1 ? 2 : 1
  res = nil
  if cinder_host_arch() == "x86_64"
    c = WireX64Compiler.new(wf_in, tier, cfg, wmod)
    res = c.compile()
  else
    c = WireA64Compiler.new(wf_in, tier, cfg, wmod)
    res = c.compile()
  cfg.print_report("wire-jit:" + wf.name) if cfg.print_passes
  res

# Compile all functions in a `WireModule` in order, registering each JIT entry address in
# `G_WIRE_JIT_SYMS` so `:call_direct_i64` resolves both inlined and non-inlined module callees.
# Returns `{func_name => [fn_ptr_i64, code_bytes_i64, compile_us_i64]}`.
-> wire_compile_module_opt(wmod, opt_cfg = nil)
  cfg = opt_cfg != nil ? opt_cfg : CinderOptConfig.new(2)
  # Clone the module so bottom-up optimization & transitive inlining (`A -> B -> C`) optimize
  # callees in-place before callers inline them, without mutating the caller's input `wmod`!
  need_clone = cfg.opt_level > 0 || cfg.pass_enabled?("always-inline")
  opt_mod = wmod
  if need_clone
    opt_mod = WireModule.new(wmod.name)
    mi = 0
    while mi < wmod.functions.size()
      opt_mod.add_func(wmod.functions[mi].clone())
      mi += 1
  compiled = {}
  fi = 0
  while fi < opt_mod.functions.size()
    wf_in = opt_mod.functions[fi]
    tier = cfg.opt_level >= 1 ? 2 : 1
    res = nil
    if cinder_host_arch() == "x86_64"
      cx = WireX64Compiler.new(wf_in, tier, cfg, opt_mod)
      res = cx.compile()
    else
      ca = WireA64Compiler.new(wf_in, tier, cfg, opt_mod)
      res = ca.compile()
    wire_register_jit_sym(wf_in.name, res[0]) if res[0] != 0
    compiled[wf_in.name] = res
    fi += 1
  cfg.print_report("wire-module") if cfg.print_passes
  compiled

# Compile a `WireFunc` into executable JIT memory for the current host architecture
# (`"arm64"` -> `WireA64Compiler`, `"x86_64"` -> `WireX64Compiler`).
# `tier`:
#   - `1`: Blazing-fast single-pass baseline compile (`-O0` + `always-inline` only; does NOT mutate `wf`!).
#   - `2`: Full optimizing second-pass compile (`-O2`: inlining, constant folding/hoisting, slot SROA,
#          jump threading, LICM/GVN, Granlund-Montgomery strength reduction, carry chains & SIMD).
# Returns `[fn_ptr_i64, code_bytes_i64, compile_us_i64]`.
-> wire_compile_func_tier(wf, tier)
  cfg = cinder_opt_from_env(tier >= 2 ? 2 : 0)
  need_clone = tier >= 2 || cfg.opt_level > 0
  wf_in = need_clone ? wf.clone() : wf
  if cinder_host_arch() == "x86_64"
    c = WireX64Compiler.new(wf_in, tier, cfg)
    return c.compile()
  c = WireA64Compiler.new(wf_in, tier, cfg)
  c.compile()

-> wire_compile_func(wf)
  wire_compile_func_tier(wf, 2)

# Cross-architecture byte-only WIRE compilation with explicit `CinderOptConfig`.
# Returns `[ok_bool, ByteBuf]`.
-> wire_encode_func_for_arch_opt(wf, arch, opt_cfg, wmod = nil)
  cfg = opt_cfg != nil ? opt_cfg : CinderOptConfig.new(2)
  need_clone = cfg.opt_level > 0 || cfg.pass_enabled?("always-inline")
  wf_in = need_clone ? wf.clone() : wf
  tier = cfg.opt_level >= 1 ? 2 : 1
  if arch == "x86_64"
    cx = WireX64Compiler.new(wf_in, tier, cfg, wmod)
    ok = cx.encode()
    return [ok, cx.a.buf]
  ca = WireA64Compiler.new(wf_in, tier, cfg, wmod)
  ok = ca.encode()
  [ok, ca.a.buf]

# Cross-architecture byte-only WIRE compilation (for cross-testing both backends on any host!).
# Returns `[ok_bool, ByteBuf]`.
-> wire_encode_func_for_arch_tier(wf, arch, tier)
  cfg = cinder_opt_from_env(tier >= 2 ? 2 : 0)
  wf_in = (tier >= 2 || cfg.opt_level > 0) ? wf.clone() : wf
  if arch == "x86_64"
    cx = WireX64Compiler.new(wf_in, tier, cfg)
    ok = cx.encode()
    return [ok, cx.a.buf]
  ca = WireA64Compiler.new(wf_in, tier, cfg)
  ok = ca.encode()
  [ok, ca.a.buf]

-> wire_encode_func_for_arch(wf, arch)
  wire_encode_func_for_arch_tier(wf, arch, 2)

# Parse C source directly into a `WireModule`, optimize with `opt_cfg`, and JIT-compile
# every C function in-process (registering symbols in `G_WIRE_JIT_SYMS` + cross-inlining)!
# Returns `[wmod, compiled_map, parse_us_i64, codegen_us_i64]`.
-> cinder_compile_c_to_wire_jit(c_src, opt_cfg = nil)
  t0 = ccall_nobox("__w_clock_ns_raw") ## i64
  wmod = c_parse_to_wire_module(c_src)
  t1 = ccall_nobox("__w_clock_ns_raw") ## i64
  compiled = wire_compile_module_opt(wmod, opt_cfg)
  t2 = ccall_nobox("__w_clock_ns_raw") ## i64
  [wmod, compiled, (t1 - t0) / 1000, (t2 - t1) / 1000]
