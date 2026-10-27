# Power set

-> power_set(items)
  result = [[]]
  i = 0
  while i < items.size
    elem = items[i]
    cur_len = result.size
    j = 0
    while j < cur_len
      subset = []
      k = 0
      while k < result[j].size
        subset.push(result[j][k])
        k += 1
      subset.push(elem)
      result.push(subset)
      j += 1
    i += 1
  result

ps = power_set([1, 2, 3])
ps.each -> (s)
  << s

## expect stdout
## []
## [1]
## [2]
## [1, 2]
## [3]
## [1, 3]
## [2, 3]
## [1, 2, 3]
