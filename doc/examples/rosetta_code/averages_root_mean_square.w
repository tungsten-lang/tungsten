# Averages/Root mean square

-> rms_squared(nums)
  sum_sq = 0
  i = 0
  while i < nums.size
    sum_sq += nums[i] * nums[i]
    i += 1
  sum_sq.to_f / nums.size

# For [1..10], sum of squares is 385, mean square is 38.5
<< rms_squared([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
<< rms_squared([3, 4])

## expect stdout
## 38.5
## 12.5
