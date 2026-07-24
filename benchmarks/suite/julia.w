t0 = clock()

c_re = ~-0.7
c_im = ~0.27015
total = 0
py = 0
while py < 2000
  zi_init = ~-1.5 + py * ~3.0 / ~2000.0
  px = 0
  while px < 2000
    zr = ~-1.5 + px * ~3.0 / ~2000.0
    zi = zi_init
    iter = 0
    while iter < 50
      if zr * zr + zi * zi > ~4.0
        break
      new_zr = zr * zr - zi * zi + c_re
      zi = ~2.0 * zr * zi + c_im
      zr = new_zr
      iter = iter + 1
    total = total + iter
    px = px + 1
  py = py + 1

t1 = clock()
<< total
<< "elapsed: " + (t1 - t0).to_s() + "s"
