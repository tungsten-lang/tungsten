## parity xfail `when 3..9` in a case never matches interpreted (falls to else) but matches compiled
# Control flow: a range as a case/when arm.
#
# Cross-engine parity spec (scripts/parity.sh).

-> classify(n)
  case n
  when 0
    "zero"
  when 3..9
    "medium"
  else
    "big"
<< "case.range [classify(0)] [classify(5)] [classify(50)]"
