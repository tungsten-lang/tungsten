# GPU isoperiodic diagram — one thread per (γ, ω) cell of the forced
# Duffing oscillator (ẋ = v, v̇ = γ·cos(ωt) − δ·v + x − x³), strobing at
# the forcing period and labeling the cell with its attractor period in
# cycles (0 = aperiodic at this resolution). CPU twin:
# Dynamics.isoperiodic_map; this example runs both and reports agreement.
#
#   bin/tungsten -o /tmp/gpu_iso doc/examples/gpu_isoperiodic.w && /tmp/gpu_iso

use core/metal

## i32[]: labels
## i32[]: iparams
## f32[]: fparams
@gpu fn iso_cells(labels, iparams, fparams)
  i = gpu.thread_position_in_grid.x ## i32
  na = iparams[0] ## i32
  nb = iparams[1] ## i32
  transient = iparams[2] ## i32
  max_p = iparams[3] ## i32
  steps = iparams[4] ## i32
  total = na * nb ## i32
  if i < total
    ia = i % na ## i32
    ib = i / na ## i32
    g = fparams[0] + (fparams[1] - fparams[0]) * ia / (na - 1) ## f32
    w = fparams[2] + (fparams[3] - fparams[2]) * ib / (nb - 1) ## f32
    delta = fparams[4] ## f32
    tol = fparams[5] ## f32
    tf = 6.2831853 / w ## f32
    dt = tf / steps ## f32
    x = 0.1 ## f32
    v = 0.1 ## f32
    t = 0.0 ## f32
    cycles = transient + max_p ## i32
    ref_x = 0.0 ## f32
    ref_v = 0.0 ## f32
    label = 0 ## i32
    c = 0 ## i32
    while c < cycles
      s = 0 ## i32
      while s < steps
        k1x = v
        k1v = g * cos(w * t) - delta * v + x - x * x * x
        t2 = t + 0.5 * dt
        x2 = x + 0.5 * dt * k1x
        v2 = v + 0.5 * dt * k1v
        k2x = v2
        k2v = g * cos(w * t2) - delta * v2 + x2 - x2 * x2 * x2
        x3 = x + 0.5 * dt * k2x
        v3 = v + 0.5 * dt * k2v
        k3x = v3
        k3v = g * cos(w * t2) - delta * v3 + x3 - x3 * x3 * x3
        t4 = t + dt
        x4 = x + dt * k3x
        v4 = v + dt * k3v
        k4x = v4
        k4v = g * cos(w * t4) - delta * v4 + x4 - x4 * x4 * x4
        x = x + dt * (k1x + 2.0 * k2x + 2.0 * k3x + k4x) / 6.0
        v = v + dt * (k1v + 2.0 * k2v + 2.0 * k3v + k4v) / 6.0
        t = t + dt
        s = s + 1
      if c == transient - 1
        ref_x = x
        ref_v = v
      if c >= transient
        if label == 0
          dx = x - ref_x
          dv = v - ref_v
          if sqrt(dx * dx + dv * dv) < tol
            label = c - transient + 1
      c = c + 1
    labels[i] = label

na = 12
nb = 3
transient = 150
max_p = 8
steps = 200

msl = read_file("doc/examples/gpu_isoperiodic.metal")
device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "iso_cells")

total = na * nb
lab_buf = metal_buffer(device, total * 4)
iparams = metal_buffer(device, 20)
fparams = metal_buffer(device, 24)
metal_buffer_write_i32(iparams, 0, na)
metal_buffer_write_i32(iparams, 1, nb)
metal_buffer_write_i32(iparams, 2, transient)
metal_buffer_write_i32(iparams, 3, max_p)
metal_buffer_write_i32(iparams, 4, steps)
metal_buffer_write_f32(fparams, 0, ~0.2)
metal_buffer_write_f32(fparams, 1, ~0.65)
metal_buffer_write_f32(fparams, 2, ~1.0)
metal_buffer_write_f32(fparams, 3, ~1.4)
metal_buffer_write_f32(fparams, 4, ~0.3)
metal_buffer_write_f32(fparams, 5, ~0.05)

queue = metal_queue(device)
metal_dispatch_n(queue, pipeline, [lab_buf, iparams, fparams], total)

tau = ~6.283185307179586
mk = -> (g, w) Duffing.new(~0.3, ~0.0 - ~1.0, ~1.0, g, w)
pf = -> (g, w) tau / w
cpu = Dynamics.isoperiodic_map(mk, ~0.2, ~0.65, na, ~1.0, ~1.4, nb, [~0.1, ~0.1], pf, transient, max_p, ~0.05, ~0.01)

agree = 0
period_cells = 0
ib = 0
while ib < nb
  ia = 0
  while ia < na
    gv = metal_buffer_read_i32(lab_buf, ib * na + ia)
    if gv == cpu[ib][ia]
      agree = agree + 1
    if gv >= 1
      period_cells = period_cells + 1
    ia = ia + 1
  ib = ib + 1

<< "cells: " + total.to_s
<< "gpu periodic cells: " + period_cells.to_s
<< "cpu/gpu agreement: " + agree.to_s + "/" + total.to_s
if agree * 100 >= total * 75 && period_cells >= 5
  << "gpu isoperiodic ok"
else
  << "gpu isoperiodic DISAGREE"
  exit 1
