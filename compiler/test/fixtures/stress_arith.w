-> step(n)
  n + 1

-> wrap(x)
  step(x)

result = 0
i = 0
while i < 5000000
  result = wrap(result)
  i += 1

<< result
