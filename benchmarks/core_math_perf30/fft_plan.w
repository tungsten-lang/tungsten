use core/fft

# Repeated transforms of the same shape are the workload an FFT plan should
# serve: all shape-dependent permutation and twiddle work is invariant.
n = 1024
re = []
im = []
original = []
i = 0
while i < n
  value = Math.sin(~0.013 * (i + ~0.0)) + Math.cos(~0.007 * (i + ~0.0))
  re.push(value)
  im.push(~0.0)
  original.push(value)
  i += 1

# Warm the shape cache outside the timed region.
FFT.fft_inplace(re, im, false)
FFT.fft_inplace(re, im, true)

rounds = 600
t0 = ccall("__w_clock_ms")
round = 0
while round < rounds
  FFT.fft_inplace(re, im, false)
  FFT.fft_inplace(re, im, true)
  round += 1
t1 = ccall("__w_clock_ms")

max_error = ~0.0
checksum = ~0.0
i = 0
while i < n
  error = (re[i] - original[i]).abs
  max_error = error if error > max_error
  checksum += re[i] * ((i % 17) + ~1.0)
  i += 1
raise "FFT round-trip mismatch" if max_error > ~0.00000001

<< "checksum=" + checksum.to_s()
<< "max_error=" + max_error.to_s()
<< "elapsed_ms=" + (t1 - t0).to_s()
