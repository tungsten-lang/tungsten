t0 = Time.instant

total = 0_i64
py = 0
while py < 2000
  ci = -1.5 + py * 3.0 / 2000.0
  px = 0
  while px < 2000
    cr = -2.0 + px * 3.0 / 2000.0
    zr = 0.0
    zi = 0.0
    iter = 0_i64
    while iter < 50
      break if zr * zr + zi * zi > 4.0
      new_zr = zr * zr - zi * zi + cr
      zi = 2.0 * zr * zi + ci
      zr = new_zr
      iter += 1
    end
    total += iter
    px += 1
  end
  py += 1
end

t1 = Time.instant
elapsed = (t1 - t0).total_seconds
puts total
puts "elapsed: #{"%.3f" % elapsed}s"
