# Extreme-tail numerics, counter streams, and inspectable accuracy contracts.

use probability

-> numeric_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> numeric_close?(got, want, tolerance = ~1.0e-11)
  difference = got - want
  difference = ~0.0 - difference if difference < ~0.0
  scale = want
  scale = ~0.0 - scale if scale < ~0.0
  scale = ~1.0 if scale < ~1.0
  difference <= tolerance*scale

standard = Probability.normal
numeric_check("normal.log_survival.10",
  numeric_close?(standard.log_survival(~10.0),
                 ~-53.23128515051247, ~3.0e-14))
numeric_check("normal.log_survival.40",
  numeric_close?(standard.log_survival(~40.0),
                 ~-804.6084420137539, ~3.0e-14))
numeric_check("normal.log_cdf.minus_40",
  numeric_close?(standard.log_cdf(~-40.0),
                 standard.log_survival(~40.0), ~1.0e-15))
numeric_check("normal.linear_tail.underflow",
  standard.survival(~40.0) == ~0.0 &&
  !standard.log_survival(~40.0).infinite?)

upper_p = ~0.999999999999
upper_q = standard.quantile(upper_p)
numeric_check("normal.quantile.extreme.roundtrip",
  numeric_close?(standard.log_survival(upper_q),
                 Math.log1p(~0.0 - upper_p), ~2.0e-8))

contract = Probability.numerical_contract(:normal_tail)
numeric_check("contract.inspectable",
  contract.arithmetic == "IEEE-754 binary64" && !contract.certified? &&
  contract.limitations.include?("not interval-certified"))

# Cross-engine golden vector for the Random123 Philox2x32-10 round function.
counter = Probability.counter_rng(12345, 7)
numeric_check("counter.algorithm",
  counter.algorithm == "philox2x32-10" && counter.splittable? &&
  !counter.cryptographic?)
numeric_check("counter.vector.0", counter.next_u32 == 3792864528)
numeric_check("counter.vector.1", counter.next_u32 == 1332351031)
numeric_check("counter.vector.2", counter.next_u32 == 3309948775)
numeric_check("counter.vector.3", counter.next_u32 == 3256021323)

left = Probability.counter_rng(99, 3)
right = Probability.counter_rng(99, 3)
other = Probability.counter_rng(99, 4)
same = true
different = false
i = 0
while i < 100
  a = left.next_u32
  same = false if a != right.next_u32
  different = true if a != other.next_u32
  i += 1
numeric_check("counter.replay", same)
numeric_check("counter.stream.separation", different)

pool = Probability.stream_pool(81, 4)
numeric_check("counter.pool",
  pool.size == 4 && pool[0].stream == 0 && pool[3].stream == 3)

range_rng = Probability.counter_rng(1, 1)
in_range = true
i = 0
while i < 1000
  draw = range_rng.integer(11)
  in_range = false if draw < 0 || draw >= 11
  i += 1
numeric_check("counter.integer.range", in_range)

<< "probability_numerics_spec: all checks passed"
