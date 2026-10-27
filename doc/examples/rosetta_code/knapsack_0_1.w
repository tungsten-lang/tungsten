# Knapsack problem/0-1

weights = [9, 13, 153, 50, 15, 68, 27, 39, 23, 52]
values  = [150, 35, 200, 160, 60, 45, 60, 40, 30, 10]
cap = 400
n = weights.size

dp = []
w = 0
while w <= cap
  dp.push(0)
  w += 1

i = 0
while i < n
  wt = weights[i]
  val = values[i]
  w = cap
  while w >= wt
    cand = dp[w - wt] + val
    if cand > dp[w]
      dp[w] = cand
    w -= 1
  i += 1

<< "Max value for capacity [cap]: [dp[cap]]"

## expect stdout
## Max value for capacity 400: 780
