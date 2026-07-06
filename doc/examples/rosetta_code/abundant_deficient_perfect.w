# Abundant, deficient and perfect number classifications

-> sum_divisors(n)
  sum = 1
  i = 2

  while i * i <= n
    if n % i == 0
      sum += i
      if i != n / i
        sum += n / i
    i += 1
  sum

abundant = 0
deficient = 0
perfect = 0

(1..20000).each -> (n)
  s = sum_divisors(n)

  if s > n
    abundant += 1
  elsif s < n
    deficient += 1
  else
    perfect += 1

<< "Deficient: [deficient]"
<< "Abundant:  [abundant]"
<< "Perfect:   [perfect]"

## expect timeout 20
## expect stdout
## Deficient: 15042
## Abundant:  4953
## Perfect:   5
