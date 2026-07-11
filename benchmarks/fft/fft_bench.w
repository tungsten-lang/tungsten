# FFT microbench — pure Tungsten radix-2.
# Compare wall time to NumPy via run.sh

use core/fft

n = 1024
re = []
im = []
i = 0
while i < n
  re = re.push(Math.sin(~0.01 * (i + ~0.0)))
  im = im.push(~0.0)
  i = i + 1

# warmup
re_w = []
im_w = []
i = 0
while i < n
  re_w = re_w.push(re[i])
  im_w = im_w.push(~0.0)
  i = i + 1
FFT.fft(re_w, im_w)

t0 = ccall("__w_clock_ms")
k = 0
iters = 10
while k < iters
  re2 = []
  im2 = []
  i = 0
  while i < n
    re2 = re2.push(re[i])
    im2 = im2.push(~0.0)
    i = i + 1
  FFT.fft(re2, im2)
  k = k + 1
t1 = ccall("__w_clock_ms")
ms = (t1 - t0 + ~0.0) / (iters + ~0.0)
<< "tungsten_fft n=" + n.to_s() + " avg_ms=" + ms.to_s()
