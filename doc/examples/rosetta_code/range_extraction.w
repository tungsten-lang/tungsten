# Range extraction

-> range_extract(nums)
  if nums.empty?
    return ""
  parts = []
  i = 0
  n = nums.size
  while i < n
    j = i
    while j + 1 < n && nums[j + 1] == nums[j] + 1
      j += 1
    if j - i >= 2
      parts.push("[nums[i]]-[nums[j]]")
    elsif j - i == 1
      parts.push(nums[i].to_s)
      parts.push(nums[j].to_s)
    else
      parts.push(nums[i].to_s)
    i = j + 1
  parts.join(",")

nums = [0, 1, 2, 4, 6, 7, 8, 11, 12, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 27, 28, 29, 30, 31, 32, 33, 35, 36, 37, 38, 39]
<< range_extract(nums)

## expect stdout
## 0-2,4,6-8,11,12,14-25,27-33,35-39
