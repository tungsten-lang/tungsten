# Quaternion Julia Set raymarched renderer — pure-CPU Tungsten reference.
#
# Renders a 3D slice of the 4D Julia set for parameter c, using the
# Hubbard-Douady distance estimate over quaternion iteration:
#
#   q ← q² + c                              (one Hamilton square + add)
#   dq ← 2·q·dq                             (chain rule on dq/dz₀)
#   if |q|² > escape²: surface found
#   distance ≈ ½ · |q| · log|q| / |dq|
#
# This is the canonical algorithm from Hart/Sandin/Kauffman's 1989
# paper "Ray Tracing Deterministic 3-D Fractals" — the same math
# Inigo Quilez and every modern raymarcher uses.
#
# Output: PPM ASCII format (head -1 = magic, head -2 = dims).
#
# Compile & run:
#   bin/tungsten -o /tmp/qjulia benchmarks/qjulia/qjulia_cpu.w
#   /tmp/qjulia 256 256 > /tmp/qjulia.ppm
#
# View: any image viewer that supports PPM (Preview.app, GIMP, etc.)
# Convert: ImageMagick `magick /tmp/qjulia.ppm qjulia.png`

width = ARGV[0].to_i
height = ARGV[1].to_i

# Julia constant c — classic parameter set producing the "spiky cauliflower"
# Quilez calls this his favorite (it's also the cover image of Hart 89).
cw = ~-0.450
cx = ~-0.447
cy = ~-0.181
cz = ~-0.276

# Iteration / quality knobs.
julia_iters = 8      # quaternion-iteration depth (more = sharper boundary)
max_steps = 64       # raymarch steps per pixel
escape_sq = ~16.0    # bailout |q|² threshold
hit_eps = ~0.001     # raymarch termination distance

# Camera setup — orbiting eye looking at the origin.
eye_x = ~2.5
eye_y = ~1.5
eye_z = ~2.0
look_x = ~0.0
look_y = ~0.0
look_z = ~0.0
fov_scale = ~1.0

# --- Quaternion helpers -----------------------------------------------
# Each q stored as 4 f64 scalars in the order (w, x, y, z).
# We pass these around as 4-tuples to dodge the no-typed-arrays-in-
# arbitrary-positions limitation. Slow but legible.

# qsq: Hamilton square. Closed form from core/numeric/hypercomplex/quaternion.w.
#   (w + xi + yj + zk)² = (w²-x²-y²-z², 2wx, 2wy, 2wz)

# qmul: Hamilton product of (a, b). Both stored as 4-tuples returned by
# the previous quaternion-arithmetic step.

# qdot: |q|² without sqrt.

-> render_pixel(px, py, w_param, x_param, y_param, z_param)
  # Normalized device coords in [-1, 1].
  u = (~2.0 * px - w_param) / w_param * fov_scale
  v = (y_param - ~2.0 * py) / y_param * fov_scale * ~0.5625  # 16:9 aspect

  # Ray origin = eye; direction = normalized(view - eye + u·right + v·up).
  # Simplified camera: assume forward = (look - eye), right = (1, 0, 0),
  # up = (0, 1, 0), and don't bother with proper basis construction.
  rdx = u
  rdy = v
  rdz = ~-1.0  # forward

  # Normalize direction.
  rdlen_sq = rdx * rdx + rdy * rdy + rdz * rdz
  inv_len = ~1.0 / sqrt_approx(rdlen_sq)
  rdx = rdx * inv_len
  rdy = rdy * inv_len
  rdz = rdz * inv_len

  # Raymarch.
  px_acc = eye_x
  py_acc = eye_y
  pz_acc = eye_z

  step = 0
  hit = ~0.0   # 0 = miss, n > 0 = iteration count at hit (for shading)

  while step < max_steps
    # Distance estimate at (px_acc, py_acc, pz_acc) — interpret as a
    # quaternion with w = 0 (the 3D slice).
    qw = ~0.0
    qx = px_acc
    qy = py_acc
    qz = pz_acc

    # Derivative q' starts as 1 + 0i + 0j + 0k.
    dw = ~1.0
    dx = ~0.0
    dy = ~0.0
    dz = ~0.0

    iter = 0
    mag_sq = qw * qw + qx * qx + qy * qy + qz * qz

    while iter < julia_iters && mag_sq < escape_sq
      # dq = 2 · q · dq  (one Hamilton product, scaled)
      # Hamilton product of q · dq (scalar-first):
      new_dw = qw * dw - qx * dx - qy * dy - qz * dz
      new_dx = qw * dx + qx * dw + qy * dz - qz * dy
      new_dy = qw * dy - qx * dz + qy * dw + qz * dx
      new_dz = qw * dz + qx * dy - qy * dx + qz * dw
      dw = ~2.0 * new_dw
      dx = ~2.0 * new_dx
      dy = ~2.0 * new_dy
      dz = ~2.0 * new_dz

      # q = q² + c  (using the closed-form quaternion square)
      qw2 = qw * qw - qx * qx - qy * qy - qz * qz
      qx2 = ~2.0 * qw * qx
      qy2 = ~2.0 * qw * qy
      qz2 = ~2.0 * qw * qz
      qw = qw2 + cw
      qx = qx2 + cx
      qy = qy2 + cy
      qz = qz2 + cz

      mag_sq = qw * qw + qx * qx + qy * qy + qz * qz
      iter = iter + 1

    # Hubbard-Douady distance estimate.
    mag = sqrt_approx(mag_sq)
    dmag = sqrt_approx(dw * dw + dx * dx + dy * dy + dz * dz)
    if dmag > ~0.0
      dist = ~0.5 * mag * log_approx(mag) / dmag
    else
      dist = ~1.0

    if dist < hit_eps
      hit = iter * ~1.0
      step = max_steps  # break out
    else
      px_acc = px_acc + rdx * dist
      py_acc = py_acc + rdy * dist
      pz_acc = pz_acc + rdz * dist
      step = step + 1

  hit

-> sqrt_approx(x)
  # Newton 4-step approximation; good enough for visualization.
  if x <= ~0.0
    return ~0.0
  y = x
  i = 0
  while i < 8
    y = ~0.5 * (y + x / y)
    i = i + 1
  y

-> log_approx(x)
  # log via change-of-base from sqrt iteration; cheap but inaccurate.
  # For the distance estimate we just need a monotone proxy.
  if x <= ~0.0
    return ~-100.0
  # log(x) ≈ 2 * (x-1)/(x+1) when x is near 1; near boundary that's true.
  t = (x - ~1.0) / (x + ~1.0)
  ~2.0 * t * (~1.0 + t * t / ~3.0 + t * t * t * t / ~5.0)

-> shade(iter_count)
  # Map iteration count → RGB (false-color palette).
  if iter_count <= ~0.5
    return [0, 0, 0]
  t = iter_count / ~8.0
  r = (~255.0 * t).to_i
  g = (~128.0 * t * (~2.0 - t)).to_i
  b = (~255.0 * (~1.0 - t)).to_i
  if r > 255
    r = 255
  if g > 255
    g = 255
  if b > 255
    b = 255
  [r, g, b]

# --- Main: render and emit PPM -----------------------------------------

<< "P3"
<< width
<< " "
<< height
<< "\n"
<< "255"
<< "\n"

w_f = width * ~1.0
h_f = height * ~1.0

y = 0
while y < height
  x = 0
  while x < width
    iter_count = render_pixel(x * ~1.0, y * ~1.0, w_f, ~1.0, h_f, ~1.0)
    rgb = shade(iter_count)
    << rgb[0]
    << " "
    << rgb[1]
    << " "
    << rgb[2]
    << "\n"
    x = x + 1
  y = y + 1
