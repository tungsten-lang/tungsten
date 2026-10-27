# Hamming distance and Hamming weight

-> popcount(n)
  count = 0
  while n > 0
    count += n & 1
    n = n >> 1
  count

-> hamming_distance_str(a, b)
  ca = a.chars
  cb = b.chars
  dist = 0
  i = 0
  while i < ca.size
    if ca[i] != cb[i]
      dist += 1
    i += 1
  dist

<< popcount(0)
<< popcount(42)
<< popcount(255)
<< hamming_distance_str("karolin", "kathrin")
<< hamming_distance_str("1011101", "1001001")

## expect stdout
## 0
## 3
## 8
## 3
## 2
