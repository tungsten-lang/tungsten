# Decimals: division, powers, rounding, conversions, comparisons.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "int.div [1 / 4]"
<< "dec.div3 [1.0 / 3]"
<< "dec.div3b [10 / 3.0]"
<< "dec.to_f [(0.5).to_f]"
<< "dec.to_i [(2.9).to_i]"
<< "dec.round [(2.345).round(2)]"
<< "dec.floor [(2.7).floor]"
<< "dec.ceil [(2.1).ceil]"
<< "dec.pow [1.5 ** 2]"
<< "dec.sqrt [Math.sqrt(2.25)]"
<< "dec.cmp [0.1 < 0.2]"
<< "dec.int.eq [2.0 == 2]"
<< "dec.mix [1 + 0.5]"
<< "dec.mul.int [0.25 * 4]"
