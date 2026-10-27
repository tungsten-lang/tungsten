# Pythagorean triples

-> gcd(a, b)
  while b != 0
    t = a % b
    a = b
    b = t
  a

-> count_triples(max_perim)
  total = 0
  primitive = 0
  m = 2
  while 2 * m * (m + 1) <= max_perim
    n = 1
    while n < m
      if (m - n) % 2 == 1 && gcd(m, n) == 1
        perim = 2 * m * (m + n)
        if perim <= max_perim
          primitive += 1
          total += max_perim / perim
      n += 1
    m += 1
  [total, primitive]

limits = [100, 1000, 10000]
limits.each -> (lim)
  res = count_triples(lim)
  << "Up to [lim]: [res[0]] triples, [res[1]] primitive"

## expect stdout
## Up to 100: 17 triples, 7 primitive
## Up to 1000: 325 triples, 70 primitive
## Up to 10000: 4858 triples, 703 primitive
