# Sparkline in unicode

-> sparkline(nums)
  bars = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
  lo = nums[0]
  hi = nums[0]
  i = 1
  while i < nums.size
    if nums[i] < lo
      lo = nums[i]
    if nums[i] > hi
      hi = nums[i]
    i += 1
  span = hi - lo
  out = ""
  i = 0
  while i < nums.size
    idx = 0
    if span > 0
      idx = ((nums[i] - lo) * 7) / span
    out += bars[idx]
    i += 1
  out

<< sparkline([1, 2, 3, 4, 5, 6, 7, 8, 7, 6, 5, 4, 3, 2, 1])
<< sparkline([3, 1, 5, 2, 7, 4, 9, 6])

## expect stdout
## ▁▂▃▄▅▆▇█▇▆▅▄▃▂▁
## ▂▁▄▁▆▃█▅
