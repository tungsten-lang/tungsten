fn check(label, actual, expected)
  if actual != expected
    << label
    << expected
    << actual
    raise label

# Small Int and multi-limb BigInt test operands
small_pos = 107
small_neg = -107
small_div = 13
small_ndiv = -13

big_a = (1 << 130) + 1234567890123456789
big_na = -big_a
big_b = (1 << 67) + 987654321
big_nb = -big_b

# 1. Division & Remainder families (tdiv, tmod, tdivmod, fdiv, fmod, fdivmod, divmod, cdiv, cmod, cdivmod)
check("small tdiv ++", small_pos.tdiv(small_div), 8)
check("small tmod ++", small_pos.tmod(small_div), 3)
check("small tdivmod +-", small_pos.tdivmod(small_ndiv), [-8, 3])
check("small tdivmod -+", small_neg.tdivmod(small_div), [-8, -3])
check("small tdivmod --", small_neg.tdivmod(small_ndiv), [8, -3])

check("small fdiv ++", small_pos.fdiv(small_div), 8)
check("small fmod ++", small_pos.fmod(small_div), 3)
check("small fdivmod +-", small_pos.fdivmod(small_ndiv), [-9, -10])
check("small fdivmod -+", small_neg.fdivmod(small_div), [-9, 10])
check("small fdivmod --", small_neg.fdivmod(small_ndiv), [8, -3])
check("small divmod -+", small_neg.divmod(small_div), [-9, 10])

check("small cdiv ++", small_pos.cdiv(small_div), 9)
check("small cmod ++", small_pos.cmod(small_div), -10)
check("small cdivmod +-", small_pos.cdivmod(small_ndiv), [-8, 3])
check("small cdivmod -+", small_neg.cdivmod(small_div), [-8, -3])
check("small cdivmod --", small_neg.cdivmod(small_ndiv), [9, 10])

# BigInt division identities: a == q * b + r
tq, tr = big_a.tdivmod(big_b)
check("big tdiv", big_a.tdiv(big_b), tq)
check("big tmod", big_a.tmod(big_b), tr)
check("big tdivmod identity", tq * big_b + tr, big_a)

fq, fr = big_na.fdivmod(big_b)
check("big fdiv -+", big_na.fdiv(big_b), fq)
check("big fmod -+", big_na.fmod(big_b), fr)
check("big fdivmod identity -+", fq * big_b + fr, big_na)
check("big divmod -+", big_na.divmod(big_b), [fq, fr])

cq, cr = big_a.cdivmod(big_b)
check("big cdiv ++", big_a.cdiv(big_b), cq)
check("big cmod ++", big_a.cmod(big_b), cr)
check("big cdivmod identity ++", cq * big_b + cr, big_a)

# 2. Exact division, divisibility, congruence
prod = big_a * big_b
check("big divexact", prod.divexact(big_b), big_a)
check("big neg divexact", (-prod).divexact(big_b), big_na)
check("big divisible? true", prod.divisible?(big_b), true)
check("big divisible? false", (prod + 1).divisible?(big_b), false)
check("big congruent? true", (prod + 42).congruent?(42, big_b), true)
check("big congruent? false", (prod + 43).congruent?(42, big_b), false)

# 3. Roots & Perfect Powers
s_val = (1 << 100) + 777
sq = s_val * s_val
check("big isqrt_rem exact", sq.isqrt_rem, [s_val, 0])
check("big isqrt_rem +5", (sq + 5).isqrt_rem, [s_val, 5])
check("big perfect_square? true", sq.perfect_square?, true)
check("big perfect_square? false", (sq + 1).perfect_square?, false)

cube_root = (1 << 70) + 33
cube = cube_root ** 3
check("big iroot 3", (cube + 19).iroot(3), cube_root)
check("big iroot_rem 3", (cube + 19).iroot_rem(3), [cube_root, 19])
check("big neg iroot 3", (-cube).iroot(3), -cube_root)
check("big perfect_power? cube", cube.perfect_power?, true)
check("big perfect_power? neg cube", (-cube).perfect_power?, true)
check("big perfect_power? non-power", (cube + 1).perfect_power?, false)

# 4. Number theory (gcdext, invmod, jacobi, kronecker, nextprime, prevprime, remove_factor)
g, x, y = big_a.gcdext(big_b)
check("big gcdext identity", big_a * x + big_b * y, g)
check("big gcdext matches gcd", g, big_a.gcd(big_b))

mod_p = (1 << 127) - 1
inv = big_a.invmod(mod_p)
check("big invmod", (big_a * inv) % mod_p, 1)

check("small jacobi", (1001).jacobi(9907), -1)
check("big jacobi", big_a.jacobi(mod_p), 1)
check("small kronecker even", (5).kronecker(8), -1)
check("big kronecker", big_a.kronecker(mod_p), big_a.jacobi(mod_p))

check("small nextprime", (14).nextprime, 17)
check("small prevprime", (17).prevprime, 13)
big_base = (1 << 80)
np = big_base.nextprime
check("big nextprime is prime", np.prime?, true)
check("big prevprime of nextprime", (np + 1).prevprime, np)

rem_target = big_b * (3 ** 7)
check("big remove_factor", rem_target.remove_factor(3), [big_b, 7])
check("big remove_factor 2", (big_b << 19).remove_factor(2), [big_b, 19])

# 5. Combinatorics & Special Sequences (Math.* and Integer#*)
check("factorial 10", (10).factorial, 3628800)
check("Math.factorial 25", Math.factorial(25), 15511210043330985984000000)
check("double_factorial 9", (9).double_factorial, 945)
check("double_factorial 10", (10).double_factorial, 3840)
check("multifactorial 10, 3", (10).multifactorial(3), 280)
check("primorial 13", (13).primorial, 30030)
check("binomial 50, 20", (50).binomial(20), 47129212243960)
check("Math.binomial 50, 20", Math.binomial(50, 20), 47129212243960)
check("Math.fib 100", Math.fib(100), 354224848179261915075)
check("Math.fib2 10", Math.fib2(10), [55, 34])
check("Math.lucas 10", Math.lucas(10), 123)
check("Math.lucas2 10", Math.lucas2(10), [123, 76])

# 6. Bit manipulation & scanning
bit_val = (1 << 200) + (1 << 75) + (1 << 12)
check("big bit_length", bit_val.bit_length, 201)
check("big sizeinbase 2", bit_val.sizeinbase(2), 201)
check("big sizeinbase 16", bit_val.sizeinbase(16), 51)
check("big popcount", bit_val.popcount, 3)
check("big hamdist", bit_val.hamdist((1 << 200) + (1 << 12) + 1), 2)
check("big scan1 from 0", bit_val.scan1(0), 12)
check("big scan1 from 13", bit_val.scan1(13), 75)
check("big scan0 from 12", bit_val.scan0(12), 13)
check("big trailing_zeros", bit_val.trailing_zeros, 12)
check("big tstbit 75", bit_val.tstbit(75), 1)
check("big tstbit 76", bit_val.tstbit(76), 0)
check("big bit_set? 75", bit_val.bit_set?(75), true)
check("big bit_set? 76", bit_val.bit_set?(76), false)
check("big setbit", bit_val.setbit(76).tstbit(76), 1)
check("big clrbit", bit_val.clrbit(75).tstbit(75), 0)
check("big combit 1->0", bit_val.combit(75).tstbit(75), 0)
check("big combit 0->1", bit_val.combit(76).tstbit(76), 1)

# 7. Magnitude comparison & byte serialization
check("big cmpabs eq", big_na.cmpabs(big_a), 0)
check("big cmpabs gt", big_na.cmpabs(big_b), 1)
check("big cmpabs lt", big_b.cmpabs(big_na), -1)

bytes_be = big_a.to_bytes(:big)
bytes_le = big_a.to_bytes(:little)
check("big from_bytes big", Integer.from_bytes(bytes_be, :big), big_a)
check("big from_bytes little", Integer.from_bytes(bytes_le, :little), big_a)
check("BigInt.from_bytes big", BigInt.from_bytes(bytes_be, :big), big_a)

<< "ALL 49 GMP OPS PASSED"
