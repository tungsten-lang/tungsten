import time

t0 = time.perf_counter()

num_words = 1000
num_iter = 5_000_000

words = [f"word{i}" for i in range(num_words)]

freq = {}
seed = 42
for _ in range(num_iter):
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    word = words[seed % num_words]
    freq[word] = freq.get(word, 0) + 1

max_freq = max(freq.values())

t1 = time.perf_counter()
print(max_freq)
print(f"elapsed: {t1 - t0:.3f}s")
