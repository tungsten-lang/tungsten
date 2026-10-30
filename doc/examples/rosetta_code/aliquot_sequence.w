# Aliquot sequence classifications

-> proper_divisor_sum(n)
  if n < 2
    return 0
  sum = 1
  i = 2
  while i * i <= n
    if n % i == 0
      sum += i
      if i != n / i
        sum += n / i
    i += 1
  sum

-> classify_aliquot(k)
  seq = [k]
  curr = k
  step = 0
  while step < 16
    curr = proper_divisor_sum(curr)
    seq.push(curr)
    if curr == 0
      return "terminating: [seq]"
    if curr == k && seq.size == 2
      return "perfect: [seq]"
    if curr == k && seq.size == 3
      return "amicable: [seq]"
    if curr == k && seq.size > 3
      return "sociable: [seq]"
    if seq.slice(0, seq.size - 1).include?(curr)
      if seq[seq.size - 2] == curr
        return "aspiring: [seq]"
      return "cyclic: [seq]"
    step += 1
  "non-terminating: [seq]"

samples = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 28, 220]
samples.each -> (n)
  << "[n]: [classify_aliquot(n)]"

## expect stdout
## 1: terminating: [1, 0]
## 2: terminating: [2, 1, 0]
## 3: terminating: [3, 1, 0]
## 4: terminating: [4, 3, 1, 0]
## 5: terminating: [5, 1, 0]
## 6: perfect: [6, 6]
## 7: terminating: [7, 1, 0]
## 8: terminating: [8, 7, 1, 0]
## 9: terminating: [9, 4, 3, 1, 0]
## 10: terminating: [10, 8, 7, 1, 0]
## 11: terminating: [11, 1, 0]
## 12: terminating: [12, 16, 15, 9, 4, 3, 1, 0]
## 28: perfect: [28, 28]
## 220: amicable: [220, 284, 220]
