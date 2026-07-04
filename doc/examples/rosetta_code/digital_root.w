# Digital root

-> digital_root(n)
  persistence = 0
  while n >= 10
    sum = 0
    while n > 0
      sum += n % 10
      n = n / 10
    n = sum
    persistence += 1
  [n, persistence]

[627615, 39390, 588225, 393900588225].each { |n|
  result = digital_root(n)
  puts "[n]: root=[result[0]] persistence=[result[1]]"
}

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten digital_root.w`
## expect stdout
## 627615: root=9 persistence=2
## 39390: root=6 persistence=2
## 588225: root=3 persistence=2
## 393900588225: root=9 persistence=2
