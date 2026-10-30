# 100 prisoners

# Deterministic LCG shuffle to test the optimal cycle-following strategy
# vs sequential drawer choice on a fixed set of trials.
-> make_drawers(n, seed)
  drawers = []
  i = 0
  while i < n
    drawers.push(i)
    i += 1
  s = seed
  i = n - 1
  while i > 0
    s = (s * 1103515245 + 12345) % 2147483648
    j = s % (i + 1)
    tmp = drawers[i]
    drawers[i] = drawers[j]
    drawers[j] = tmp
    i -= 1
  drawers

-> optimal_trial(drawers, n, max_picks)
  prisoner = 0
  while prisoner < n
    curr = prisoner
    picks = 0
    found = false
    while picks < max_picks
      if drawers[curr] == prisoner
        found = true
        break
      curr = drawers[curr]
      picks += 1
    if !found
      return false
    prisoner += 1
  true

trials = 200
wins = 0
t = 1
while t <= trials
  drawers = make_drawers(100, t * 7919)
  if optimal_trial(drawers, 100, 50)
    wins += 1
  t += 1

<< "Optimal strategy wins: [wins] / [trials]"

## expect stdout
## Optimal strategy wins: 43 / 200
