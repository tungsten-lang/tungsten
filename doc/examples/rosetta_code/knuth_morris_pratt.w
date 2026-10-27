# Knuth-Morris-Pratt string search

-> kmp_table(w)
  chars = w.chars
  m = chars.size
  t = [-1]
  pos = 1
  cnd = 0
  while pos < m
    if chars[pos] == chars[cnd]
      t.push(t[cnd])
    else
      t.push(cnd)
      while cnd >= 0 && chars[pos] != chars[cnd]
        cnd = t[cnd]
    pos += 1
    cnd += 1
  t.push(cnd)
  t

-> kmp_search(s, w)
  sc = s.chars
  wc = w.chars
  t = kmp_table(w)
  matches = []
  j = 0
  k = 0
  while j < sc.size
    if wc[k] == sc[j]
      j += 1
      k += 1
      if k == wc.size
        matches.push(j - k)
        k = t[k]
    else
      k = t[k]
      if k < 0
        j += 1
        k += 1
  matches

<< kmp_search("GCATCGCAGAGAGTATACAGTACG", "GCAGAGAG")
<< kmp_search("ABABDABACDABABCABAB", "ABABCABAB")
<< kmp_search("banananobano", "na")

## expect stdout
## [5]
## [10]
## [2, 4]
