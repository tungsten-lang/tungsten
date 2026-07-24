import time

t0 = time.perf_counter()

total = 0
for py in range(2000):
    ci = -1.5 + py * 3.0 / 2000.0
    for px in range(2000):
        cr = -2.0 + px * 3.0 / 2000.0
        zr = 0.0
        zi = 0.0
        iter = 0
        while iter < 50:
            if zr * zr + zi * zi > 4.0:
                break
            new_zr = zr * zr - zi * zi + cr
            zi = 2.0 * zr * zi + ci
            zr = new_zr
            iter += 1
        total += iter

t1 = time.perf_counter()
print(total)
print(f"elapsed: {t1 - t0:.3f}s")
