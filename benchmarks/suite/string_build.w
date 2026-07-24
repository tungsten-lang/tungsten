# String-building throughput: append a 26-char chunk 400,000 times into a
# growable StringBuffer (amortized-O(1) appends) — 10,400,000 chars.
t0 = clock
n = 400000 ## i64
sb = StringBuffer(64)
i = 0 ## i64
while i < n
  sb << "abcdefghijklmnopqrstuvwxyz"
  i = i + 1
s = sb.to_s
t1 = clock
<< s.size()
<< "elapsed: [t1 - t0]s"
