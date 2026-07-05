# Use c with all 4 components non-zero so the iteration mixes through
# the full quaternion space and the slice reveals genuine 4D structure.

width = ARGV[0].to_i
height = ARGV[1].to_i

# Canonical "Norman-Banderup" quaternion Julia parameter — all 4
# components non-zero, produces rich dendritic structure.
cw = ~-0.291
cx = ~-0.399
cy = ~0.339
cz = ~0.437

# Sample the slice at qz = 0.5, qw = 0 — off the degenerate plane.
slice_qz = ~0.5
slice_qw = ~0.0

max_iters = 32
escape_sq = ~4.0
xmin = ~-1.6
xmax = ~1.6
ymin = ~-1.2
ymax = ~1.2

w_f = width * ~1.0
h_f = height * ~1.0
xrange = xmax - xmin
yrange = ymax - ymin

<< "P3 " + width.to_s + " " + height.to_s + " 255"

y = 0
while y < height
  x = 0
  while x < width
    qx = xmin + (x * ~1.0 / w_f) * xrange
    qy = ymax - (y * ~1.0 / h_f) * yrange
    qz = slice_qz
    qw = slice_qw
    iter = 0
    mag_sq = qw * qw + qx * qx + qy * qy + qz * qz
    while iter < max_iters && mag_sq < escape_sq
      nw = qw * qw - qx * qx - qy * qy - qz * qz
      nx = ~2.0 * qw * qx
      ny = ~2.0 * qw * qy
      nz = ~2.0 * qw * qz
      qw = nw + cw
      qx = nx + cx
      qy = ny + cy
      qz = nz + cz
      mag_sq = qw * qw + qx * qx + qy * qy + qz * qz
      iter = iter + 1
    if iter == max_iters
      pixel = "0 0 0"
    else
      t = iter * ~1.0 / max_iters
      r = (~255.0 * t * t).to_i
      g = (~80.0 + ~175.0 * t).to_i
      b = (~200.0 * (~1.0 - t * t)).to_i
      if r > 255
        r = 255
      if g > 255
        g = 255
      if b > 255
        b = 255
      pixel = r.to_s + " " + g.to_s + " " + b.to_s
    << pixel
    x = x + 1
  y = y + 1
