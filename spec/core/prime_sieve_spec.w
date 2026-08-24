# PrimeSieve / Int.nth_prime / Int.primes / Int.prime_pi / fused `/prime? :count`
# — known values (A006988, A006880) through the compiled two-tier mod-30 sieve.
# Every check runs in well under a second; the ladder rungs are exercised on
# both the exact-hit and the sieve-forward paths.

# Compare through to_s so arrays and ints both work (and no string literal
# has to carry `[...]`, which Tungsten strings would interpolate).
-> check(name, got, want)
  if got.to_s == want.to_s
    << "PASS " + name
  else
    << "FAIL " + name + ": got " + got.to_s + " want " + want.to_s

check("nth 1..10", [1,2,3,4,5,6,7,8,9,10].map(-> (k) Int.nth_prime(k)), [2, 3, 5, 7, 11, 13, 17, 19, 23, 29])
check("nth 150 (between rungs)", Int.nth_prime(150), 863)
check("nth 1000 (rung hit)", Int.nth_prime(1000), 7919)
check("nth 12345", Int.nth_prime(12345), 132241)
check("nth 1e6", Int.nth_prime(1000000), 15485863)
check("nth 1e7", Int.nth_prime(10000000), 179424673)
check("pi 10..1e7", [10, 100, 1000, 10000, 100000, 1000000, 10000000].map(-> (k) Int.prime_pi(k)), [4, 25, 168, 1229, 9592, 78498, 664579])
check("pi 1e8", Int.prime_pi(100000000), 5761455)
check("fused 2..100", (2..100) /prime? :count, 25)
check("fused 0..100", (0..100) /prime? :count, 25)
check("fused 1..100", (1..100) /prime? :count, 25)
check("fused 50..100", (50..100) /prime? :count, 10)
check("fused 2...100 exclusive", (2...100) /prime? :count, 25)
check("fused 2..1e6", (2..1000000) /prime? :count, 78498)
check("count 1e9..2e9", PrimeSieve.count(1000000000, 2000000000), 47374753)
check("count above 2^48", PrimeSieve.count(300000000000000, 300000000000600), 15)
p = Int.primes(10)
check("primes(10)", p, [2, 3, 5, 7, 11, 13, 17, 19, 23, 29])
q = Int.primes(1000)
check("primes(1000) size", q.size, 1000)
check("primes(1000)[999]", q[999], 7919)
r = Int.primes(2000000)
check("primes(2e6)[-1]", r[1999999], 32452843)
check("primes(0)", Int.primes(0).size, 0)
check("primes(3)", Int.primes(3), [2, 3, 5])
check("nth(0)", Int.nth_prime(0), 0)
check("pi(1)", Int.prime_pi(1), 0)
