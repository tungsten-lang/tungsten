# Int#prime? benchmark — π(120 000 000).
#
# Same workload as primes.c / primes.rb / primes.go in this directory, but
# written the idiomatic Tungsten way: a fused map/reduce pipeline over the
# range. `(lo..hi)/prime?:count` maps the stdlib `prime?` predicate across the
# range and reduces by counting the matches — one fused loop, no intermediate
# array. `prime?` is the runtime intrinsic (tiered: small-prime screen, prime
# trial division, deterministic Miller-Rabin, Lucas-Lehmer for Mersennes).
#
# Equivalent spellings (interpreter / REPL): `(lo..hi).count(:prime?)` and the
# space-dot form `lo..hi .count(:prime?)`.
#
# Time it: `bin/tungsten -o /tmp/pm prime_method.w && time /tmp/pm`.

<< ((2..120000000)/prime?:count)
