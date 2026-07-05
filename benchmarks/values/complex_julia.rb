t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

c_re = -0.7
c_im = 0.27015
total = 0
py = 0
while py < 2000
  zi_init = -1.5 + py * 3.0 / 2000.0
  px = 0
  while px < 2000
    zr = -1.5 + px * 3.0 / 2000.0
    zi = zi_init
    iter = 0
    while iter < 50
      break if zr * zr + zi * zi > 4.0
      new_zr = zr * zr - zi * zi + c_re
      zi = 2.0 * zr * zi + c_im
      zr = new_zr
      iter += 1
    end
    total += iter
    px += 1
  end
  py += 1
end

t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts total
puts "elapsed: #{'%.3f' % (t1 - t0)}s"
