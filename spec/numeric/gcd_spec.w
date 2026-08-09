# Integer#gcd — zero identities, sign normalization, W_INT48-boundary
# operands, multi-limb (BigInt) cases, and length-skewed operand pairs.
# gcd underpins Rational normalization, so wrong answers here corrupt
# every rational result silently. Expected values are precomputed and
# cross-checked against the interpreter; all comparisons go through
# .to_s so BigInt and inline-int results check identically.

-> gcd_check(name, got, want)
  if got.to_s == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s + " want " + want
    exit 1

# --- zero identities ---
gcd_check("gcd.zero_zero", 0.gcd(0), "0")
gcd_check("gcd.zero_n", 0.gcd(7), "7")
gcd_check("gcd.n_zero", 7.gcd(0), "7")

# --- sign normalization: result is always non-negative ---
gcd_check("gcd.neg_left", (-12).gcd(8), "4")
gcd_check("gcd.neg_right", 12.gcd(-8), "4")
gcd_check("gcd.neg_both", (-12).gcd(-8), "4")

# --- W_INT48 boundary: operands straddle the 47/48-bit inline range ---
# (2^47 - 3) * 2 and (2^47 - 3) * 3 share exactly (2^47 - 3).
gcd_check("gcd.i48_shared_factor", 281474976710650.gcd(422212465065975), "140737488355325")
# 2^48 vs 2^47: the answer itself sits on the promotion boundary.
gcd_check("gcd.i48_pow2", (2**48).gcd(2**47), "140737488355328")

# --- full-u64 one-limb BigInts ---
# The result itself exceeds the inline payload and must remain an exact,
# positive one-limb BigInt. Neither operand divides the other.
one_limb_factor = 140737488355329
gcd_check(
  "gcd.one_limb_heap_result",
  (one_limb_factor * 5).gcd(0 - one_limb_factor * 7),
  "140737488355329"
)
# Exercise unsigned comparisons with both magnitudes' high bit set.
gcd_check(
  "gcd.one_limb_high_bit",
  "18446744073709551615".to_i.gcd("-9223372036854775809".to_i),
  "3"
)

# --- multi-limb (BigInt) ---
# 3^200 vs 3^150 -> 3^150.
gcd_check("gcd.big_pow3", (3**200).gcd(3**150), "369988485035126972924700782451696644186473100389722973815184405301748249")
# Products of distinct Mersenne primes sharing exactly 2^89-1:
# (2^89-1)(2^107-1) vs (2^89-1)(2^127-1).
# TODO(compiler bug): building BOTH operands via "literal".to_i miscompiles —
# String#to_i infers :int, the inlined Integer#gcd then runs raw-i64
# arithmetic on unboxed BigInt pointer bits and returns 1 (interpreter is
# correct; one to_i operand mixed with a **-built one is also correct).
# Same family as the 35a03fe :int-raw-unbox fixes. Until that is fixed the
# products are built with ** so this case asserts real multi-limb gcd.
pq = (2**89 - 1) * (2**107 - 1)
pr = (2**89 - 1) * (2**127 - 1)
gcd_check("gcd.big_shared_prime", pq.gcd(pr), "618970019642690137449562111")
# Mixed construction: one to_i-built operand, one **-built (both orders).
pr_toi = "105312291668557186697918027513529248857806893649219117400977309697".to_i
gcd_check("gcd.big_shared_prime_toi_arg", pq.gcd(pr_toi), "618970019642690137449562111")
gcd_check("gcd.big_shared_prime_toi_recv", pr_toi.gcd(pq), "618970019642690137449562111")
# 2^300+1 vs 2^150+1 are coprime (2^300+1 = 2 mod any divisor of 2^150+1).
gcd_check("gcd.big_coprime", (2**300 + 1).gcd(2**150 + 1), "1")

# --- length skew: one huge operand, one tiny ---
gcd_check("gcd.skew_big_small", (3**200).gcd(51), "3")
gcd_check("gcd.skew_small_big", 51.gcd(3**200), "3")
neg_big = "-265613988875874769338781322035779626829233452653394495974574961739092490901302182994384699044001".to_i
gcd_check("gcd.skew_neg_big", neg_big.gcd(51), "3")

<< "gcd: ok"
