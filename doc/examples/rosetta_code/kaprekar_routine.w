# Kaprekar's routine (6174)

-> kaprekar_step(n)
  digits = []
  i = 0
  while i < 4
    digits.push(n % 10)
    n /= 10
    i += 1
  # Sort ascending
  i = 1
  while i < 4
    key = digits[i]
    j = i - 1
    while j >= 0 && digits[j] > key
      digits[j + 1] = digits[j]
      j -= 1
    digits[j + 1] = key
    i += 1
  asc = digits[0] * 1000 + digits[1] * 100 + digits[2] * 10 + digits[3]
  desc = digits[3] * 1000 + digits[2] * 100 + digits[1] * 10 + digits[0]
  desc - asc

-> kaprekar_chain(start)
  chain = [start]
  curr = start
  while curr != 6174 && curr != 0
    curr = kaprekar_step(curr)
    chain.push(curr)
  chain

<< kaprekar_chain(3524)
<< kaprekar_chain(2111)

## expect stdout
## [3524, 3087, 8352, 6174]
## [2111, 999, 8991, 8082, 8532, 6174]
