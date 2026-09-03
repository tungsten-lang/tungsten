# Decimals: float literals are exact decimals; printed forms of whole
# values, e-notation literals, tiny and huge values.
#
# Cross-engine parity spec (scripts/parity.sh).

<< "dec.sum [0.1 + 0.2]"
<< "dec.eq [0.1 + 0.2 == 0.3]"
<< "dec.whole [5.0]"
<< "dec.whole.mul [2.5 * 2]"
<< "dec.whole.add [1.5 + 3.5]"
<< "dec.e [1.5e3]"
<< "dec.e2 [1e10]"
<< "dec.e3 [1e-7]"
<< "dec.e4 [2.5e-3]"
<< "dec.big [12345.678 * 1000]"
<< "dec.trailing [1.50]"
<< "dec.tiny [0.000001]"
<< "dec.tiny2 [0.0000001]"
<< "dec.huge [1e20]"
<< "dec.huge2 [1.0e21 * 10]"
<< "dec.neg [-0.5 + 0.25]"
<< "dec.tos [(0.5).to_s]"
<< "dec.type [type(0.5)]"
<< "dec.type2 [type(2.0 * 2)]"
<< 5.0
<< 0.1 + 0.2
