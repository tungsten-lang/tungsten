# Binary digits

-> to_binary(n)
  if n == 0
    return "0"
  out = ""
  while n > 0
    if n % 2 == 1
      out = "1" + out
    else
      out = "0" + out
    n /= 2
  out

nums = [5, 50, 9000]
nums.each -> (n)
  << to_binary(n)

## expect stdout
## 101
## 110010
## 10001100101000
