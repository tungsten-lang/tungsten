# BigInt#prev/succ/next — served by Int's source bodies through type-class
# dispatch since the C IC rows were retired (runtime-to-core port). Pins
# value semantics across widths, signs, and the i48 demotion crossover on
# both engines.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

one_limb = 10 ** 18
two_limb = 10 ** 30
four_limb = 10 ** 70

# succ/prev are +1/-1 and leave the receiver untouched
check("succ.one_limb", one_limb.succ.to_s(), (one_limb + 1).to_s())
check("prev.one_limb", one_limb.prev.to_s(), (one_limb - 1).to_s())
check("succ.two_limb", two_limb.succ.to_s(), (two_limb + 1).to_s())
check("prev.two_limb", two_limb.prev.to_s(), (two_limb - 1).to_s())
check("succ.four_limb", four_limb.succ.to_s(), (four_limb + 1).to_s())
check("prev.four_limb", four_limb.prev.to_s(), (four_limb - 1).to_s())
check("receiver.untouched", one_limb.to_s(), (10 ** 18).to_s())

# next is succ
check("next.equals_succ", four_limb.next.to_s(), four_limb.succ.to_s())

# negative receivers: prev grows magnitude, succ shrinks it
neg = 0 - two_limb
check("succ.negative", neg.succ.to_s(), (1 - two_limb).to_s())
check("prev.negative", neg.prev.to_s(), (0 - two_limb - 1).to_s())

# inverse identities round-trip across the whole surface
check("prev.succ_inverse", four_limb.prev.succ.to_s(), four_limb.to_s())
check("succ.prev_inverse", four_limb.succ.prev.to_s(), four_limb.to_s())

# i48 demotion crossover: 2^47 is the first heap magnitude; its prev is the
# largest inline value and must still compare/print exactly
crossover = 140737488355328
check("prev.crossover_demotes", crossover.prev.to_s(), "140737488355327")
check("succ.crossover", crossover.succ.to_s(), "140737488355329")
check("prev.crossover_roundtrip", crossover.prev.succ.to_s(), crossover.to_s())
neg_crossover = 0 - crossover
check("succ.neg_crossover", neg_crossover.succ.to_s(), "-140737488355327")
check("prev.neg_crossover", neg_crossover.prev.to_s(), "-140737488355329")

<< "bigint_succ_prev_spec: all checks passed"
