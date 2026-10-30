# Babbage problem
# Find the smallest positive integer whose square ends in 269696

-> solve_babbage()
  n = 1
  while true
    sq = n * n
    if sq % 1000000 == 269696
      << "[n] squared is [sq]"
      return
    n += 1

solve_babbage()

## expect stdout
## 25264 squared is 638269696
