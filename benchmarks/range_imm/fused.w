# Fused-pipeline workload — ranges that never escape.
#
# The XOR term inside the added expression defeats the poly_sum closed
# form (non-polynomial), so this compiles to the fused counted loop while
# keeping the accumulator additive — the promotion walk only handles
# additive captured accumulators (TODO: `acc = acc ^ x` in a block emits
# non-dominating IR; see the bxor promotion gap). Steps 1-2 of the
# immediate-Range campaign must not move this number (fusion untouched).

fn mix(n)
  acc = 0
  (1..n).each -> (k)
    acc = acc + (k ^ 25)
  acc

<< mix(150000000)
