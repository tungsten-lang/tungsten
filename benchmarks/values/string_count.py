import time

t0 = time.perf_counter()

base = "the quick brown fox jumps over the lazy dog "
text = base * 2500000

count = 0
pos = 0
needle = "fox"
needle_len = len(needle)
while pos <= len(text) - needle_len:
    idx = text.find(needle, pos)
    if idx == -1:
        break
    count += 1
    pos = idx + needle_len

t1 = time.perf_counter()
print(count)
print(f"elapsed: {t1 - t0:.3f}s")
