# Parity spec for Currency ordering, Decimal modulo, and String#count
# across compiled and interpreted engines.

# 1. Currency ordering (<, <=, >, >=, <=>)
<< "cur.lt " + ($5.00 < $6.00).to_s()
<< "cur.lt.eq " + ($5.00 < $5.0).to_s()
<< "cur.lte " + ($5.00 <= $5.0).to_s()
<< "cur.gt " + ($6.00 > $5.00).to_s()
<< "cur.gte " + ($5.01 >= $5.0).to_s()
<< "cur.neg " + (-$2.50 < $1.00).to_s()
<< "cur.cmp.lt " + ($5.00 <=> $6.00).to_s()
<< "cur.cmp.eq " + ($5.00 <=> $5.0).to_s()
<< "cur.cmp.gt " + ($6.00 <=> $5.00).to_s()
<< "cur.big.lt " + ($999999.99 < $1000000.00).to_s()

# 2. Decimal modulo (%)
<< "dec.mod.int " + (5.5 % 2).to_s()
<< "dec.mod.neg " + (-5.5 % 2).to_s()
<< "dec.mod.dec " + (5.5 % 1.25).to_s()
<< "dec.mod.int_lhs " + (10 % 0.3).to_s()
<< "dec.mod.zero_rem " + (2.5 % 0.5).to_s()
<< "dec.mod.big " + (100000000000000000000.5 % 3).to_s()

dec_zero = false
begin
  _ = 5.5 % 0
rescue e
  dec_zero = true
<< "dec.mod.zero_raises " + dec_zero.to_s()

# 3. String#count (static and dynamic receiver)
-> poly_count(x, sub)
  x.count(sub)

<< "str.count.char " + "banana".count("a").to_s()
<< "str.count.sub " + "banana".count("an").to_s()
<< "str.count.none " + "banana".count("z").to_s()
<< "str.count.empty " + "banana".count("").to_s()
<< "str.count.poly " + poly_count("banana", "a").to_s()
<< "str.count.poly_sub " + poly_count("ababab", "ab").to_s()
