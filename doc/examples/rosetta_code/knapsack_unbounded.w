# Knapsack problem/Unbounded

# Panacea (val 3000, wt 3, vol 25), Ichors (val 1800, wt 2, vol 15), Gold (val 2500, wt 20, vol 2)
# Weight scaled by 10 (max 250), Volume scaled by 1000 (max 250)
-> solve_unbounded()
  best_val = 0
  best_counts = [0, 0, 0]
  p = 0
  while p * 3 <= 250 && p * 25 <= 250
    i = 0
    while p * 3 + i * 2 <= 250 && p * 25 + i * 15 <= 250
      g = 0
      while p * 3 + i * 2 + g * 20 <= 250 && p * 25 + i * 15 + g * 2 <= 250
        val = p * 3000 + i * 1800 + g * 2500
        if val > best_val
          best_val = val
          best_counts = [p, i, g]
        g += 1
      i += 1
    p += 1
  << "Max value: [best_val]"
  << "Panacea=[best_counts[0]], Ichor=[best_counts[1]], Gold=[best_counts[2]]"

solve_unbounded()

## expect stdout
## Max value: 54500
## Panacea=0, Ichor=15, Gold=11
