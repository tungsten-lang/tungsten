# jsn/jit_mem — in-process executable memory (MAP_JIT on Apple Silicon ARM64)
# and low-level native call / closure ABI helpers for the JS ARM64 JIT.

in JS

# 64 MB contiguous MAP_JIT slab so all JITted functions and stubs stay within
# ARM64's ±128 MB direct `bl` branch range.
JIT_SLAB_SIZE = 67108864

# [base_addr, cursor, capacity, fn_mmap, fn_wp, fn_icache, enabled]
JIT_MEM = i64[8]

# ---- Raw C-ABI call trampolines ----

fn jit_raw_call0(fp) (i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f()
    ret i64 %r
  IR

fn jit_raw_call1(fp, a0) (i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0)
    ret i64 %r
  IR

fn jit_raw_call2(fp, a0, a1) (i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1)
    ret i64 %r
  IR

fn jit_raw_call3(fp, a0, a1, a2) (i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2)
    ret i64 %r
  IR

fn jit_raw_call4(fp, a0, a1, a2, a3) (i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2, i64 %a3)
    ret i64 %r
  IR

fn jit_raw_call6(fp, a0, a1, a2, a3, a4, a5) (i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5)
    ret i64 %r
  IR

fn jit_raw_call8(fp, a0, a1, a2, a3, a4, a5, a6, a7) (i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6, i64 %a7)
    ret i64 %r
  IR

# ---- Raw memory access ----

fn jit_store32(addr, off, val) (i64 i64 i64) i64
  ll <<~IR
    %p = add i64 %addr, %off
    %q = inttoptr i64 %p to ptr
    %v = trunc i64 %val to i32
    store i32 %v, ptr %q, align 4
    ret i64 0
  IR

fn jit_load32(addr, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %addr, %off
    %q = inttoptr i64 %p to ptr
    %v = load i32, ptr %q, align 4
    %r = zext i32 %v to i64
    ret i64 %r
  IR

fn jit_store64(addr, off, val) (i64 i64 i64) i64
  ll <<~IR
    %p = add i64 %addr, %off
    %q = inttoptr i64 %p to ptr
    store i64 %val, ptr %q, align 8
    ret i64 0
  IR

fn jit_load64(addr, off) (i64 i64) i64
  ll <<~IR
    %p = add i64 %addr, %off
    %q = inttoptr i64 %p to ptr
    %v = load i64, ptr %q, align 8
    ret i64 %v
  IR

# Copy `count` 32-bit words from an i64[] buffer into executable memory at `dst`.
fn jit_copy_words(dst, src, count) (i64 i64[] i64) i64
  i = 0
  while i < count
    jit_store32(dst, i * 4, src[i])
    i += 1
  0

# Raw pointer of an i64[] typed array's data buffer (a->slots at offset 16 of WArray).
-> jit_i64_ptr(a)
  jit_arr_slots_ptr(wvalue_bits(a) ## i64)

# Raw fn_ptr and captures pointer from a boxed Tungsten closure WValue.
fn jit_cl_fn(cl_bits) (i64) i64
  ll <<~IR
    %p = and i64 %cl_bits, 140737488355312
    %q = inttoptr i64 %p to ptr
    %f = load i64, ptr %q, align 8
    ret i64 %f
  IR

fn jit_cl_caps(cl_bits) (i64) i64
  ll <<~IR
    %p = and i64 %cl_bits, 140737488355312
    %q = inttoptr i64 %p to ptr
    %a = getelementptr i8, ptr %q, i64 8
    %c = load i64, ptr %a, align 8
    ret i64 %c
  IR

# Raw pointer to a WArray's WValue slots (offset 16 of WArray struct).
fn jit_arr_slots_ptr(arr_bits) (i64) i64
  ll <<~IR
    %p = and i64 %arr_bits, 140737488355312
    %q = inttoptr i64 %p to ptr
    %a = getelementptr i8, ptr %q, i64 16
    %s = load i64, ptr %a, align 8
    ret i64 %s
  IR

# Raw pointer to a WArray's byte buffer (ByteArray uses WArray with ebits=8).
fn jit_bytearray_ptr(ba_bits) (i64) i64
  ll <<~IR
    %p = and i64 %ba_bits, 140737488355312
    %q = inttoptr i64 %p to ptr
    %a = getelementptr i8, ptr %q, i64 16
    %s = load i64, ptr %a, align 8
    ret i64 %s
  IR

# IEEE 754 bit pattern of a Float WValue (unbiased 64-bit double bits).
fn jit_f64_bits(v_bits) (i64) i64
  ll <<~IR
    %r = sub i64 %v_bits, 281474976710656
    ret i64 %r
  IR

# ---- Executable slab management ----

-> jit_mem_init
  return JIT_MEM[6] == 1 if JIT_MEM[6] != 0
  if Env.get("BLADE_JS_JIT", "1") == "0"
    JIT_MEM[6] = -1
    return false
  # RTLD_DEFAULT on macOS = -2
  h = -2
  p_mmap = ccall("w_dlsym", h, "mmap")
  p_wp = ccall("w_dlsym", h, "pthread_jit_write_protect_np")
  p_ic = ccall("w_dlsym", h, "sys_icache_invalidate")
  if p_mmap == nil || p_wp == nil || p_ic == nil
    JIT_MEM[6] = -1
    return false
  # PROT_READ|PROT_WRITE|PROT_EXEC = 7
  # MAP_PRIVATE (0x0002) | MAP_ANON (0x1000) | MAP_JIT (0x0800) = 0x1802 = 6146
  base = jit_raw_call6(p_mmap ## i64, 0, JIT_SLAB_SIZE, 7, 6146, -1, 0)
  if base == -1 || base == 0
    JIT_MEM[6] = -1
    return false
  JIT_MEM[0] = base
  JIT_MEM[1] = 0
  JIT_MEM[2] = JIT_SLAB_SIZE
  JIT_MEM[3] = p_mmap ## i64
  JIT_MEM[4] = p_wp ## i64
  JIT_MEM[5] = p_ic ## i64
  JIT_MEM[6] = 1
  true

-> jit_mem_ready?
  JIT_MEM[6] == 1 || (JIT_MEM[6] == 0 && jit_mem_init())

# Allocate `nbytes` (16-byte aligned) in the executable slab and copy `words[0..nwords)`.
# Returns the executable start address (i64), or 0 on failure.
-> jit_mem_emit(words, nwords)
  return 0 if !jit_mem_ready?()
  nbytes = ((nwords * 4 + 15) / 16) * 16
  cur = JIT_MEM[1]
  if cur + nbytes > JIT_MEM[2]
    # Allocate a fresh slab if full
    base = jit_raw_call6(JIT_MEM[3], 0, JIT_SLAB_SIZE, 7, 6146, -1, 0)
    return 0 if base == -1 || base == 0
    JIT_MEM[0] = base
    JIT_MEM[1] = 0
    JIT_MEM[2] = JIT_SLAB_SIZE
    cur = 0
  addr = JIT_MEM[0] + cur
  JIT_MEM[1] = cur + nbytes
  jit_raw_call1(JIT_MEM[4], 0)   # write-enable MAP_JIT on this thread
  jit_copy_words(addr, words, nwords)
  jit_raw_call1(JIT_MEM[4], 1)   # exec-enable MAP_JIT on this thread
  jit_raw_call2(JIT_MEM[5], addr, nbytes)
  addr

# Patch a single 32-bit instruction in-place inside MAP_JIT memory.
-> jit_mem_patch32(addr, insn)
  return nil if JIT_MEM[6] != 1
  jit_raw_call1(JIT_MEM[4], 0)
  jit_store32(addr, 0, insn)
  jit_raw_call1(JIT_MEM[4], 1)
  jit_raw_call2(JIT_MEM[5], addr, 4)
  nil
