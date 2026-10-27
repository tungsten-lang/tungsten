# Taxicab numbers

-> find_taxicab(max_base)
  a = 1
  while a <= max_base
    b = a + 1
    while b <= max_base
      c = a + 1
      while c <= max_base
        d = c + 1
        while d <= max_base
          s1 = a * a * a + b * b * b
          s2 = c * c * c + d * d * d
          if s1 == s2
            << "[s1] = [a]^3 + [b]^3 = [c]^3 + [d]^3"
          d += 1
        c += 1
      b += 1
    a += 1

find_taxicab(16)

## expect stdout
## 1729 = 1^3 + 12^3 = 9^3 + 10^3
## 4104 = 2^3 + 16^3 = 9^3 + 15^3
