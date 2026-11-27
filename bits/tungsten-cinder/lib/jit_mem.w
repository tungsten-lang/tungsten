# cinder/jit_mem — Cross-platform executable memory slab & raw C-ABI call trampolines.
#
# Supports:
#   - macOS ARM64: MAP_PRIVATE | MAP_ANON | MAP_JIT (0x1802 = 6146),
#     pthread_jit_write_protect_np, sys_icache_invalidate, RTLD_DEFAULT = -2.
#   - Linux x86_64 & aarch64: MAP_PRIVATE | MAP_ANONYMOUS (0x22 = 34),
#     PROT_READ | PROT_WRITE | PROT_EXEC (7) with W^X mprotect fallback,
#     RTLD_DEFAULT = 0 (glibc/musl NULL handle).

use ./buf

CINDER_JIT_SLAB_SIZE = 67108864

# [base_addr, cursor, capacity, fn_mmap, fn_wp, fn_icache, state, is_macos, fn_mprotect]
CINDER_JIT_MEM = i64[10]
CINDER_HOST_MEMO = {}
CINDER_C_SYMS = {}

-> cinder_host_os
  on macos
    return "macos"
  on linux
    return "linux"
  cached = CINDER_HOST_MEMO[:os]
  return cached if cached != nil
  u = capture("uname -s").strip()
  res = u == "Darwin" ? "macos" : (u == "Linux" ? "linux" : u.downcase())
  CINDER_HOST_MEMO[:os] = res
  res

-> cinder_host_arch
  on arm64
    return "arm64"
  on x86_64
    return "x86_64"
  cached = CINDER_HOST_MEMO[:arch]
  return cached if cached != nil
  m = capture("uname -m").strip()
  res = (m == "arm64" || m == "aarch64") ? "arm64" : ((m == "x86_64" || m == "amd64") ? "x86_64" : m)
  CINDER_HOST_MEMO[:arch] = res
  res

-> cinder_rtld_default
  cinder_host_os() == "macos" ? -2 : 0

-> cinder_resolve_c_sym(name)
  addr = CINDER_C_SYMS[name]
  return addr if addr != nil
  p = ccall("w_dlsym", cinder_rtld_default(), name)
  a = p == nil ? 0 : (p ## i64)
  CINDER_C_SYMS[name] = a
  a

# ---- Raw C-ABI call trampolines ----

fn cinder_raw_call0(fp) (i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f()
    ret i64 %r
  IR

fn cinder_raw_call1(fp, a0) (i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0)
    ret i64 %r
  IR

fn cinder_raw_call2(fp, a0, a1) (i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1)
    ret i64 %r
  IR

fn cinder_raw_call3(fp, a0, a1, a2) (i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2)
    ret i64 %r
  IR

fn cinder_raw_call4(fp, a0, a1, a2, a3) (i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2, i64 %a3)
    ret i64 %r
  IR

fn cinder_raw_call5(fp, a0, a1, a2, a3, a4) (i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4)
    ret i64 %r
  IR

fn cinder_raw_call6(fp, a0, a1, a2, a3, a4, a5) (i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5)
    ret i64 %r
  IR

fn cinder_raw_call8(fp, a0, a1, a2, a3, a4, a5, a6, a7) (i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6, i64 %a7)
    ret i64 %r
  IR

fn cinder_store8(addr, off, val) (i64 i64 i64) i64
  ll <<~IR
    %p = add i64 %addr, %off
    %q = inttoptr i64 %p to ptr
    %v = trunc i64 %val to i8
    store i8 %v, ptr %q, align 1
    ret i64 0
  IR

fn cinder_store32(addr, off, val) (i64 i64 i64) i64
  ll <<~IR
    %p = add i64 %addr, %off
    %q = inttoptr i64 %p to ptr
    %v = trunc i64 %val to i32
    store i32 %v, ptr %q, align 4
    ret i64 0
  IR

fn cinder_load32(addr, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %addr, %off
    %q = inttoptr i64 %p to ptr
    %v = load i32, ptr %q, align 4
    %r = zext i32 %v to i64
    ret i64 %r
  IR

fn cinder_store64(addr, off, val) (i64 i64 i64) i64
  ll <<~IR
    %p = add i64 %addr, %off
    %q = inttoptr i64 %p to ptr
    store i64 %val, ptr %q, align 8
    ret i64 0
  IR

fn cinder_load64(addr, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %addr, %off
    %q = inttoptr i64 %p to ptr
    %v = load i64, ptr %q, align 8
    ret i64 %v
  IR

fn cinder_copy_words(dst, src, count) (i64 i64[] i64) i64
  i = 0
  while i < count
    cinder_store32(dst, i * 4, src[i])
    i += 1
  0

-> cinder_jit_alloc_slab
  p_mmap = CINDER_JIT_MEM[3]
  is_mac = CINDER_JIT_MEM[7] == 1
  flags = is_mac ? 6146 : 34
  base = cinder_raw_call6(p_mmap, 0, CINDER_JIT_SLAB_SIZE, 7, flags, -1, 0)
  if (base == -1 || base == 0) && !is_mac
    # Hardened Linux fallback: allocate RW (3) and toggle via mprotect
    base = cinder_raw_call6(p_mmap, 0, CINDER_JIT_SLAB_SIZE, 3, flags, -1, 0)
    if base != -1 && base != 0
      CINDER_JIT_MEM[9] = 1
  base

-> cinder_jit_init
  return CINDER_JIT_MEM[6] == 1 if CINDER_JIT_MEM[6] != 0
  if env("CINDER_JIT") == "0"
    CINDER_JIT_MEM[6] = -1
    return false
  is_mac = cinder_host_os() == "macos"
  CINDER_JIT_MEM[7] = is_mac ? 1 : 0
  h = is_mac ? -2 : 0
  p_mmap = ccall("w_dlsym", h, "mmap")
  if p_mmap == nil
    CINDER_JIT_MEM[6] = -1
    return false
  CINDER_JIT_MEM[3] = p_mmap ## i64
  if is_mac
    p_wp = ccall("w_dlsym", h, "pthread_jit_write_protect_np")
    p_ic = ccall("w_dlsym", h, "sys_icache_invalidate")
    if p_wp == nil || p_ic == nil
      CINDER_JIT_MEM[6] = -1
      return false
    CINDER_JIT_MEM[4] = p_wp ## i64
    CINDER_JIT_MEM[5] = p_ic ## i64
  else
    p_mp = ccall("w_dlsym", h, "mprotect")
    CINDER_JIT_MEM[8] = p_mp == nil ? 0 : (p_mp ## i64)
    p_cc = ccall("w_dlsym", h, "__clear_cache")
    CINDER_JIT_MEM[5] = p_cc == nil ? 0 : (p_cc ## i64)
  base = cinder_jit_alloc_slab()
  if base == -1 || base == 0
    CINDER_JIT_MEM[6] = -1
    return false
  CINDER_JIT_MEM[0] = base
  CINDER_JIT_MEM[1] = 0
  CINDER_JIT_MEM[2] = CINDER_JIT_SLAB_SIZE
  CINDER_JIT_MEM[6] = 1
  true

-> cinder_jit_ready?
  CINDER_JIT_MEM[6] == 1 || (CINDER_JIT_MEM[6] == 0 && cinder_jit_init())

-> cinder_jit_reserve(raw_nbytes)
  return 0 if !cinder_jit_ready?()
  nbytes = ((raw_nbytes + 15) / 16) * 16
  nbytes = 16 if nbytes < 16
  cur = CINDER_JIT_MEM[1]
  if cur + nbytes > CINDER_JIT_MEM[2]
    base = cinder_jit_alloc_slab()
    return 0 if base == -1 || base == 0
    CINDER_JIT_MEM[0] = base
    CINDER_JIT_MEM[1] = 0
    CINDER_JIT_MEM[2] = CINDER_JIT_SLAB_SIZE
    cur = 0
  addr = CINDER_JIT_MEM[0] + cur
  CINDER_JIT_MEM[1] = cur + nbytes
  addr

-> cinder_jit_begin_write(addr, nbytes)
  if CINDER_JIT_MEM[7] == 1
    cinder_raw_call1(CINDER_JIT_MEM[4], 0)
  elsif CINDER_JIT_MEM[9] == 1 && CINDER_JIT_MEM[8] != 0
    page_base = addr & -4096
    page_len = ((addr + nbytes - page_base + 4095) / 4096) * 4096
    cinder_raw_call3(CINDER_JIT_MEM[8], page_base, page_len, 3)
  nil

-> cinder_jit_end_write(addr, nbytes)
  if CINDER_JIT_MEM[7] == 1
    cinder_raw_call1(CINDER_JIT_MEM[4], 1)
    cinder_raw_call2(CINDER_JIT_MEM[5], addr, nbytes)
  else
    if CINDER_JIT_MEM[9] == 1 && CINDER_JIT_MEM[8] != 0
      page_base = addr & -4096
      page_len = ((addr + nbytes - page_base + 4095) / 4096) * 4096
      cinder_raw_call3(CINDER_JIT_MEM[8], page_base, page_len, 5)
    if cinder_host_arch() == "arm64" && CINDER_JIT_MEM[5] != 0
      cinder_raw_call2(CINDER_JIT_MEM[5], addr, addr + nbytes)
  nil

# Emit 32-bit ARM64 instruction words (i64[]) into executable memory.
-> cinder_jit_emit_words(words, nwords)
  nbytes = nwords * 4
  addr = cinder_jit_reserve(nbytes)
  return 0 if addr == 0
  aligned = ((nbytes + 15) / 16) * 16
  cinder_jit_begin_write(addr, aligned)
  cinder_copy_words(addr, words, nwords)
  cinder_jit_end_write(addr, aligned)
  addr

# Emit raw machine-code bytes (ByteBuf) into executable memory (used on x86_64 & ARM64).
-> cinder_jit_emit_buf(buf)
  nbytes = buf.len
  addr = cinder_jit_reserve(nbytes)
  return 0 if addr == 0
  aligned = ((nbytes + 15) / 16) * 16
  cinder_jit_begin_write(addr, aligned)
  cinder_raw_memcpy(addr, buf.raw_ptr(), nbytes)
  cinder_jit_end_write(addr, aligned)
  addr
