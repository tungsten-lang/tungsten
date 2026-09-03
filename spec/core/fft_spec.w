# FFT — radix-2 Cooley–Tukey DFT on split real/imag lists (core/fft.w).
#
# Run:
#   bin/tungsten run --interpret spec/core/fft_spec.w
#   bin/tungsten -o /tmp/fft_spec spec/core/fft_spec.w && /tmp/fft_spec

use core/fft

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

-> near(a, b)
  d = a - b
  if d < ~0.0
    d = ~0.0 - d
  return d < ~1.0e-12

-> near_list(xs, ys)
  if xs.size != ys.size
    return false
  i = 0
  while i < xs.size
    if !near(xs[i], ys[i])
      return false
    i += 1
  return true

zeros4 = [~0.0, ~0.0, ~0.0, ~0.0]

# ---- is_pow2 ----
check("is_pow2 1", FFT.is_pow2(1))
check("is_pow2 2", FFT.is_pow2(2))
check("is_pow2 1024", FFT.is_pow2(1024))
check("is_pow2 3", !FFT.is_pow2(3))
check("is_pow2 6", !FFT.is_pow2(6))
check("is_pow2 0", !FFT.is_pow2(0))
check("is_pow2 negative", !FFT.is_pow2(-4))

# ---- fft ----
impulse = FFT.fft([~1.0, ~0.0, ~0.0, ~0.0], zeros4)
check("fft returns re/im pair", impulse.size == 2 && type(impulse) == "Array")
check("fft impulse re", near_list(impulse[0], [~1.0, ~1.0, ~1.0, ~1.0]))
check("fft impulse im", near_list(impulse[1], zeros4))
ones = FFT.fft([~1.0, ~1.0, ~1.0, ~1.0], zeros4)
check("fft constant re", near_list(ones[0], [~4.0, ~0.0, ~0.0, ~0.0]))
check("fft constant im", near_list(ones[1], zeros4))
ramp = FFT.fft([~1.0, ~2.0, ~3.0, ~4.0], zeros4)
check("fft ramp re", near_list(ramp[0], [~10.0, ~-2.0, ~-2.0, ~-2.0]))
check("fft ramp im", near_list(ramp[1], [~0.0, ~2.0, ~0.0, ~-2.0]))
sine = FFT.fft([~0.0, ~1.0, ~0.0, ~-1.0], zeros4)
check("fft sine re", near_list(sine[0], zeros4))
check("fft sine im", near_list(sine[1], [~0.0, ~-2.0, ~0.0, ~2.0]))
imag_in = FFT.fft(zeros4, [~1.0, ~0.0, ~0.0, ~0.0])
check("fft imaginary impulse", near_list(imag_in[0], zeros4) && near_list(imag_in[1], [~1.0, ~1.0, ~1.0, ~1.0]))
check("fft accepts ints", near_list(FFT.fft([1, 0], [0, 0])[0], [~1.0, ~1.0]))
check("fft length 1", near_list(FFT.fft([~7.0], [~0.0])[0], [~7.0]))
eight = FFT.fft([~1.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0], [~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0])
check("fft n=8 impulse is flat", near_list(eight[0], [~1.0, ~1.0, ~1.0, ~1.0, ~1.0, ~1.0, ~1.0, ~1.0]))

src_re = [~1.0, ~2.0, ~3.0, ~4.0]
src_im = [~0.0, ~0.0, ~0.0, ~0.0]
FFT.fft(src_re, src_im)
check("fft copies its inputs", src_re == [~1.0, ~2.0, ~3.0, ~4.0] && src_im == zeros4)

inplace_re = [~1.0, ~1.0]
inplace_im = [~0.0, ~0.0]
inplace = FFT.fft_inplace(inplace_re, inplace_im, false)
check("fft_inplace mutates", near_list(inplace_re, [~2.0, ~0.0]))
check("fft_inplace returns the same arrays", inplace[0] == inplace_re && inplace[1] == inplace_im)

# ---- ifft ----
back = FFT.ifft(ramp[0], ramp[1])
check("ifft round-trips re", near_list(back[0], [~1.0, ~2.0, ~3.0, ~4.0]))
check("ifft round-trips im", near_list(back[1], zeros4))
check("ifft normalizes by 1/n", near_list(FFT.ifft([~4.0, ~0.0, ~0.0, ~0.0], zeros4)[0], [~1.0, ~1.0, ~1.0, ~1.0]))
sine_back = FFT.ifft(sine[0], sine[1])
check("ifft round-trips sine", near_list(sine_back[0], [~0.0, ~1.0, ~0.0, ~-1.0]))

# ---- rfft ----
rf = FFT.rfft([~1.0, ~2.0, ~3.0, ~4.0])
check("rfft matches fft with zero im", near_list(rf[0], ramp[0]) && near_list(rf[1], ramp[1]))
check("rfft ints", near_list(FFT.rfft([1, 1])[0], [~2.0, ~0.0]))

# ---- abs ----
check("abs 3-4-5", FFT.abs([~3.0], [~4.0]) == [~5.0])
check("abs spectrum", near_list(FFT.abs(ramp[0], ramp[1]), [~10.0, Math.sqrt(~8.0), ~2.0, Math.sqrt(~8.0)]))
check("abs empty", FFT.abs([], []) == [])

# ---- fft2 ----
two_d = FFT.fft2([~1.0, ~2.0, ~3.0, ~4.0], zeros4, 2, 2)
check("fft2 re", near_list(two_d[0], [~10.0, ~-2.0, ~-4.0, ~0.0]))
check("fft2 im", near_list(two_d[1], zeros4))
row = FFT.fft2([~1.0, ~2.0, ~3.0, ~4.0], zeros4, 1, 4)
check("fft2 single row equals fft", near_list(row[0], ramp[0]) && near_list(row[1], ramp[1]))

# ---- errors ----
bad_len = false
msg = ""
begin
  FFT.fft([~1.0, ~1.0, ~1.0], [~0.0, ~0.0, ~0.0])
rescue error
  bad_len = true
  msg = error.to_s
check("fft rejects non power of 2", bad_len)
check("fft error names the length", msg.include?("power of 2") && msg.include?("3"))
empty_raises = false
begin
  FFT.fft([], [])
rescue error
  empty_raises = true
check("fft rejects empty", empty_raises)

<< "ALL PASS fft_spec ([passed.load()] checks)"
