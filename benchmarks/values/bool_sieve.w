t0 = clock()

n = 1000000
is_prime = bool[n + 1]

is_prime[0] = false
is_prime[1] = false

i = 2
while i <= n
  is_prime[i] = true
  i = i + 1


i = 2
while i * i <= n
  if is_prime[i]
    j = i * i
    while j <= n
      is_prime[j] = false
      j = j + i
  i = i + 1

count = 0
k = 0
while k <= n
  if is_prime[k]
    count = count + 1
  k = k + 1

t1 = clock()
<< count
<< "elapsed: " + (t1 - t0).to_s() + "s"
