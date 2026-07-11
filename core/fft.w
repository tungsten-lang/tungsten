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
    # bit-reverse permutation
    j = 0
    i = 0
    while i < n
      if i < j
        tr = re[i]
        re[i] = re[j]
        re[j] = tr
        ti = im[i]
        im[i] = im[j]
        im[j] = ti
      m = n / 2
      while m >= 1 && j >= m
        j = j - m
        m = m / 2
      j = j + m
      i = i + 1
    # butterflies
    len = 2
    while len <= n
      half = len / 2
      ang = ~0.0 - ~6.283185307179586 / (len + ~0.0)
      if inverse
        ang = ~0.0 - ang
      wlen_re = Math.cos(ang)
      wlen_im = Math.sin(ang)
      i0 = 0
      while i0 < n
        wr = ~1.0
        wi = ~0.0
        j = 0
        while j < half
          u_re = re[i0 + j]
          u_im = im[i0 + j]
          v_re = re[i0 + j + half] * wr - im[i0 + j + half] * wi
          v_im = re[i0 + j + half] * wi + im[i0 + j + half] * wr
          re[i0 + j] = u_re + v_re
          im[i0 + j] = u_im + v_im
          re[i0 + j + half] = u_re - v_re
          im[i0 + j + half] = u_im - v_im
          nwr = wr * wlen_re - wi * wlen_im
          wi = wr * wlen_im + wi * wlen_re
          wr = nwr
          j = j + 1
        i0 = i0 + len
      len = len * 2
    if inverse
      inv_n = ~1.0 / (n + ~0.0)
      i = 0
      while i < n
        re[i] = re[i] * inv_n
        im[i] = im[i] * inv_n
        i = i + 1
    [re, im]

  -> .fft(re_in, im_in)
    re = []
    im = []
    i = 0
    while i < re_in.size()
      re = re.push(re_in[i] + ~0.0)
      im = im.push(im_in[i] + ~0.0)
      i = i + 1
    FFT.fft_inplace(re, im, false)

  -> .ifft(re_in, im_in)
    re = []
    im = []
    i = 0
    while i < re_in.size()
      re = re.push(re_in[i] + ~0.0)
      im = im.push(im_in[i] + ~0.0)
      i = i + 1
    FFT.fft_inplace(re, im, true)

  -> .rfft(x)
    re = []
    im = []
    i = 0
    while i < x.size()
      re = re.push(x[i] + ~0.0)
      im = im.push(~0.0)
      i = i + 1
    FFT.fft_inplace(re, im, false)

  # Magnitude spectrum |X[k]|.
  -> .abs(re, im)
    out = []
    i = 0
    while i < re.size()
      out = out.push(Math.sqrt(re[i] * re[i] + im[i] * im[i]))
      i = i + 1
    out

  # 2-D FFT: row-major flat re/im of length rows*cols (both powers of 2).
  -> .fft2(re_in, im_in, rows, cols)
    n = rows * cols
    re = []
    im = []
    i = 0
    while i < n
      re = re.push(re_in[i] + ~0.0)
      im = im.push(im_in[i] + ~0.0)
      i = i + 1
    # rows
    r = 0
    while r < rows
      row_re = []
      row_im = []
      c = 0
      while c < cols
        row_re = row_re.push(re[r * cols + c])
        row_im = row_im.push(im[r * cols + c])
        c = c + 1
      FFT.fft_inplace(row_re, row_im, false)
      c = 0
      while c < cols
        re[r * cols + c] = row_re[c]
        im[r * cols + c] = row_im[c]
        c = c + 1
      r = r + 1
    # cols
    c = 0
    while c < cols
      col_re = []
      col_im = []
      r = 0
      while r < rows
        col_re = col_re.push(re[r * cols + c])
        col_im = col_im.push(im[r * cols + c])
        r = r + 1
      FFT.fft_inplace(col_re, col_im, false)
      r = 0
      while r < rows
        re[r * cols + c] = col_re[r]
        im[r * cols + c] = col_im[r]
        r = r + 1
      c = c + 1
    [re, im]
