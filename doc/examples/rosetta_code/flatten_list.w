# Flatten a list

-> flatten(arr)
  result = []
  arr.each { |item|
    if item.is_a?(Array)
      flatten(item).each { |x| result.push(x) }
    else
      result.push(item)
  }
  result

puts flatten([[1], 2, [[3, 4], 5], [[[]]], [[[6]]], 7, 8, []])

## expect skip currently unsupported in this runtime
