# Water collected between towers

-> trap_water(heights)
  n = heights.size
  if n < 3
    return 0
  left_max = []
  right_max = []
  i = 0
  while i < n
    left_max.push(0)
    right_max.push(0)
    i += 1
  left_max[0] = heights[0]
  i = 1
  while i < n
    if heights[i] > left_max[i - 1]
      left_max[i] = heights[i]
    else
      left_max[i] = left_max[i - 1]
    i += 1
  right_max[n - 1] = heights[n - 1]
  i = n - 2
  while i >= 0
    if heights[i] > right_max[i + 1]
      right_max[i] = heights[i]
    else
      right_max[i] = right_max[i + 1]
    i -= 1
  water = 0
  i = 0
  while i < n
    bound = left_max[i]
    if right_max[i] < bound
      bound = right_max[i]
    if bound > heights[i]
      water += bound - heights[i]
    i += 1
  water

<< trap_water([1, 5, 3, 7, 2])
<< trap_water([5, 3, 7, 2, 6, 4, 5, 9, 1, 2])
<< trap_water([2, 6, 3, 5, 2, 8, 1, 4, 2, 2, 5, 3, 5, 7, 4, 1])

## expect stdout
## 2
## 14
## 35
