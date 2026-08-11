# Word-overwrite destination ops (E4 stage 3). Compiled `r = a + w` /
# `r = a - w` / `r = a * w` overwriting a proven-dead BigInt candidate
# computes into the dying buffer (w_bigint_{add,sub,mul}_word_dest).
# These specs must print identical output compiled and interpreted: the
# interpreter does no escape analysis, so any divergence is a consumed
# value that was still live. The adversarial cases pin the alias rules:
# a plain slot copy kills candidacy statically, and every runtime-minted
# alias (identity returns, negation views) carries a shared mark that the
# dest entries must honor.

-> check(name, got, want)
  if got.to_s() == want.to_s()
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# -- fixed-operand word loops: the mul1/add1/sub1 bench shape --

-> loop_add(n)
  a = ((1 << 200) + 987654321) ## big
  r = 0 ## big
  i = 0 ## i64
  while i < n
    r = a + 5
    i = i + 1
  r + 0

-> loop_sub(n)
  a = ((1 << 200) + 987654321) ## big
  r = 0 ## big
  i = 0 ## i64
  while i < n
    r = a - 7
    i = i + 1
  r + 0

-> loop_mul(n)
  a = ((1 << 200) + 987654321) ## big
  r = 0 ## big
  i = 0 ## i64
  while i < n
    r = a * 3
    i = i + 1
  r + 0

-> loop_mul_commuted(n)
  a = ((1 << 200) + 987654321) ## big
  r = 0 ## big
  i = 0 ## i64
  while i < n
    r = 3 * a
    i = i + 1
  r + 0

ref_a = ((1 << 200) + 987654321) ## big
check("word.add.fixed", loop_add(50), ref_a + 5)
check("word.sub.fixed", loop_sub(50), ref_a - 7)
check("word.mul.fixed", loop_mul(50), ref_a * 3)
check("word.mul.commuted", loop_mul_commuted(50), 3 * ref_a)

# -- evolving chain: both vars candidates, buffers hand back and forth --

-> chain_addsub(n)
  a = ((1 << 256) + 123456789) ## big
  r = 0 ## big
  i = 0 ## i64
  while i < n
    r = a + 5
    a = r - 7
    i = i + 1
  c = a + r
  c

# reference spelled so no statement matches the word-dest shape
-> chain_addsub_ref(n)
  a = ((1 << 256) + 123456789) ## big
  r = 0 ## big
  i = 0 ## i64
  while i < n
    r = (a + 2) + 3
    a = (r - 3) - 4
    i = i + 1
  c = a + r
  c

check("word.chain.addsub", chain_addsub(1000), chain_addsub_ref(1000))

# -- growing mul chain: capacity refusals must self-heal --

-> chain_mulgrow(n)
  a = 12345678901234567890123456789 ## big
  r = 0 ## big
  i = 0 ## i64
  while i < n
    r = a * 3
    a = r - 5
    i = i + 1
  a + 0

-> chain_mulgrow_ref(n)
  a = 12345678901234567890123456789 ## big
  i = 0 ## i64
  while i < n
    a = (a * 3) - (2 + 3)
    i = i + 1
  a

check("word.chain.mulgrow", chain_mulgrow(2000), chain_mulgrow_ref(2000))

# -- negative operands and words crossing zero --

-> loop_neg_base(n)
  a = (0 - ((1 << 130) + 55555)) ## big
  r = 0 ## big
  i = 0 ## i64
  while i < n
    r = a + 9
    r = a - 9
    r = a * 7
    i = i + 1
  r + 0

neg_ref = (0 - ((1 << 130) + 55555)) ## big
check("word.neg.base", loop_neg_base(25), neg_ref * 7)

# -- width transitions: two-limb results shrinking to one limb --

-> loop_shrink(n)
  a = (1 << 64) ## big
  r = 0 ## big
  i = 0 ## i64
  while i < n
    r = a - 7
    r = a + 3
    i = i + 1
  r + 0

check("word.width.shrink", loop_shrink(40), (1 << 64) + 3)

# -- ADVERSARIAL: plain slot copy — candidacy dies statically --

-> alias_slot_copy(n)
  seed = 111111111111111111111111111111111111 ## big
  a = ((1 << 180) + 42) ## big
  r = seed + 0
  y = r
  i = 0 ## i64
  while i < n
    r = a + 5
    r = a * 3
    r = a - 7
    i = i + 1
  y

check("alias.slot_copy", alias_slot_copy(30), 111111111111111111111111111111111111)

# -- ADVERSARIAL: identity alias (x + 0) — candidacy survives, the
# shared mark must protect the still-live operand --

-> alias_identity(n)
  x = 777777777777777777777777777777777777 ## big
  a = ((1 << 190) + 271828) ## big
  r = 0 ## big
  r = x + 0
  i = 0 ## i64
  while i < n
    r = a * 3
    r = a + 5
    i = i + 1
  x

check("alias.identity_x_plus_0", alias_identity(30), 777777777777777777777777777777777777)

-> alias_identity_mul(n)
  x = 888888888888888888888888888888888888 ## big
  a = ((1 << 190) + 271828) ## big
  r = 0 ## big
  r = x * 1
  i = 0 ## i64
  while i < n
    r = a - 7
    i = i + 1
  x

check("alias.identity_x_times_1", alias_identity_mul(30), 888888888888888888888888888888888888)

# -- ADVERSARIAL: negation view of the candidate's value --

-> alias_negation(n)
  a = ((1 << 170) + 314159) ## big
  r = 0 ## big
  r = a + 5
  y = 0 - r
  i = 0 ## i64
  while i < n
    r = a * 3
    r = a - 7
    i = i + 1
  y + 0

neg_a = ((1 << 170) + 314159) ## big
check("alias.negation_view", alias_negation(30), 0 - (neg_a + 5))

# -- ADVERSARIAL: parameter overwrite must never consume the caller's
# value (no dominating local seed => no candidacy) --

-> overwrite_param(r, a, n)
  i = 0 ## i64
  while i < n
    r = a + 5
    i = i + 1
  r

caller_kept = 999999999999999999999999999999999999 ## big
param_a = ((1 << 160) + 161803) ## big
got = overwrite_param(caller_kept, param_a, 20)
check("param.result", got, param_a + 5)
check("param.caller_value_intact", caller_kept, 999999999999999999999999999999999999)

# -- conditional seed must not admit (the dest load must never see an
# uninitialized slot); behavior must simply match the interpreter --

-> conditional_seed(flag, n)
  a = ((1 << 150) + 7) ## big
  if flag
    r = 0 ## big
  i = 0 ## i64
  while i < n
    r = a + 5
    i = i + 1
  r

check("seed.conditional_true", conditional_seed(true, 10), ((1 << 150) + 7) + 5)
check("seed.conditional_false", conditional_seed(false, 10), ((1 << 150) + 7) + 5)

# -- word operand arriving in a variable (not statically extractable) --

-> loop_var_word(n, w)
  a = ((1 << 210) + 999) ## big
  r = 0 ## big
  i = 0 ## i64
  while i < n
    r = a + w
    r = a * w
    r = a - w
    i = i + 1
  r + 0

vw_ref = ((1 << 210) + 999) ## big
check("word.var_word_small", loop_var_word(20, 11), vw_ref - 11)
check("word.var_word_negative", loop_var_word(20, 0 - 6), vw_ref + 6)
check("word.var_word_zero", loop_var_word(20, 0), vw_ref)
check("word.var_word_one", loop_var_word(20, 1), vw_ref - 1)
check("word.var_word_wide", loop_var_word(20, 1 << 60), vw_ref - (1 << 60))

# -- dynamic non-integer word: entry must fall back to the polymorphic op --

-> loop_rational_word(n, w)
  a = ((1 << 90) + 17) ## big
  r = 0 ## big
  i = 0 ## i64
  while i < n
    r = a * w
    i = i + 1
  r + 0

rat_base = ((1 << 90) + 17) ## big
rat_want = rat_base * (1/2)
check("word.rational_falls_back", loop_rational_word(10, 1/2), rat_want)

<< "bigint_word_dest_spec done"
