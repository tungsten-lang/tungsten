# Babbage problem
# Find the smallest positive integer whose square ends in 269696

n = 1
while true
  sq = n * n
  if sq % 1000000 == 269696
    puts "[n] squared is [sq]"
    break
  n += 1

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten babbage_problem.w`
## expect stdout
## 25264 squared is 638269696
