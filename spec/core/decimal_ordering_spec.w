# Mixed Decimal/Integer ORDERING is numeric and exact — it must never fault.
# Regression pinned here: `x = -4.0` then `x >= 0` fell through every
# comparison arm to the as_int assert (both engines), because the ops had
# decimal-vs-decimal arms but no mixed arm.

x = -4.0
<< "neg_gte0 " + (x >= 0).to_s()
<< "neg_lt0 " + (x < 0).to_s()
<< "neg_ss0 " + (x <=> 0).to_s()

y = 4.0
<< "pos_gte0 " + (y >= 0).to_s()
<< "pos_lte4 " + (y <= 4).to_s()
<< "pos_gte4 " + (y >= 4).to_s()
<< "pos_gt3 " + (y > 3).to_s()
<< "pos_lt5 " + (y < 5).to_s()
<< "pos_ss4 " + (y <=> 4).to_s()

# int on the left
<< "int_lt " + (0 < x).to_s()
<< "int_gt " + (5 > y).to_s()
<< "int_ss " + (4 <=> y).to_s()

# fractional against neighbors
z = 2.5
<< "frac_gt2 " + (z > 2).to_s()
<< "frac_lt3 " + (z < 3).to_s()

# equality canary: the exactness-driven == policy is owned elsewhere; this
# line only pins that ORDERING changes never silently alter equality.
<< "eq_canary " + (y == 4).to_s()

# BigInt vs decimal orders (double-path, order only)
big = 10 ** 30
<< "big_gt_dec " + (big > x).to_s()
<< "dec_lt_big " + (x < big).to_s()
