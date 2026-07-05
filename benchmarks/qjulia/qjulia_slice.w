# Quaternion Julia Set slice renderer — escape-time visualization.
# Renders the 2D slice (qx, qy, qz=0, qw=0) of the 4D Julia set for
# parameter c. Each pixel iterates q ← q² + c and colors by the
# iteration index at which |q|² > 4 (escape time).
#
# This is the classic Julia rendering — what every fractal program
# from 1990 onward does. Beautiful, fast, no distance estimation.

width = ARGV[0].to_i
height = ARGV[1].to_i

# Julia constant — "spiky cauliflower" with rich boundary detail.
cw = ~-0.45
cx = ~-0.45
cy = ~-0.18
cz = ~-0.27

max_iters = 32
escape_sq = ~4.0

# View bounds in quaternion (qx, qy) plane.
xmin = ~-1.4
xmax = ~1.4
ymin = ~-1.4
ymax = ~1.4

w_f = width * ~1.0
h_f = height * ~1.0
xrange = xmax - xmin
yrange = ymax - ymin

# Emit PPM header on ONE line each by chaining strings.
header_line = "P3 " + width.to_s + " " + height.to_s + " 255"
<< header_line

# Render rows. Each pixel printed as "R G B" on its own line.
y = 0
while y < height
  x = 0
  while x < width
    # Map pixel (x, y) → quaternion start (qx, qy, 0, 0).
    qx = xmin + (x * ~1.0 / w_f) * xrange
    qy = ymax - (y * ~1.0 / h_f) * yrange
    qz = ~0.0
    qw = ~0.0

    iter = 0
    mag_sq = qw * qw + qx * qx + qy * qy + qz * qz

    while iter < max_iters && mag_sq < escape_sq
      # q ← q² + c via closed-form quaternion square:
      #   (w + xi + yj + zk)² = (w²−x²−y²−z², 2wx, 2wy, 2wz)
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

    # Color by iteration count: deep red at boundary, fading to black inside.
    if iter == max_iters
      # Inside the set: black.
      pixel = "0 0 0"
    else
      # Outside the set: shade by escape time.
      t = iter * ~1.0 / max_iters
      r = (~255.0 * t).to_i
      g = (~64.0 + ~191.0 * t * t).to_i
      b = (~255.0 - ~200.0 * t).to_i
      if r > 255
        r = 255
      if g > 255
        g = 255
      if b > 255
        b = 255
      if b < 0
        b = 0
      pixel = r.to_s + " " + g.to_s + " " + b.to_s

    << pixel
    x = x + 1
  y = y + 1
