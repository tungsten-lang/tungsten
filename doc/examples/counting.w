n = 0

while n < 50_000_000_000
  n = n + 1

  if n % 5_000_000_000 == 0
    << n

## expect skip long-running example
