# Gravitational n-body: 5 bodies (Sun + 4 gas giants), 500,000 timesteps.
# The body state lives in a raw f64[35]; `advance` types its array parameter
# via the trailing param-type-list `(f64[] f64)` so `b[i]` stays a raw load,
# and every intermediate is `## f64` — no boxing in the hot pairwise loop.
-> advance(b, dt) (f64[] f64)
  i = 0 ## i64
  while i < 5
    j = i + 1 ## i64
    while j < 5
      oi = i * 7
      oj = j * 7
      dx = (b[oi] - b[oj]) ## f64
      dy = (b[oi + 1] - b[oj + 1]) ## f64
      dz = (b[oi + 2] - b[oj + 2]) ## f64
      dist = (dx * dx + dy * dy + dz * dz).sqrt ## f64
      mag = (dt / (dist * dist * dist)) ## f64
      mi = b[oi + 6] ## f64
      mj = b[oj + 6] ## f64
      b[oi + 3] = b[oi + 3] - dx * mj * mag
      b[oi + 4] = b[oi + 4] - dy * mj * mag
      b[oi + 5] = b[oi + 5] - dz * mj * mag
      b[oj + 3] = b[oj + 3] + dx * mi * mag
      b[oj + 4] = b[oj + 4] + dy * mi * mag
      b[oj + 5] = b[oj + 5] + dz * mi * mag
      j = j + 1
    i = i + 1
  i = 0 ## i64
  while i < 5
    o = i * 7
    b[o] = b[o] + dt * b[o + 3]
    b[o + 1] = b[o + 1] + dt * b[o + 4]
    b[o + 2] = b[o + 2] + dt * b[o + 5]
    i = i + 1

t0 = clock
dpy = ~365.24
sm = ~4.0 * ~3.141592653589793 * ~3.141592653589793
b = f64[35]
b[6] = sm
b[7] = ~4.84143144246472090
b[8] = ~-1.16032004402742839
b[9] = ~-0.103622044471123109
b[10] = ~1.66007664274403694e-03 * dpy
b[11] = ~7.69901118419740425e-03 * dpy
b[12] = ~-6.90460016972063023e-05 * dpy
b[13] = ~9.54791938424326609e-04 * sm
b[14] = ~8.34336671824457987
b[15] = ~4.12479856412430479
b[16] = ~-0.403523417114321381
b[17] = ~-2.76742510726862411e-03 * dpy
b[18] = ~4.99852801234917238e-03 * dpy
b[19] = ~2.30417297573763929e-05 * dpy
b[20] = ~2.85885980666130812e-04 * sm
b[21] = ~12.8943695621391310
b[22] = ~-15.1111514016986312
b[23] = ~-0.223307578892655734
b[24] = ~2.96460137564761618e-03 * dpy
b[25] = ~2.37847173959480950e-03 * dpy
b[26] = ~-2.96589568540237556e-05 * dpy
b[27] = ~4.36624404335156298e-05 * sm
b[28] = ~15.3796971148509165
b[29] = ~-25.9193146099879641
b[30] = ~0.179258772950371181
b[31] = ~2.68067772490389322e-03 * dpy
b[32] = ~1.62824170038242295e-03 * dpy
b[33] = ~-9.51592254519715870e-05 * dpy
b[34] = ~5.15138902046611451e-05 * sm
px = ~0.0
py = ~0.0
pz = ~0.0
i = 0 ## i64
while i < 5
  o = i * 7
  px = px + b[o + 3] * b[o + 6]
  py = py + b[o + 4] * b[o + 6]
  pz = pz + b[o + 5] * b[o + 6]
  i = i + 1
b[3] = ~0.0 - px / sm
b[4] = ~0.0 - py / sm
b[5] = ~0.0 - pz / sm
dt = ~0.01
s = 0 ## i64
while s < 500000
  advance(b, dt)
  s = s + 1
e = ~0.0
i = 0 ## i64
while i < 5
  o = i * 7
  e = e + ~0.5 * b[o + 6] * (b[o + 3] * b[o + 3] + b[o + 4] * b[o + 4] + b[o + 5] * b[o + 5])
  j = i + 1 ## i64
  while j < 5
    oj = j * 7
    dx = (b[o] - b[oj]) ## f64
    dy = (b[o + 1] - b[oj + 1]) ## f64
    dz = (b[o + 2] - b[oj + 2]) ## f64
    dist = (dx * dx + dy * dy + dz * dz).sqrt ## f64
    e = e - b[o + 6] * b[oj + 6] / dist
    j = j + 1
  i = i + 1
t1 = clock
<< e
<< "elapsed: [t1 - t0]s"
