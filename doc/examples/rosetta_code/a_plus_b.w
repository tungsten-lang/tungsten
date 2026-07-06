# A+B: Read two integers and print their sum

line = gets
nums = line.split(" ").map -> (s) s.to_i
<< nums[0] + nums[1]

## expect stdin
## 2 3
## expect stdout
## 5
