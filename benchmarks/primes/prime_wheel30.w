# Int#prime? wheel benchmark — π(500 000 000) via a mod-30 candidate wheel.
#
# Same idea as prime_wheel.w but a wider wheel: generates only the candidates
# coprime to 30 — the eight residues 30m + {1,7,11,13,17,19,23,29} — and tests
# each with `prime_30k?`, the fast variant of `prime?` that skips the ÷2/÷3/÷5
# screen the wheel has already guaranteed away. `base = 30 * m` is hoisted above
# the eight unrolled lines (one multiply per m, not eight). 2, 3, 5 (not coprime
# to 30) are seeded into the count.
#
# π(5e8) = 26 355 867. ~7.1s — essentially TIES the mod-12 wheel (prime_wheel.w,
# also ~7.1s) despite checking ~20% fewer candidates (8/30 vs 4/12). Dropping
# the multiples of 5 saves nothing because prime_12k? already rejects them in one
# extra modulo. Bigger wheels don't help: the cost is the per-survivor inner test
# (division-free prime-factor scan ≤ 1e6, single-base Miller-Rabin above), which is
# identical and shared across every form. That test is now ~4× faster than the
# original: division-free Montgomery arithmetic + a Forišek–Jančina single hashed
# base for n < 2^32 (was ~28s). A segmented sieve is the next lever.
#
# At the final m the +23/+29 offsets can exceed N, so those two carry a bound
# guard; the other six always fit at N = 5e8.
#
# Time it: bin/tungsten -o /tmp/pw30 prime_wheel30.w && time /tmp/pw30

-> count_primes
  count = 3
  (0..500000000 / 30) -> (m)
    base = 30 * m
    count++ if (base + 1).prime_30k?
    count++ if (base + 7).prime_30k?
    count++ if (base + 11).prime_30k?
    count++ if (base + 13).prime_30k?
    count++ if (base + 17).prime_30k?
    count++ if (base + 19).prime_30k?
    count++ if base + 23 <= 500000000 && (base + 23).prime_30k?
    count++ if base + 29 <= 500000000 && (base + 29).prime_30k?
  count

<< count_primes
