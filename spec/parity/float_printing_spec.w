# Floats: the `~` prefix makes a binary float; printed forms of sums,
# whole values, long fractions, and math functions.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "flt.half [~0.5]"
<< "flt.sum [~0.1 + ~0.2]"
<< "flt.whole [~5.0]"
<< "flt.whole.mul [~2.5 * ~2.0]"
<< "flt.big2 [~123456789012345678.0]"
<< "flt.div [~1.0 / ~3.0]"
<< "flt.tenth [~0.1]"
<< "flt.third.mul [~0.1 * ~3.0]"
<< "flt.to_s [(~0.25).to_s]"
<< "flt.neg [-~0.5]"
<< "flt.zero [~0.0]"
<< "flt.int.mix [~1.5 + 1]"
<< "flt.type [type(~0.5)]"
<< "flt.sqrt [Math.sqrt(~2.0)]"
<< "flt.sin [Math.sin(~0.0)]"
<< "flt.round [(~2.567).round(2)]"
<< "flt.floor [(~2.7).floor]"
<< "flt.to_i [(~2.9).to_i]"
<< "flt.tof [(3).to_f]"
<< "flt.tof2 [(7).to_f / 2]"
<< "flt.sum.arr [[~0.5, ~1.5].sum]"
<< ~5.0
<< ~0.1 + ~0.2
