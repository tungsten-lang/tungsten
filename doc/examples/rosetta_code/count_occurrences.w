# Count occurrences of a substring

-> count(s, sub)
  n = 0
  i = 0
  while i <= s.size - sub.size
    if s.slice(i, sub.size) == sub
      n += 1
    i += 1
  n

<< count("the three truths", "th")
<< count("ababababab", "abab")

## expect stdout
## 3
## 4
