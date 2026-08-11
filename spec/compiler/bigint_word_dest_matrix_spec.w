# Word-dest value-correctness matrix (E4 stage 3). Sweeps widths 1..64
# limbs (plus the >= 128 mul fallback band), all four sign combinations,
# and word shapes {small, negative, wide, zero, one} through the three
# dest-taking loop shapes, comparing every result against the ordinary
# immutable path computed in a candidate-free helper. Full values print
# so an external oracle (python3) can re-derive each line, and the
# compiled/interpreted outputs must be byte-identical.

-> ref_op(a, w, op)
  if op == 0
    return a + w
  if op == 1
    return a - w
  a * w

-> lane(bits, aneg, w, op, n)
  a = 0 ## big
  if aneg > 0
    a = (0 - ((1 << bits) + 987654321987654321)) ## big
  else
    a = ((1 << bits) + 987654321987654321) ## big
  r = 0 ## big
  i = 0 ## i64
  while i < n
    if op == 0
      r = a + w
    elsif op == 1
      r = a - w
    else
      r = a * w
    i = i + 1
  out = r + 0
  out

-> lane_mixed(bits, aneg, w, n)
  # alternating shapes in one loop: mul grows a limb, add/sub shrink back,
  # so the capacity guard and its self-healing refusal both run
  a = 0 ## big
  if aneg > 0
    a = (0 - ((1 << bits) + 987654321987654321)) ## big
  else
    a = ((1 << bits) + 987654321987654321) ## big
  r = 0 ## big
  i = 0 ## i64
  while i < n
    r = a * w
    r = a + w
    r = a - w
    r = a * w
    i = i + 1
  out = r + 0
  out

widths = [1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 15, 16, 17, 24, 31, 32, 33, 40, 47, 48, 63, 64, 65, 100, 127, 128, 129, 200]
words = [5, 0 - 7, (1 << 40) + 9, 0, 1, 0 - 1]
mismatches = 0 ## i64
wi = 0 ## i64
while wi < widths.size()
  limbs = widths[wi]
  bits = limbs * 64 - 8
  sign = 0 ## i64
  while sign < 2
    ki = 0 ## i64
    while ki < words.size()
      w = words[ki]
      op = 0 ## i64
      while op < 3
        got = lane(bits, sign, w, op, 3)
        aval = ref_op((1 << bits) + 987654321987654321, 0, 0)
        if sign > 0
          aval = 0 - ((1 << bits) + 987654321987654321)
        want = ref_op(aval, w, op)
        if got != want
          mismatches += 1
          << "MISMATCH limbs=" + limbs.to_s() + " sign=" + sign.to_s() + " w=" + w.to_s() + " op=" + op.to_s()
        << limbs.to_s() + "|" + sign.to_s() + "|" + w.to_s() + "|" + op.to_s() + "|" + got.to_s()
        op += 1
      gotm = lane_mixed(bits, sign, 3, 4)
      op += 0
      ki += 1
    sign += 1
  wi += 1

# mixed-shape sweep printed separately (word 3 only, both signs)
wi = 0 ## i64
while wi < widths.size()
  limbs = widths[wi]
  bits = limbs * 64 - 8
  sign = 0 ## i64
  while sign < 2
    gotm = lane_mixed(bits, sign, 3, 4)
    aval = ref_op((1 << bits) + 987654321987654321, 0, 0)
    if sign > 0
      aval = 0 - ((1 << bits) + 987654321987654321)
    wantm = ref_op(aval, 3, 2)
    if gotm != wantm
      mismatches += 1
      << "MISMATCH-MIXED limbs=" + limbs.to_s() + " sign=" + sign.to_s()
    << "M|" + limbs.to_s() + "|" + sign.to_s() + "|" + gotm.to_s()
    sign += 1
  wi += 1

if mismatches == 0
  << "word_dest_matrix: all cases match"
else
  << "word_dest_matrix: MISMATCHES " + mismatches.to_s()
  exit 1
