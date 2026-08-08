# BigInt bitwise `&` semantics — pins the source-routed operator (weak-arm
# seam + BigInt#&(BigInt) typed body) against the C kernels on both engines.
# Two's-complement semantics for negatives (Python-int parity), sign-free
# straight kernel for the migrated both-positive multi-limb arm.

fails = 0

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

a = (1 << 200) + (1 << 130) + 12345
b = (1 << 190) + (1 << 130) + 54321

# Both-positive unequal length (the migrated arm)
check("pp_uneq", a & b, (1 << 130) + 4145)
check("pp_uneq_comm", b & a, (1 << 130) + 4145)

# Both-positive equal length (also in the arm)
c4 = (1 << 250) + (1 << 100) + 77
d4 = (1 << 250) + (1 << 100) + 14
check("pp_eq", c4 & d4, (1 << 250) + (1 << 100) + 12)

# Top-limb cancellation must trim and stay canonical
t1 = (43690 << 128) + ((1 << 64) - 1)
t2 = (21845 << 128) + ((1 << 64) - 1)
check("top_cancel", t1 & t2, (1 << 64) - 1)

# Result demotes to inline when small
check("demote", ((1 << 200) + 7) & ((1 << 130) + 7), 7)

# Disjoint bits -> zero
check("disjoint_zero", (1 << 200) & (1 << 199), 0)

# Identity aliasing arm
check("self_and", a & a, a)

# One-limb operands stay on the C fused arm; values still exact
p1 = (1 << 60) + 999
p2 = (1 << 60) + 123
check("one_limb", p1 & p2, (1 << 60) + 99)

# Inline-int mixes
check("int_arg", a & 255, 57)
check("int_recv", 255 & a, 57)

# Negatives: two's-complement, matching Python ints. Expected values are
# bound to variables first: `0 - <big literal>` inline currently trips the
# known compiled const-fold wrap (see the negated-big-literal lowering bug),
# and the spec must pin `&`, not that bug.
np_want = 1569275433846670190958947355801916604025588861116008678401
pn_want = 1606938044258990275541962092341162602522202993782792835309577
nn_mag = 1608507319692836945734282169164648272980082081073635916837945
check("neg_pos", (0 - a) & b, np_want)
check("pos_neg", a & (0 - b), pn_want)
check("neg_neg", (0 - a) & (0 - b), 0 - nn_mag)

# Negative one-limb
check("neg_small", (0 - 6) & 13, 8)

# Explicit operator send
check("explicit_send", a.&(b), (1 << 130) + 4145)

# Chained ops across the family.
# a & b is odd, so `| 1` is a no-op and `^ 1` clears bit 0.
check("mix_family", ((a & b) | 1) ^ 1, (1 << 130) + 4144)

# --- Bitwise OR (source-routed for both-positive multi-limb pairs) ---
or_uneq_want = 1608507319692836945734282169164648272980082081073635916837945
check("or_pp_uneq", a | b, or_uneq_want)
check("or_pp_uneq_comm", b | a, or_uneq_want)
or_eq_want = 1809251394333065553493296640760748560207343511668284413344754151620345856079
check("or_pp_eq", c4 | d4, or_eq_want)
# Tail-copy path: max-width result from a skew pair
or_skew_want = 1606938044258990275543323221808846356376056492212519908147215
check("or_skew", ((1 << 200) + 7) | ((1 << 130) + 9), or_skew_want)
# Negatives keep C's fused two's-complement pass
or_np_want = 1606938044258990275541962092341162602522202993782792835309577
check("or_neg_pos", (0 - a) | b, 0 - or_np_want)
check("or_self", a | a, a)
check("or_int_arg", a | 255, a + 255 - 57)
check("or_explicit_send", a.|(b), or_uneq_want)

# --- Bitwise XOR (source-routed for both-positive multi-limb pairs) ---
xor_uneq_want = 1608507319692836945732921039696964519126228582643908843987976
check("xor_pp_uneq", a ^ b, xor_uneq_want)
check("xor_pp_uneq_comm", b ^ a, xor_uneq_want)
# Equal-length XOR cancels every shared top limb — the trim/demote path
check("xor_eq_cancel", c4 ^ d4, 67)
check("xor_self_zero", a ^ a, 0)
xor_np_want = 1608507319692836945732921039696964519126228582643908843987978
check("xor_neg_pos", (0 - a) ^ b, 0 - xor_np_want)
xor_int_want = 1606938044258990275543323221808846356376056492212519908159686
check("xor_int_arg", a ^ 255, xor_int_want)
check("xor_explicit_send", a.^(b), xor_uneq_want)
# Involution: (x ^ y) ^ y == x across the family
check("xor_involution", (a ^ b) ^ b, a)

<< "bigint_bitwise_spec: all checks passed"
