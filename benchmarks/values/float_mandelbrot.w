t0 = clock

total = 0

dxdy = ~3.0 / ~2000.0

0...2000 ->
  ci = ~-1.5 + py * dxdy

  0...2000 ->
    cr = ~-2.0 + px * dxdy
    zr = ~0.0
    zi = ~0.0

    iter = 0
    while iter < 50
      if zr * zr + zi * zi > ~4.0
        break
      new_zr = zr * zr - zi * zi + cr
      zi = ~2.0 * zr * zi + ci
      zr = new_zr
      iter = iter + 1

    total = total + iter

t1 = clock

<< total
<< "elapsed: [t1 - t0]s"
