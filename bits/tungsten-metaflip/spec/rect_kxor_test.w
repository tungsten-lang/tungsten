use ../lib/metaflip/kernels/rect_kxor

-> ffrxt_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL rectangular kxor: " + label
    exit(1)
  1

# Unequal widths exercise the exact rectangular loops directly.  The first two
# selected terms share V/W, so multilinearity collapses them into one U-XOR
# term.  Four untouched terms make a concrete 6 -> 5 identity.
us = i64[7]
vs = i64[7]
ws = i64[7]
us[0] = 1
vs[0] = 3
ws[0] = 5
us[1] = 2
vs[1] = 3
ws[1] = 5
us[2] = 4
vs[2] = 6
ws[2] = 9
us[3] = 8
vs[3] = 12
ws[3] = 3
us[4] = 16
vs[4] = 24
ws[4] = 6
us[5] = 32
vs[5] = 48
ws[5] = 12
us[6] = 3
vs[6] = 5
ws[6] = 10
selected6 = i64[6]
i = 0 ## i64
while i < 6
  selected6[i] = i
  i += 1

cu = i64[6]
cv = i64[6]
cw = i64[6]
cu[0] = us[0] ^ us[1]
cv[0] = vs[0]
cw[0] = ws[0]
i = 1
while i < 5
  cu[i] = us[i + 1]
  cv[i] = vs[i + 1]
  cw[i] = ws[i + 1]
  i += 1
indices5 = i64[5]
i = 0
while i < 5
  indices5[i] = i
  i += 1

z = ffrxt_expect("accepts multilinear 6 -> 5 identity", ffrx_local_exact_shape(us, vs, ws, selected6, 6, cu, cv, cw, indices5, 5, 6, 12, 8) == 1) ## i64
cw[4] = cw[4] ^ 1
z = ffrxt_expect("rejects one-bit corruption", ffrx_local_exact_shape(us, vs, ws, selected6, 6, cu, cv, cw, indices5, 5, 6, 12, 8) == 0)
cw[4] = ws[5]

# Add one untouched term to obtain the analogous 7 -> 6 identity.
selected7 = i64[7]
i = 0
while i < 7
  selected7[i] = i
  i += 1
cu[5] = us[6]
cv[5] = vs[6]
cw[5] = ws[6]
indices6 = i64[6]
i = 0
while i < 6
  indices6[i] = i
  i += 1
z = ffrxt_expect("accepts multilinear 7 -> 6 identity", ffrx_local_exact_shape(us, vs, ws, selected7, 7, cu, cv, cw, indices6, 6, 6, 12, 8) == 1)

# The rectangular target fold must equal the XOR of independently computed
# term fingerprints for both supported k values.
folded = i64[4]
manual = i64[4]
words = i64[4]
z = ffrx_target_fingerprint_shape(us, vs, ws, selected7, 7, 6, 12, 8, folded)
i = 0
while i < 7
  z = ffm_fingerprint_shape(us[i], vs[i], ws[i], 6, 12, 8, words)
  j = 0 ## i64
  while j < 4
    manual[j] = manual[j] ^ words[j]
    j += 1
  i += 1
i = 0
while i < 4
  z = ffrxt_expect("shape-aware target fingerprint word " + i.to_s(), folded[i] == manual[i])
  i += 1

z = ffrxt_expect("accepts bounded 6 -> 5 plan", ffrx_plan_valid(2, 5, 6, 6, 16, 128, 4, 0) == 1)
z = ffrxt_expect("accepts bounded 7 -> 6 plan", ffrx_plan_valid(4, 4, 5, 7, 8, 96, 4, 0) == 1)
z = ffrxt_expect("accepts bounded 7 -> 5 plan", ffrx_plan_valid_objective(2, 2, 7, 7, 5, 16, 128, 4, 0) == 1)
z = ffrxt_expect("accepts bounded 5 -> 3 single/pair plan", ffrx_plan_valid_objective(2, 2, 7, 5, 3, 16, 128, 4, 0) == 1)
z = ffrxt_expect("keeps direct 4 -> 2 single/single mode deferred", ffrx_plan_valid_objective(2, 2, 7, 4, 2, 16, 128, 4, 0) == 0)
z = ffrxt_expect("caps pair/triple 7 -> 5 memory", ffrx_plan_valid_objective(2, 2, 7, 7, 5, 8, 512, 4, 0) == 0)
z = ffrxt_expect("accepts bounded 6 -> 4 pair/pair plan", ffrx_plan_valid_objective(2, 2, 7, 6, 4, 8, 128, 4, 0) == 1)
z = ffrxt_expect("caps cubic 7 -> 6 memory", ffrx_plan_valid(4, 4, 5, 7, 8, 256, 4, 0) == 0)
z = ffrxt_expect("rejects unsupported rewrite arity", ffrx_plan_valid(3, 4, 6, 8, 8, 64, 2, 0) == 0)

<< "PASS rectangular kxor unequal-width exact gates"
