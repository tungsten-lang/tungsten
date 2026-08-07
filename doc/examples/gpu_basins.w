# GPU basin-of-attraction sweep — each grid cell is one GPU thread
# integrating the damped double-well Duffing flow (ẋ = v,
# v̇ = −δ·v + x − x³; attractors at (±1, 0)) and labeling itself by the
# well it falls into. The CPU twin is Dynamics.basins; this example
# runs BOTH on the same grid and reports their agreement.
#
#   bin/tungsten -o /tmp/gpu_basins doc/examples/gpu_basins.w && /tmp/gpu_basins

use core/metal

## i32[]: labels
## i32[]: iparams
## f32[]: fparams
@gpu fn basin_cells(labels, iparams, fparams)
  i = gpu.thread_position_in_grid.x ## i32
  nx = iparams[0] ## i32
  ny = iparams[1] ## i32
  steps = iparams[2] ## i32
  total = nx * ny ## i32
  if i < total
    ix = i % nx ## i32
    iy = i / nx ## i32
    x_lo = fparams[0] ## f32
    x_hi = fparams[1] ## f32
    y_lo = fparams[2] ## f32
    y_hi = fparams[3] ## f32
    dt = fparams[4] ## f32
    delta = fparams[5] ## f32
    x = x_lo + (x_hi - x_lo) * ix / (nx - 1) ## f32
    v = y_lo + (y_hi - y_lo) * iy / (ny - 1) ## f32
    s = 0 ## i32
    while s < steps
      k1x = v
      k1v = x - x * x * x - delta * v
      x2 = x + 0.5 * dt * k1x
      v2 = v + 0.5 * dt * k1v
      k2x = v2
      k2v = x2 - x2 * x2 * x2 - delta * v2
      x3 = x + 0.5 * dt * k2x
      v3 = v + 0.5 * dt * k2v
      k3x = v3
      k3v = x3 - x3 * x3 * x3 - delta * v3
      x4 = x + dt * k3x
      v4 = v + dt * k3v
      k4x = v4
      k4v = x4 - x4 * x4 * x4 - delta * v4
      x = x + dt * (k1x + 2.0 * k2x + 2.0 * k3x + k4x) / 6.0
      v = v + dt * (k1v + 2.0 * k2v + 2.0 * k3v + k4v) / 6.0
      s = s + 1
    lab = 0 ## i32
    if x > 0.0
      lab = 1
    labels[i] = lab

nx = 16
ny = 16
steps = 5000
dt = ~0.01
delta = ~0.5

msl = read_file("doc/examples/gpu_basins.metal")
device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "basin_cells")

total = nx * ny
labels_buf = metal_buffer(device, total * 4)
iparams = metal_buffer(device, 12)
fparams = metal_buffer(device, 24)
metal_buffer_write_i32(iparams, 0, nx)
metal_buffer_write_i32(iparams, 1, ny)
metal_buffer_write_i32(iparams, 2, steps)
metal_buffer_write_f32(fparams, 0, ~0.0 - ~2.0)
metal_buffer_write_f32(fparams, 1, ~2.0)
metal_buffer_write_f32(fparams, 2, ~0.0 - ~2.0)
metal_buffer_write_f32(fparams, 3, ~2.0)
metal_buffer_write_f32(fparams, 4, ~0.01)
metal_buffer_write_f32(fparams, 5, ~0.5)

queue = metal_queue(device)
metal_dispatch_n(queue, pipeline, [labels_buf, iparams, fparams], total)

# CPU twin on the same grid: damped double-well via Duffing with γ = 0.
well = Duffing.new(delta, ~0.0 - ~1.0, ~1.0, ~0.0, ~1.0)
cpu = Dynamics.basins(well, ~0.0 - ~2.0, ~2.0, ~0.0 - ~2.0, ~2.0, nx, ny, ~50.0, ~0.01, [[~0.0 - ~1.0, ~0.0], [~1.0, ~0.0]], ~0.5)

agree = 0
gpu_ones = 0
iy = 0
while iy < ny
  ix = 0
  while ix < nx
    g = metal_buffer_read_i32(labels_buf, iy * nx + ix)
    if g == 1
      gpu_ones = gpu_ones + 1
    if g == cpu[iy][ix]
      agree = agree + 1
    ix = ix + 1
  iy = iy + 1

<< "cells: " + total.to_s
<< "gpu well+1 cells: " + gpu_ones.to_s
<< "cpu/gpu agreement: " + agree.to_s + "/" + total.to_s
if agree * 100 >= total * 95
  << "gpu basins ok"
else
  << "gpu basins DISAGREE"
  exit 1
