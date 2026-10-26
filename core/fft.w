# FFT — discrete Fourier transform (native Cooley–Tukey radix-2).
#
# API:
#   FFT.fft(re, im)   → [re_out, im_out]  complex DFT, length power of 2
#   FFT.ifft(re, im)  → inverse (normalized 1/n)
#   FFT.rfft(x)       → real-input FFT (im = 0)
#   FFT.fft2(re, im, rows, cols)  row-column 2-D
#
# Complex numbers are split real/imag arrays (plain Tungsten lists of Float)
# so this works without a Complex dependency at the call site. Prefer
# Complex[] when building higher-level code (core/numeric/hypercomplex).
#
# Backend: pure Tungsten O(n log n). On macOS, large power-of-two f32 paths
# can later route through vDSP_fft (runtime/blas_bridge.c) — same symbol
# scheme as GEMM. Benchmarks in benchmarks/fft/ compare to NumPy/FFTW.

+ FFT
  -> .is_pow2(n)
    if n <= 0
      return false
    (n & (n - 1)) == 0

  # In-place iterative radix-2 Cooley–Tukey on re[]/im[] of length n.
  -> .fft_inplace(re, im, inverse)
    n = re.size()
    if FFT.is_pow2(n) == false
      raise "FFT: length must be a power of 2 (got " + n.to_s() + ")"
    if n >= 16
      fast = ccall("w_array_memmove_f64", re, im, inverse ? -5 : -4)
      if fast != nil
        return [re, im]
    rb = f64[n]
    ib = f64[n]
    if n >= 4 && type(re[0]) == "Float" && type(im[0]) == "Float"
      ccall("w_array_memmove_f64", re, rb, n)
      ccall("w_array_memmove_f64", im, ib, n)
    else
      i = 0 ## i64
      while i < n
        rb[i] = re[i]
        ib[i] = im[i]
        i = i + 1
    fft_radix2_kernel(rb, ib, n, inverse ? 1 : 0)
    if n >= 4
      ccall("w_array_memmove_f64", rb, re, n)
      ccall("w_array_memmove_f64", ib, im, n)
    else
      i = 0 ## i64
      while i < n
        re[i] = rb[i]
        im[i] = ib[i]
        i = i + 1
    [re, im]

  -> .fft(re_in, im_in)
    n = re_in.size()
    if FFT.is_pow2(n) == false
      raise "FFT: length must be a power of 2 (got " + n.to_s() + ")"
    if n >= 16
      fast = ccall("w_array_memmove_f64", re_in, im_in, -2)
      if fast != nil
        return fast
    rb = f64[n]
    ib = f64[n]
    if n >= 4 && type(re_in[0]) == "Float" && type(im_in[0]) == "Float"
      ccall("w_array_memmove_f64", re_in, rb, n)
      ccall("w_array_memmove_f64", im_in, ib, n)
    else
      i = 0 ## i64
      while i < n
        rb[i] = re_in[i]
        ib[i] = im_in[i]
        i = i + 1
    fft_radix2_kernel(rb, ib, n, 0)
    re = ccall("w_array_memmove_f64", rb, nil, n)
    im = ccall("w_array_memmove_f64", ib, nil, n)
    [re, im]

  -> .ifft(re_in, im_in)
    n = re_in.size()
    if FFT.is_pow2(n) == false
      raise "FFT: length must be a power of 2 (got " + n.to_s() + ")"
    if n >= 16
      fast = ccall("w_array_memmove_f64", re_in, im_in, -3)
      if fast != nil
        return fast
    rb = f64[n]
    ib = f64[n]
    if n >= 4 && type(re_in[0]) == "Float" && type(im_in[0]) == "Float"
      ccall("w_array_memmove_f64", re_in, rb, n)
      ccall("w_array_memmove_f64", im_in, ib, n)
    else
      i = 0 ## i64
      while i < n
        rb[i] = re_in[i]
        ib[i] = im_in[i]
        i = i + 1
    fft_radix2_kernel(rb, ib, n, 1)
    re = ccall("w_array_memmove_f64", rb, nil, n)
    im = ccall("w_array_memmove_f64", ib, nil, n)
    [re, im]

  -> .rfft(x)
    n = x.size()
    if FFT.is_pow2(n) == false
      raise "FFT: length must be a power of 2 (got " + n.to_s() + ")"
    rb = f64[n]
    ib = f64[n]
    i = 0 ## i64
    while i < n
      rb[i] = x[i]
      ib[i] = ~0.0
      i = i + 1
    fft_radix2_kernel(rb, ib, n, 0)
    re = Array.new(n)
    im = Array.new(n)
    i = 0 ## i64
    while i < n
      re[i] = rb[i]
      im[i] = ib[i]
      i = i + 1
    [re, im]

  # Magnitude spectrum |X[k]|.
  -> .abs(re, im)
    n = re.size()
    out = Array.new(n)
    i = 0 ## i64
    while i < n
      r = re[i]
      m = im[i]
      out[i] = Math.sqrt(r * r + m * m)
      i = i + 1
    out

  # 2-D FFT: row-major flat re/im of length rows*cols (both powers of 2).
  -> .fft2(re_in, im_in, rows, cols)
    if FFT.is_pow2(cols) == false
      raise "FFT: length must be a power of 2 (got " + cols.to_s() + ")"
    if FFT.is_pow2(rows) == false
      raise "FFT: length must be a power of 2 (got " + rows.to_s() + ")"
    n = rows * cols
    rb = f64[n]
    ib = f64[n]
    i = 0 ## i64
    while i < n
      rb[i] = re_in[i]
      ib[i] = im_in[i]
      i = i + 1
    row_re = f64[cols]
    row_im = f64[cols]
    r = 0 ## i64
    while r < rows
      base = (r * cols) ## i64
      c = 0 ## i64
      while c < cols
        row_re[c] = rb[base + c]
        row_im[c] = ib[base + c]
        c = c + 1
      fft_radix2_kernel(row_re, row_im, cols, 0)
      c = 0 ## i64
      while c < cols
        rb[base + c] = row_re[c]
        ib[base + c] = row_im[c]
        c = c + 1
      r = r + 1
    col_re = f64[rows]
    col_im = f64[rows]
    c = 0 ## i64
    while c < cols
      r = 0 ## i64
      while r < rows
        idx = (r * cols + c) ## i64
        col_re[r] = rb[idx]
        col_im[r] = ib[idx]
        r = r + 1
      fft_radix2_kernel(col_re, col_im, rows, 0)
      r = 0 ## i64
      while r < rows
        idx = (r * cols + c) ## i64
        rb[idx] = col_re[r]
        ib[idx] = col_im[r]
        r = r + 1
      c = c + 1
    re = Array.new(n)
    im = Array.new(n)
    i = 0 ## i64
    while i < n
      re[i] = rb[i]
      im[i] = ib[i]
      i = i + 1
    [re, im]

-> fft_radix2_kernel(re, im, n, inv) (f64[] f64[] i64 i64) i64
  j = 0 ## i64
  i = 0 ## i64
  while i < n
    if i < j
      tr = re[i]
      re[i] = re[j]
      re[j] = tr
      ti = im[i]
      im[i] = im[j]
      im[j] = ti
    m = (n >> 1) ## i64
    while m >= 1 && j >= m
      j = (j - m) ## i64
      m = (m >> 1) ## i64
    j = (j + m) ## i64
    i = i + 1
  if n >= 4
    i0 = 0 ## i64
    if inv == 0
      while i0 < n
        r0 = re[i0]
        m0 = im[i0]
        r1 = re[i0 + 1]
        m1 = im[i0 + 1]
        r2 = re[i0 + 2]
        m2 = im[i0 + 2]
        r3 = re[i0 + 3]
        m3 = im[i0 + 3]
        t0r = r0 + r1
        t0i = m0 + m1
        t1r = r0 - r1
        t1i = m0 - m1
        t2r = r2 + r3
        t2i = m2 + m3
        t3r = r2 - r3
        t3i = m2 - m3
        re[i0] = t0r + t2r
        im[i0] = t0i + t2i
        re[i0 + 1] = t1r + t3i
        im[i0 + 1] = t1i - t3r
        re[i0 + 2] = t0r - t2r
        im[i0 + 2] = t0i - t2i
        re[i0 + 3] = t1r - t3i
        im[i0 + 3] = t1i + t3r
        i0 = i0 + 4
    else
      while i0 < n
        r0 = re[i0]
        m0 = im[i0]
        r1 = re[i0 + 1]
        m1 = im[i0 + 1]
        r2 = re[i0 + 2]
        m2 = im[i0 + 2]
        r3 = re[i0 + 3]
        m3 = im[i0 + 3]
        t0r = r0 + r1
        t0i = m0 + m1
        t1r = r0 - r1
        t1i = m0 - m1
        t2r = r2 + r3
        t2i = m2 + m3
        t3r = r2 - r3
        t3i = m2 - m3
        re[i0] = t0r + t2r
        im[i0] = t0i + t2i
        re[i0 + 1] = t1r - t3i
        im[i0 + 1] = t1i + t3r
        re[i0 + 2] = t0r - t2r
        im[i0 + 2] = t0i - t2i
        re[i0 + 3] = t1r + t3i
        im[i0 + 3] = t1i - t3r
        i0 = i0 + 4
  elsif n == 2
    u_re = re[0]
    u_im = im[0]
    v_re = re[1]
    v_im = im[1]
    re[0] = u_re + v_re
    im[0] = u_im + v_im
    re[1] = u_re - v_re
    im[1] = u_im - v_im
  if n >= 8
    tw_re = f64[n >> 1]
    tw_im = f64[n >> 1]
    len = 8 ## i64
    while len <= n
      half = (len >> 1) ## i64
      ang = (~0.0 - ~6.283185307179586 / (len + ~0.0)) ## f64
      if inv != 0
        ang = (~0.0 - ang) ## f64
      wlen_re = Math.cos(ang) ## f64
      wlen_im = Math.sin(ang) ## f64
      wr = ~1.0
      wi = ~0.0
      j = 0 ## i64
      while j < half
        tw_re[j] = wr
        tw_im[j] = wi
        nwr = wr * wlen_re - wi * wlen_im
        wi = wr * wlen_im + wi * wlen_re
        wr = nwr
        j = j + 1
      i0 = 0 ## i64
      while i0 < n
        j = 0 ## i64
        while j < half
          wr = tw_re[j]
          wi = tw_im[j]
          idx = (i0 + j) ## i64
          idx_h = (idx + half) ## i64
          u_re = re[idx]
          u_im = im[idx]
          r_h = re[idx_h]
          i_h = im[idx_h]
          v_re = r_h * wr - i_h * wi
          v_im = r_h * wi + i_h * wr
          re[idx] = u_re + v_re
          im[idx] = u_im + v_im
          re[idx_h] = u_re - v_re
          im[idx_h] = u_im - v_im
          j = j + 1
        i0 = (i0 + len) ## i64
      len = (len << 1) ## i64
  if inv != 0
    inv_n = (~1.0 / (n + ~0.0)) ## f64
    i = 0 ## i64
    while i < n
      re[i] = re[i] * inv_n
      im[i] = im[i] * inv_n
      i = i + 1
  0
