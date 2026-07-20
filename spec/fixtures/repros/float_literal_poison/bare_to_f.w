# Minimal-minimal repro: a decimal literal is an exact Decimal (0xFFFD tag),
# NOT a Float (`~0.5` is the Float form). Before the fix, `(0.5).to_f` died
# "undefined method 'to_f'" because the Decimal IC table (w_ic_decimal_table)
# omitted to_f — no division, no earlier literal, no method boundary needed.
<< "bare to_f: " + (0.5).to_f.to_s
<< "bare to_f neg: " + (-0.25).to_f.to_s
