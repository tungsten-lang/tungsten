# cinder/buf — Fast growable binary byte buffer with direct C file output.
#
# Used by Cinder's x86_64/ARM64 assemblers and Mach-O / ELF64 binary object writers
# to emit multi-megabyte .o files in milliseconds without String concatenation.

fn cinder_raw_u8_ptr(arr_bits) (i64) i64
  ll <<~IR
    %p = and i64 %arr_bits, 281474976710648
    %q = inttoptr i64 %p to ptr
    %st_p = getelementptr i8, ptr %q, i64 4
    %st32 = load i32, ptr %st_p, align 4
    %st64 = sext i32 %st32 to i64
    %sl_p = getelementptr i8, ptr %q, i64 16
    %sl = load i64, ptr %sl_p, align 8
    %res = add i64 %sl, %st64
    ret i64 %res
  IR

fn cinder_raw_memcpy(dst, src, n) (i64 i64 i64) i64
  ll <<~IR
    %dp = inttoptr i64 %dst to ptr
    %sp = inttoptr i64 %src to ptr
    call void @llvm.memcpy.p0.p0.i64(ptr %dp, ptr %sp, i64 %n, i1 false)
    ret i64 0
  IR

fn cinder_heap_str_ptr(s_bits) (i64) i64
  ll <<~IR
    %r = call i64 @w_string_data_ptr(i64 %s_bits)
    ret i64 %r
  IR

fn cinder_raw_str_blen(s_bits) (i64) i64
  ll <<~IR
    %r = call i64 @w_string_byte_length(i64 %s_bits)
    ret i64 %r
  IR

-> cinder_blen(s)
  cinder_raw_str_blen(wvalue_bits(s) ## i64)

-> cinder_str_to_cstr_u8(s)
  n = cinder_blen(s)
  arr = u8[n + 1]
  if n > 16
    sp = cinder_heap_str_ptr(wvalue_bits(s) ## i64)
    dp = cinder_raw_u8_ptr(wvalue_bits(arr) ## i64)
    cinder_raw_memcpy(dp, sp, n)
  else
    i = 0
    while i < n
      arr[i] = (s.byte_at(i) & 0xFF) ## u8
      i += 1
  arr[n] = 0 ## u8
  arr

fn cinder_buf_call1(fp, a0) (i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0)
    ret i64 %r
  IR

fn cinder_buf_call2(fp, a0, a1) (i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1)
    ret i64 %r
  IR

fn cinder_buf_call3(fp, a0, a1, a2) (i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2)
    ret i64 %r
  IR

fn cinder_buf_call4(fp, a0, a1, a2, a3) (i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2, i64 %a3)
    ret i64 %r
  IR

CINDER_STDIO_PTRS = i64[7]

-> cinder_init_stdio_ptrs
  return nil if CINDER_STDIO_PTRS[0] != 0
  h = 0
  on macos
    h = -2
  CINDER_STDIO_PTRS[1] = ccall("w_dlsym", h, "fopen") ## i64
  CINDER_STDIO_PTRS[2] = ccall("w_dlsym", h, "fwrite") ## i64
  CINDER_STDIO_PTRS[3] = ccall("w_dlsym", h, "fclose") ## i64
  CINDER_STDIO_PTRS[4] = ccall("w_dlsym", h, "fseek") ## i64
  CINDER_STDIO_PTRS[5] = ccall("w_dlsym", h, "ftell") ## i64
  CINDER_STDIO_PTRS[6] = ccall("w_dlsym", h, "fread") ## i64
  CINDER_STDIO_PTRS[0] = 1
  nil

-> cinder_write_raw_file(path, data_ptr, nbytes)
  cinder_init_stdio_ptrs()
  p_arr = cinder_str_to_cstr_u8(path)
  m_arr = cinder_str_to_cstr_u8("wb")
  p_cstr = cinder_raw_u8_ptr(wvalue_bits(p_arr) ## i64)
  mode_cstr = cinder_raw_u8_ptr(wvalue_bits(m_arr) ## i64)
  fp = cinder_buf_call2(CINDER_STDIO_PTRS[1], p_cstr, mode_cstr)
  return false if fp == 0
  wrote = 0
  if nbytes > 0
    wrote = cinder_buf_call4(CINDER_STDIO_PTRS[2], data_ptr, 1, nbytes, fp)
  rc = cinder_buf_call1(CINDER_STDIO_PTRS[3], fp) & 0xFFFFFFFF
  wrote == nbytes && rc == 0

-> cinder_read_raw_file_buf(path)
  cinder_init_stdio_ptrs()
  p_arr = cinder_str_to_cstr_u8(path)
  m_arr = cinder_str_to_cstr_u8("rb")
  p_cstr = cinder_raw_u8_ptr(wvalue_bits(p_arr) ## i64)
  mode_cstr = cinder_raw_u8_ptr(wvalue_bits(m_arr) ## i64)
  fp = cinder_buf_call2(CINDER_STDIO_PTRS[1], p_cstr, mode_cstr)
  return nil if fp == 0
  cinder_buf_call3(CINDER_STDIO_PTRS[4], fp, 0, 2)
  sz = cinder_buf_call1(CINDER_STDIO_PTRS[5], fp)
  if sz < 0
    cinder_buf_call1(CINDER_STDIO_PTRS[3], fp)
    return nil
  cinder_buf_call3(CINDER_STDIO_PTRS[4], fp, 0, 0)
  bb = ByteBuf.new(sz + 16)
  bb.reserve(sz + 8)
  got = 0
  if sz > 0
    got = cinder_buf_call4(CINDER_STDIO_PTRS[6], bb.raw_ptr(), 1, sz, fp)
  cinder_buf_call1(CINDER_STDIO_PTRS[3], fp)
  return nil if got != sz
  bb.len = sz
  bb

+ ByteBuf
  rw :data, :len, :cap

  -> new(init_cap = 1024)
    c = init_cap < 64 ? 64 : init_cap
    @cap = c
    @data = u8[c]
    @len = 0

  -> reserve(extra)
    need = @len + extra
    return nil if need <= @cap
    nc = @cap * 2
    while nc < need
      nc = nc * 2
    old_d = @data
    nd = u8[nc]
    if @len > 0
      src_p = cinder_raw_u8_ptr(wvalue_bits(old_d) ## i64)
      dst_p = cinder_raw_u8_ptr(wvalue_bits(nd) ## i64)
      cinder_raw_memcpy(dst_p, src_p, @len)
    @data = nd
    @cap = nc
    ccall("w_value_free_w", old_d)
    nil

  -> raw_ptr
    cinder_raw_u8_ptr(wvalue_bits(@data) ## i64)

  -> put_u8(v)
    reserve(1)
    @data[@len] = (v & 0xFF) ## u8
    @len += 1
    nil

  -> put_u16_le(v)
    reserve(2)
    d = @data
    p = @len
    d[p]     = (v & 0xFF) ## u8
    d[p + 1] = ((v >> 8) & 0xFF) ## u8
    @len = p + 2
    nil

  -> put_u32_le(v)
    reserve(4)
    d = @data
    p = @len
    d[p]     = (v & 0xFF) ## u8
    d[p + 1] = ((v >> 8) & 0xFF) ## u8
    d[p + 2] = ((v >> 16) & 0xFF) ## u8
    d[p + 3] = ((v >> 24) & 0xFF) ## u8
    @len = p + 4
    nil

  -> put_u64_le(v)
    reserve(8)
    d = @data
    p = @len
    d[p]     = (v & 0xFF) ## u8
    d[p + 1] = ((v >> 8) & 0xFF) ## u8
    d[p + 2] = ((v >> 16) & 0xFF) ## u8
    d[p + 3] = ((v >> 24) & 0xFF) ## u8
    d[p + 4] = ((v >> 32) & 0xFF) ## u8
    d[p + 5] = ((v >> 40) & 0xFF) ## u8
    d[p + 6] = ((v >> 48) & 0xFF) ## u8
    d[p + 7] = ((v >> 56) & 0xFF) ## u8
    @len = p + 8
    nil

  -> patch_u8(off, v)
    @data[off] = (v & 0xFF) ## u8
    nil

  -> patch_u32_le(off, v)
    d = @data
    d[off]     = (v & 0xFF) ## u8
    d[off + 1] = ((v >> 8) & 0xFF) ## u8
    d[off + 2] = ((v >> 16) & 0xFF) ## u8
    d[off + 3] = ((v >> 24) & 0xFF) ## u8
    nil

  -> patch_u64_le(off, v)
    d = @data
    d[off]     = (v & 0xFF) ## u8
    d[off + 1] = ((v >> 8) & 0xFF) ## u8
    d[off + 2] = ((v >> 16) & 0xFF) ## u8
    d[off + 3] = ((v >> 24) & 0xFF) ## u8
    d[off + 4] = ((v >> 32) & 0xFF) ## u8
    d[off + 5] = ((v >> 40) & 0xFF) ## u8
    d[off + 6] = ((v >> 48) & 0xFF) ## u8
    d[off + 7] = ((v >> 56) & 0xFF) ## u8
    nil

  -> read_u8(off)
    (@data[off] ## i64) & 0xFF

  -> read_u16_le(off)
    d = @data
    ((d[off] ## i64) & 0xFF) | (((d[off + 1] ## i64) & 0xFF) << 8)

  -> read_u32_le(off)
    d = @data
    b0 = (d[off] ## i64) & 0xFF
    b1 = (d[off + 1] ## i64) & 0xFF
    b2 = (d[off + 2] ## i64) & 0xFF
    b3 = (d[off + 3] ## i64) & 0xFF
    b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)

  -> read_u64_le(off)
    lo = read_u32_le(off)
    hi = read_u32_le(off + 4)
    lo | (hi << 32)

  -> slice_ascii(off, n)
    return "" if n <= 0 || off < 0 || off + n > @len
    arr = u8[n + 1]
    cinder_raw_memcpy(cinder_raw_u8_ptr(wvalue_bits(arr) ## i64), raw_ptr() + off, n)
    ccall("w_string_take_byte_array", arr, n)

  -> put_zeros(n)
    return nil if n <= 0
    reserve(n)
    d = @data
    p = @len
    e = p + n
    while p < e
      d[p] = 0 ## u8
      p += 1
    @len = e
    nil

  -> align_to(pow2_bytes, fill_byte = 0)
    return nil if pow2_bytes <= 1
    rem = @len & (pow2_bytes - 1)
    return nil if rem == 0
    pad = pow2_bytes - rem
    reserve(pad)
    fb = (fill_byte & 0xFF) ## u8
    d = @data
    p = @len
    e = p + pad
    while p < e
      d[p] = fb
      p += 1
    @len = e
    nil

  -> put_buf(other)
    n = other.len
    return nil if n <= 0
    reserve(n)
    cinder_raw_memcpy(raw_ptr() + @len, other.raw_ptr(), n)
    @len += n
    nil

  -> put_raw_bytes(src_u8, n)
    return nil if n <= 0
    reserve(n)
    cinder_raw_memcpy(raw_ptr() + @len, cinder_raw_u8_ptr(wvalue_bits(src_u8) ## i64), n)
    @len += n
    nil

  -> put_ascii(s)
    n = cinder_blen(s)
    return nil if n <= 0
    reserve(n)
    if n > 16
      sp = cinder_heap_str_ptr(wvalue_bits(s) ## i64)
      cinder_raw_memcpy(raw_ptr() + @len, sp, n)
      @len += n
    else
      d = @data
      p = @len
      i = 0
      while i < n
        d[p + i] = (s.byte_at(i) & 0xFF) ## u8
        i += 1
      @len = p + n
    nil

  -> put_cstr(s)
    off = @len
    put_ascii(s)
    put_u8(0)
    off

  -> write_file(path)
    cinder_write_raw_file(path, raw_ptr(), @len)
