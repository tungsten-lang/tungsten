# Filter

nums = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
evens = []
nums.each -> (x)
  if x % 2 == 0
    evens.push(x)

<< evens

## expect stdout
## [2, 4, 6, 8, 10]
