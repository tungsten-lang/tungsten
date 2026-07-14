# Core Int number-theory regressions.
# Run: `bin/tungsten -o /tmp/int-spec spec/numeric/int_spec.w && /tmp/int-spec`.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

check("lcm.zero_zero", 0.lcm(0), 0)
check("lcm.left_zero", 0.lcm(17), 0)
check("lcm.right_zero", 17.lcm(0), 0)
check("lcm.positive", 21.lcm(6), 42)
check("lcm.negative", (-21).lcm(6), 42)

# The old multiply-first form promoted this intermediate to BigInt even though
# the exact result fits inline. The divide-first implementation does not.
check("lcm.common_large_factor", 1000000000.lcm(1000000000), 1000000000)
check("lcm.bigint_receiver", 1000000000000000.lcm(1000000000000000), 1000000000000000)
check("lcm.bigint_mixed", 6.lcm(1000000000000000), 3000000000000000)
