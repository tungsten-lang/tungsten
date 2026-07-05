# Int#prime? wheel benchmark — π(500 000 000) via a mod-12 candidate wheel.
#
# Counts primes by generating ONLY the candidates coprime to 12 — the residues
# 12m + {-1, 1, 5, 7} — and testing each with the stdlib `prime_12k?`, a fast
# variant of `prime?` that skips the redundant ÷2/÷3 screen (the wheel already
# guarantees coprimality to 6). The four offsets are unrolled so no per-m array
# is allocated. 2 and 3 (not coprime to 12) are seeded into the count.
#
# π(5e8) = 26 355 867. ~7.1s — about 15% under the idiomatic every-number form
# `(2..N)/prime?:count` (~8.4s). The candidate wheel only trims cheap
# rejections; the per-survivor test (prime-table trial division ≤ 1e7,
# single-base Miller-Rabin above) dominates and is identical across every form.
#
# The mod-30 wheel (`prime_30k?`, 8 offsets per 30m: 1,7,11,13,17,19,23,29)
# TIES this — dropping the multiples of 5 saves nothing, since prime_12k?
# rejects them in one extra modulo. Bigger wheels buy nothing here; the lever is
# the inner test, not candidate generation. That inner test is now ~4× faster
# than the original: the u64 Miller-Rabin tier uses division-free Montgomery
# arithmetic with a Forišek–Jančina single hashed base for n < 2^32 (see
# runtime.c w_prime_fj32 / w_prime_mont_mr); the original 3-base %-reduction run
# was ~28s. A segmented sieve, which replaces per-number testing with cheap array
# marks, remains the next order-of-magnitude lever.
#
# N = 5e8 is chosen so 12m+7 ≤ N at the final m (no bound guard needed); change
# N and the last wheel turn may overshoot — add `&& cand <= N` guards then.
#
# Time it: bin/tungsten -o /tmp/pw prime_wheel.w && time /tmp/pw

-> count_primes
  count = 2
  (0..500000000 / 12) -> (m)
    base = 12 * m
    count++ if (base - 1).prime_12k?
    count++ if (base + 1).prime_12k?
    count++ if (base + 5).prime_12k?
    count++ if (base + 7).prime_12k?
  count

<< count_primes
