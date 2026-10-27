# Flatten a list

-> flatten(arr)
  result = []
  i = 0
  while i < arr.size
    item = arr[i]
    if item.is_a?(Array)
      sub = flatten(item)
      j = 0
      while j < sub.size
        result.push(sub[j])
        j += 1
    else
      result.push(item)
    i += 1
  result

<< flatten([[1], 2, [[3, 4], 5], [[[]]], [[[6]]], 7, 8, []])

## expect stdout
## [1, 2, 3, 4, 5, 6, 7, 8]
