# Conversion pipes: `| unit` converts (left unit wins arithmetic; pipe picks
# display unit), `| unit(d)` rounds to d decimals. Engineering ≈x.xxx×10ⁿ
# display for magnitudes >= 10^16.
<< 5 kg + 3 kg | lb(2)
<< 1 km | m
<< 1 g · 299_792_458 m/s · 299_792_458 m/s | J
