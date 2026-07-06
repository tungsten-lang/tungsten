# Flatten a list

-> flatten(arr)
  result = []
  arr.each -> (item)
    if item.is_a?(Array)
      flatten(item).each -> (x) result.push(x)
    else
      result.push(item)
  result

<< flatten([[1], 2, [[3, 4], 5], [[[]]], [[[6]]], 7, 8, []])

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten flatten_list.w`
## expect stdout
## [1, 2, 3, 4, 5, 6, 7, 8]
