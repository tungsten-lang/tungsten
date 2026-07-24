# Mandelbrot escape-time over a 2000x2000 grid, 50 iterations max.
# `~` literals keep the arithmetic in raw f64; counters typed `## i64`.
t0 = clock
total = 0 ## i64
d = ~3.0 / ~2000.0
py = 0 ## i64
while py < 2000
  ci = ~-1.5 + py * d
  px = 0 ## i64
  while px < 2000
    cr = ~-2.0 + px * d
    zr = ~0.0
    zi = ~0.0
    iter = 0 ## i64
    while iter < 50
      if zr * zr + zi * zi > ~4.0
        break
      nzr = zr * zr - zi * zi + cr
      zi = ~2.0 * zr * zi + ci
      zr = nzr
      iter = iter + 1
    total = total + iter
    px = px + 1
  py = py + 1
t1 = clock
<< total
<< "elapsed: [t1 - t0]s"
