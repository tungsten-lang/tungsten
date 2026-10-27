# Josephus problem

-> josephus(n, k)
  survivor = 0
  i = 2
  while i <= n
    survivor = (survivor + k) % i
    i += 1
  survivor

<< "n=5, k=2: prisoner [josephus(5, 2)] survives"
<< "n=41, k=3: prisoner [josephus(41, 3)] survives"

## expect stdout
## n=5, k=2: prisoner 2 survives
## n=41, k=3: prisoner 30 survives
