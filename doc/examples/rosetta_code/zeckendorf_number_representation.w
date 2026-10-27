# Zeckendorf number representation

-> zeckendorf(n)
  if n == 0
    return "0"
  fibs = [1, 2]
  while fibs[fibs.size - 1] <= n
    k = fibs.size
    fibs.push(fibs[k - 1] + fibs[k - 2])
  out = ""
  i = fibs.size - 2
  while i >= 0
    if n >= fibs[i]
      out += "1"
      n -= fibs[i]
    else
      out += "0"
    i -= 1
  out

(0..20).each -> (n)
  << "[n]: [zeckendorf(n)]"

## expect stdout
## 0: 0
## 1: 1
## 2: 10
## 3: 100
## 4: 101
## 5: 1000
## 6: 1001
## 7: 1010
## 8: 10000
## 9: 10001
## 10: 10010
## 11: 10100
## 12: 10101
## 13: 100000
## 14: 100001
## 15: 100010
## 16: 100100
## 17: 100101
## 18: 101000
## 19: 101001
## 20: 101010
