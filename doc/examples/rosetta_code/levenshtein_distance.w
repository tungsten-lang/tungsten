# Levenshtein distance

-> min3(a, b, c)
  m = a
  if b < m
    m = b
  if c < m
    m = c
  m

-> levenshtein(s, t)
  sc = s.chars
  tc = t.chars
  m = sc.size
  n = tc.size
  v0 = []
  j = 0
  while j <= n
    v0.push(j)
    j += 1
  i = 0
  while i < m
    v1 = [i + 1]
    j = 0
    while j < n
      cost = 1
      if sc[i] == tc[j]
        cost = 0
      v1.push(min3(v1[j] + 1, v0[j + 1] + 1, v0[j] + cost))
      j += 1
    v0 = v1
    i += 1
  v0[n]

<< levenshtein("kitten", "sitting")
<< levenshtein("rosettacode", "raisethysword")
<< levenshtein("saturday", "sunday")

## expect stdout
## 3
## 8
## 3
