t0 = Time.instant

n = 1_000_000
is_prime = Array.new(n + 1, true)
is_prime[0] = false
is_prime[1] = false

i = 2
while i * i <= n
  if is_prime[i]
    j = i * i
    while j <= n
      is_prime[j] = false
      j += i
    end
  end
  i += 1
end

count = 0
k = 0
while k <= n
  count += 1 if is_prime[k]
  k += 1
end

t1 = Time.instant
elapsed = (t1 - t0).total_seconds
puts count
puts "elapsed: #{"%.3f" % elapsed}s"
