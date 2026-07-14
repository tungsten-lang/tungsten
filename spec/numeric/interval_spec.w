# Interval arithmetic sign-partition regression.
#
# Multiplication has nine endpoint-sign combinations. Eight need only two
# extremal products; the mixed/mixed case needs all four corners.

-> check_interval(name, got, want_lo, want_hi)
  if got.lo == want_lo && got.hi == want_hi
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want [" + want_lo.to_s() + ", " + want_hi.to_s() + "]"

pp = Interval.new(~2.0, ~5.0)
nn = Interval.new(~-5.0, ~-2.0)
mm = Interval.new(~-3.0, ~5.0)

check_interval("mul.pos.pos", pp * Interval.new(~3.0, ~11.0), ~6.0, ~55.0)
check_interval("mul.pos.neg", pp * Interval.new(~-11.0, ~-3.0), ~-55.0, ~-6.0)
check_interval("mul.pos.mix", pp * Interval.new(~-7.0, ~11.0), ~-35.0, ~55.0)
check_interval("mul.neg.pos", nn * Interval.new(~3.0, ~11.0), ~-55.0, ~-6.0)
check_interval("mul.neg.neg", nn * Interval.new(~-11.0, ~-3.0), ~6.0, ~55.0)
check_interval("mul.neg.mix", nn * Interval.new(~-7.0, ~11.0), ~-55.0, ~35.0)
check_interval("mul.mix.pos", mm * Interval.new(~3.0, ~11.0), ~-33.0, ~55.0)
check_interval("mul.mix.neg", mm * Interval.new(~-11.0, ~-3.0), ~-55.0, ~33.0)
check_interval("mul.mix.mix", mm * Interval.new(~-7.0, ~11.0), ~-35.0, ~55.0)
check_interval("mul.zero.edge", Interval.new(~0.0, ~5.0) * Interval.new(~-7.0, ~11.0), ~-35.0, ~55.0)
unbounded = Interval.new(~0.0, Math.exp(~1000.0))
zero = Interval.point(~0.0)
check_interval("mul.zero.unbounded", zero * unbounded, ~0.0, ~0.0)
check_interval("mul.unbounded.zero", unbounded * zero, ~0.0, ~0.0)
check_interval("div.pos.pos", pp / Interval.new(~2.0, ~4.0), ~0.5, ~2.5)
check_interval("div.neg.neg", nn / Interval.new(~-4.0, ~-2.0), ~0.5, ~2.5)
