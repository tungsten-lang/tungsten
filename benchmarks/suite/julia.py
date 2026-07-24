import time

t0 = time.perf_counter()

c_re = -0.7
c_im = 0.27015
total = 0
for py in range(2000):
    zi_init = -1.5 + py * 3.0 / 2000.0
    for px in range(2000):
        zr = -1.5 + px * 3.0 / 2000.0
        zi = zi_init
        iter = 0
        while iter < 50:
            if zr * zr + zi * zi > 4.0:
                break
            new_zr = zr * zr - zi * zi + c_re
            zi = 2.0 * zr * zi + c_im
            zr = new_zr
            iter += 1
        total += iter

t1 = time.perf_counter()
print(total)
print(f"elapsed: {t1 - t0:.3f}s")
