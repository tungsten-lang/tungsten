# GPU Lyapunov parameter map — one thread per (a, b) cell computing the
# largest Lyapunov exponent of the Hénon map by the tangent method.
# The CPU twin is Dynamics.lyapunov_map; this example runs both on the
# same grid and reports agreement over the non-escaping cells.
#
#   bin/tungsten -o /tmp/gpu_lyap doc/examples/gpu_lyapunov_map.w && /tmp/gpu_lyap

use core/metal

## f32[]: lambdas
## i32[]: iparams
## f32[]: fparams
@gpu fn lyap_cells(lambdas, iparams, fparams)
  i = gpu.thread_position_in_grid.x ## i32
  na = iparams[0] ## i32
  nb = iparams[1] ## i32
  warm = iparams[2] ## i32
  iters = iparams[3] ## i32
  total = na * nb ## i32
  if i < total
    ia = i % na ## i32
    ib = i / na ## i32
    a = fparams[0] + (fparams[1] - fparams[0]) * ia / (na - 1) ## f32
    b = fparams[2] + (fparams[3] - fparams[2]) * ib / (nb - 1) ## f32
    x = 0.1 ## f32
    y = 0.1 ## f32
    s = 0 ## i32
    while s < warm
      x_next = 1.0 - a * x * x + y
      y = b * x
      x = x_next
      s = s + 1
    vx = 1.0 ## f32
    vy = 0.0 ## f32
    acc = 0.0 ## f32
    escaped = 0 ## i32
    k = 0 ## i32
    while k < iters
      wx = vy - 2.0 * a * x * vx
      wy = b * vx
      nv = sqrt(wx * wx + wy * wy)
      if nv > 0.0
        acc = acc + log(nv)
        vx = wx / nv
        vy = wy / nv
      x_next = 1.0 - a * x * x + y
      y = b * x
      x = x_next
      if x > 1000000.0
        escaped = 1
        k = iters
      if x < -1000000.0
        escaped = 1
        k = iters
      k = k + 1
    lam = acc / iters ## f32
    if escaped == 1
      lam = 99.0
    lambdas[i] = lam

na = 24
nb = 8
warm = 300
iters = 2000

msl = read_file("doc/examples/gpu_lyapunov_map.metal")
device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "lyap_cells")

total = na * nb
lam_buf = metal_buffer(device, total * 4)
iparams = metal_buffer(device, 16)
fparams = metal_buffer(device, 16)
metal_buffer_write_i32(iparams, 0, na)
metal_buffer_write_i32(iparams, 1, nb)
metal_buffer_write_i32(iparams, 2, warm)
metal_buffer_write_i32(iparams, 3, iters)
metal_buffer_write_f32(fparams, 0, ~1.0)
metal_buffer_write_f32(fparams, 1, ~1.4)
metal_buffer_write_f32(fparams, 2, ~0.2)
metal_buffer_write_f32(fparams, 3, ~0.3)

queue = metal_queue(device)
metal_dispatch_n(queue, pipeline, [lam_buf, iparams, fparams], total)

cpu = Dynamics.lyapunov_map(-> (a, b) Henon.new(a, b), ~1.0, ~1.4, na, ~0.2, ~0.3, nb, [~0.1, ~0.1], warm, iters)

agree = 0
finite = 0
chaotic_gpu = 0
ib = 0
while ib < nb
  ia = 0
  while ia < na
    g = metal_buffer_read_f32(lam_buf, ib * na + ia)
    c = cpu[ib][ia]
    cf = c
    if cf < ~0.0
      cf = ~0.0 - cf
    if cf < ~10.0 && g < ~10.0
      finite = finite + 1
      d = g - c
      if d < ~0.0
        d = ~0.0 - d
      if d < ~0.05
        agree = agree + 1
    if g > ~0.0 && g < ~10.0
      chaotic_gpu = chaotic_gpu + 1
    ia = ia + 1
  ib = ib + 1

classic = cpu[nb - 1][na - 1]
<< "cells: " + total.to_s + " finite: " + finite.to_s
<< "cpu lambda at (1.4, 0.3): " + classic.to_s
<< "gpu chaotic cells: " + chaotic_gpu.to_s
<< "agreement (|d| < 0.05): " + agree.to_s + "/" + finite.to_s
if agree * 100 >= finite * 90 && classic > ~0.3
  << "gpu lyapunov map ok"
else
  << "gpu lyapunov map DISAGREE"
  exit 1
