# Same-binary boxed acceptance harness for complete immutable and consumed
# compound BigInt bitwise migration. The candidate lane calls a stable source seam through a
# benchmark-only noinline wrapper; the oracle lane calls the retained C kernel
# through an otherwise identical wrapper.  Baseline builds without the future
# completion marker remain runnable, but inline-operand rows are explicitly
# reported as C/C controls and cannot pass full-acceptance mode in the runner.

CORPUS_SIZE = 8
CORPUS_MASK = CORPUS_SIZE - 1

-> thread_cpu_ns
  ccall("w_leafpub_thread_cpu_ns")

-> consume_low_byte(value)
  ccall("w_leafpub_consume_low_byte", value)

-> source_and(a, b)
  ccall("w_bitwise_gate_and_source", a, b)

-> source_or(a, b)
  ccall("w_bitwise_gate_or_source", a, b)

-> source_xor(a, b)
  ccall("w_bitwise_gate_xor_source", a, b)

-> baseline_and(a, b)
  ccall("w_bitwise_gate_and_source_baseline", a, b)

-> baseline_or(a, b)
  ccall("w_bitwise_gate_or_source_baseline", a, b)

-> baseline_xor(a, b)
  ccall("w_bitwise_gate_xor_source_baseline", a, b)

-> source_complete?
  ccall("w_bitwise_gate_source_complete")

-> c_and(a, b)
  ccall("w_bitwise_gate_and_c", a, b)

-> c_or(a, b)
  ccall("w_bitwise_gate_or_c", a, b)

-> c_xor(a, b)
  ccall("w_bitwise_gate_xor_c", a, b)

-> source_and_mut(a, b)
  ccall("w_bitwise_gate_and_mut_source", a, b)

-> source_or_mut(a, b)
  ccall("w_bitwise_gate_or_mut_source", a, b)

-> source_xor_mut(a, b)
  ccall("w_bitwise_gate_xor_mut_source", a, b)

-> c_and_mut(a, b)
  ccall("w_bitwise_gate_and_mut_c", a, b)

-> c_or_mut(a, b)
  ccall("w_bitwise_gate_or_mut_c", a, b)

-> c_xor_mut(a, b)
  ccall("w_bitwise_gate_xor_mut_c", a, b)

-> peek_low_byte(value)
  ccall("w_bitwise_gate_low_byte_no_release", value)

-> source_op(op, a, b)
  full = source_complete?()
  if op == "and"
    return full ? source_and(a, b) : baseline_and(a, b)
  if op == "or"
    return full ? source_or(a, b) : baseline_or(a, b)
  full ? source_xor(a, b) : baseline_xor(a, b)

-> c_op(op, a, b)
  if op == "and"
    return c_and(a, b)
  if op == "or"
    return c_or(a, b)
  c_xor(a, b)

-> source_mut_op(op, a, b)
  if op == "and"
    return source_and_mut(a, b)
  if op == "or"
    return source_or_mut(a, b)
  source_xor_mut(a, b)

-> c_mut_op(op, a, b)
  if op == "and"
    return c_and_mut(a, b)
  if op == "or"
    return c_or_mut(a, b)
  c_xor_mut(a, b)

-> public_op(op, a, b)
  if op == "and"
    return a & b
  if op == "or"
    return a | b
  a ^ b

-> explicit_op(op, a, b)
  if op == "and"
    return a.&(b)
  if op == "or"
    return a.|(b)
  a.^(b)

-> fail_check(name, detail)
  << "FAIL " + name + ": " + detail
  exit(1)

-> check_exact(name, got, expected)
  if !ccall("w_bitwise_gate_exact_integer", got, expected)
    fail_check(name, "source/public value differs from retained C")
  if !ccall("w_bitwise_gate_canonical_integer", got)
    fail_check(name, "noncanonical result representation")

-> check_inline_integer(name, value)
  if !ccall("w_bitwise_gate_inline_integer", value)
    fail_check(name, "one-limb demotion did not produce a canonical inline Integer")

-> make_width_value(limbs, salt)
  top = 1 << (limbs * 64 - 1)
  middle = 0
  if limbs > 1
    middle = 1 << ((limbs / 2) * 64 + 17)
  top + middle + salt * 2 + 1

-> make_negative(value, header_form, label)
  result = header_form ? ccall("w_bitwise_gate_header_negative", value) : ccall("w_bitwise_gate_overlay_negative", value)
  expected_form = header_form ? 1 : 2
  got_form = ccall("w_bitwise_gate_negative_form", result)
  if got_form != expected_form
    fail_check(label, "negative fixture has form " + got_form.to_s() + ", expected " + expected_form.to_s())
  result

-> distinct_equal(value, label)
  other = (value + 2) - 2
  if !ccall("w_bitwise_gate_distinct_storage", value, other)
    fail_check(label, "fixture construction collapsed to shared storage")
  other

-> suffix_width(stratum)
  pieces = stratum.split("-")
  pieces[pieces.size() - 1].to_i()

-> build_pairs(op, stratum)
  left = []
  right = []
  i = 0
  while i < CORPUS_SIZE
    a = nil
    b = nil
    if stratum.starts_with?("width-") || stratum.starts_with?("boundary-")
      width = suffix_width(stratum)
      a = make_width_value(width, i * 17 + 101)
      b = make_width_value(width, i * 29 + 211)
    elsif stratum == "skew-64-4"
      a = make_width_value(64, i * 17 + 301)
      b = make_width_value(4, i * 29 + 401)
    elsif stratum == "skew-4-64"
      a = make_width_value(4, i * 17 + 503)
      b = make_width_value(64, i * 29 + 601)
    elsif stratum == "skew-8192-4"
      a = make_width_value(8192, i * 17 + 701)
      b = make_width_value(4, i * 29 + 809)
    elsif stratum == "skew-4-8192"
      a = make_width_value(4, i * 17 + 907)
      b = make_width_value(8192, i * 29 + 1009)
    elsif stratum == "inline-left"
      a = 1000003 + i * 2
      b = make_width_value(8, i * 29 + 1103)
    elsif stratum == "inline-right"
      a = make_width_value(8, i * 17 + 1201)
      b = 1000033 + i * 2
    elsif stratum.starts_with?("negneg-overlay-")
      width = suffix_width(stratum)
      a = make_negative(make_width_value(width, i * 17 + 1301), false, stratum + "/a")
      b = make_negative(make_width_value(width, i * 29 + 1409), false, stratum + "/b")
    elsif stratum.starts_with?("negpos-overlay-")
      width = suffix_width(stratum)
      a = make_negative(make_width_value(width, i * 17 + 1511), false, stratum + "/a")
      b = make_width_value(width, i * 29 + 1601)
    elsif stratum.starts_with?("posneg-overlay-")
      width = suffix_width(stratum)
      a = make_width_value(width, i * 17 + 1709)
      b = make_negative(make_width_value(width, i * 29 + 1801), false, stratum + "/b")
    elsif stratum.starts_with?("negneg-header-")
      width = suffix_width(stratum)
      a = make_negative(make_width_value(width, i * 17 + 1901), true, stratum + "/a")
      b = make_negative(make_width_value(width, i * 29 + 2003), true, stratum + "/b")
    elsif stratum.starts_with?("negpos-header-")
      width = suffix_width(stratum)
      a = make_negative(make_width_value(width, i * 17 + 2111), true, stratum + "/a")
      b = make_width_value(width, i * 29 + 2203)
    elsif stratum.starts_with?("posneg-header-")
      width = suffix_width(stratum)
      a = make_width_value(width, i * 17 + 2309)
      b = make_negative(make_width_value(width, i * 29 + 2411), true, stratum + "/b")
    elsif stratum == "same-object"
      a = make_width_value(8, i * 17 + 2503)
      b = a
    elsif stratum == "distinct-equal"
      a = make_width_value(8, i * 17 + 2609)
      b = distinct_equal(a, stratum + "/" + i.to_s())
    elsif stratum == "zero-left"
      a = 0
      b = make_width_value(8, i * 29 + 2707)
    elsif stratum == "zero-right"
      a = make_width_value(8, i * 17 + 2801)
      b = 0
    elsif stratum == "minus-one-left"
      a = -1
      b = make_width_value(8, i * 29 + 2903)
    elsif stratum == "minus-one-right"
      a = make_width_value(8, i * 17 + 3001)
      b = -1
    elsif stratum == "normalize-top"
      if op == "and"
        a = (1 << 255) + (1 << 80) + i * 2 + 1
        b = (1 << 254) + (1 << 80) + i * 4 + 1
      elsif op == "or"
        a = make_width_value(64, i * 17 + 3109)
        b = make_width_value(4, i * 29 + 3203)
      else
        a = (1 << 255) + (1 << 80) + i * 2 + 1
        b = (1 << 255) + (1 << 80) + i * 4 + 3
    elsif stratum == "normalize-inline"
      if op == "and"
        a = (1 << 255) + 37
        b = (1 << 254) + 37
      elsif op == "or"
        a = make_negative(1 << 255, false, stratum + "/a")
        b = (1 << 255) - 1
      else
        a = (1 << 255) + 37
        b = (1 << 255) + 12
    elsif stratum == "normalize-zero"
      if op == "and"
        a = 1 << 255
        b = 1 << 254
      elsif op == "or"
        a = 0
        b = 0
      else
        a = make_width_value(8, i * 17 + 3301)
        b = distinct_equal(a, stratum + "/" + i.to_s())
    else
      fail_check("stratum", "unknown stratum " + stratum)
    left.push(a)
    right.push(b)
    i += 1
  [left, right]

-> build_mut_pair(op, stratum, salt)
  width = suffix_width(stratum)
  if width == 1 && op == "and"
    # Both operands are one-limb heap BigInts, but their high bits are
    # disjoint. The nonzero shared low field must demote to an inline Integer.
    low = 33 + (salt % 8) * 2
    return [(1 << 63) + low, (1 << 62) + low]
  if width == 1 && op == "xor"
    # Equal high fields cancel while distinct low fields leave a nonzero i48.
    low = 33 + (salt % 8) * 2
    return [(1 << 63) + low, (1 << 63) + low + 18]
  receiver = make_width_value(width, salt * 17 + 6007)
  top = width * 64 - 1
  argument = (1 << top) + (1 << (top - 2)) + 1085102592571150095 + salt * 2
  [receiver, argument]

# Timed width-one pairs deliberately remain heap BigInts after every
# operation, so the adaptive lane measures the consumed one-limb kernel rather
# than an inline-identity steady state after a single canonicalizing call.
-> build_mut_timing_pair(stratum, salt)
  width = suffix_width(stratum)
  receiver = make_width_value(width, salt * 17 + 6007)
  top = width * 64 - 1
  argument = (1 << top) + (1 << (top - 2)) + 1085102592571150095 + salt * 2
  [receiver, argument]

-> correctness_strata
  widths = [1, 2, 3, 4, 5, 8, 16, 24, 32, 40, 48, 64, 128, 256, 384, 448, 512, 1024, 2048, 4096, 8192]
  strata = []
  i = 0
  while i < widths.size()
    strata.push("width-" + widths[i].to_s())
    i += 1
  extras = [
    "boundary-4095", "boundary-4097",
    "skew-64-4", "skew-4-64", "skew-8192-4", "skew-4-8192",
    "inline-left", "inline-right",
    "negneg-overlay-1", "negpos-overlay-1", "posneg-overlay-1",
    "negneg-overlay-4", "negpos-overlay-4", "posneg-overlay-4",
    "negneg-overlay-64", "negpos-overlay-64", "posneg-overlay-64",
    "negneg-header-4", "negpos-header-4", "posneg-header-4",
    "negneg-header-64", "negpos-header-64", "posneg-header-64",
    "same-object", "distinct-equal", "zero-left", "zero-right",
    "minus-one-left", "minus-one-right",
    "normalize-top", "normalize-inline", "normalize-zero"
  ]
  i = 0
  while i < extras.size()
    strata.push(extras[i])
    i += 1
  strata

-> run_correctness
  ops = ["and", "or", "xor"]
  strata = correctness_strata()
  checks = 0
  partial_rows = 0
  control_rows = 0
  oi = 0
  while oi < ops.size()
    op = ops[oi]
    si = 0
    while si < strata.size()
      stratum = strata[si]
      pair = build_pairs(op, stratum)
      lane_kind = ccall("w_bitwise_gate_lane_kind", pair[0][0], pair[1][0])
      if lane_kind == 0
        control_rows += 1
      elsif lane_kind == 1
        partial_rows += 1
      i = 0
      while i < CORPUS_SIZE
        a = pair[0][i]
        b = pair[1][i]
        expected = c_op(op, a, b)
        check_exact(op + "/" + stratum + "/source/" + i.to_s(), source_op(op, a, b), expected)
        check_exact(op + "/" + stratum + "/public/" + i.to_s(), public_op(op, a, b), expected)
        if ccall("w_leafpub_is_bigint", a)
          check_exact(op + "/" + stratum + "/send/" + i.to_s(), explicit_op(op, a, b), expected)
          checks += 1
        elsif ccall("w_leafpub_is_bigint", b)
          check_exact(op + "/" + stratum + "/send-reverse/" + i.to_s(), explicit_op(op, b, a), expected)
          checks += 1
        reverse_expected = c_op(op, b, a)
        check_exact(op + "/" + stratum + "/reverse/" + i.to_s(), source_op(op, b, a), reverse_expected)
        check_exact(op + "/" + stratum + "/commute/" + i.to_s(), reverse_expected, expected)
        checks += 4
        i += 1
      si += 1
    oi += 1

  # Consumed compound seams get separate receiver storage for source, C, and
  # immutable-oracle evaluation. The public compound surface is checked once
  # per operation with an alias that must retain the pre-assignment value.
  mut_widths = [1, 2, 4, 8, 16, 32, 64, 128, 256]
  oi = 0
  while oi < ops.size()
    op = ops[oi]
    mi = 0
    while mi < mut_widths.size()
      mut_stratum = "mut-width-" + mut_widths[mi].to_s()
      want_pair = build_mut_pair(op, mut_stratum, mi + 101)
      expected = c_op(op, want_pair[0], want_pair[1])
      source_pair = build_mut_pair(op, mut_stratum, mi + 101)
      source_result = source_mut_op(op, source_pair[0], source_pair[1])
      check_exact(op + "/" + mut_stratum + "/source", source_result, expected)
      c_pair = build_mut_pair(op, mut_stratum, mi + 101)
      c_result = c_mut_op(op, c_pair[0], c_pair[1])
      check_exact(op + "/" + mut_stratum + "/c", c_result, expected)
      if mut_widths[mi] == 1 && op != "or"
        check_inline_integer(op + "/" + mut_stratum + "/expected-inline", expected)
        check_inline_integer(op + "/" + mut_stratum + "/source-inline", source_result)
        check_inline_integer(op + "/" + mut_stratum + "/c-inline", c_result)
      checks += 2
      mi += 1

    public_pair = build_mut_pair(op, "mut-width-4", oi + 401)
    receiver = public_pair[0]
    original = distinct_equal(receiver, op + "/compound-original")
    alias_value = receiver
    if op == "and"
      receiver &= public_pair[1]
    elsif op == "or"
      receiver |= public_pair[1]
    else
      receiver ^= public_pair[1]
    check_exact(op + "/compound-public", receiver, c_op(op, original, public_pair[1]))
    check_exact(op + "/compound-alias", alias_value, original)
    checks += 2

    # Unknown-typed compound operands still enter the stable consumed seam.
    # Its raw helper must preserve the public operator's Float coercion and
    # invalid-text error policy, not reinterpret arbitrary WValue tag bits.
    float_rhs = op == "and" ? ~15.75 : (op == "or" ? ~256.75 : ~255.75)
    source_float_pair = build_mut_timing_pair("mut-width-4", oi + 501)
    c_float_pair = build_mut_timing_pair("mut-width-4", oi + 501)
    source_float_result = source_mut_op(op, source_float_pair[0], float_rhs)
    c_float_result = c_mut_op(op, c_float_pair[0], float_rhs)
    check_exact(op + "/compound-float-policy", source_float_result, c_float_result)

    source_error = nil
    source_invalid_pair = build_mut_timing_pair("mut-width-4", oi + 601)
    begin
      source_mut_op(op, source_invalid_pair[0], "15")
    rescue error
      source_error = error.to_s()
    c_error = nil
    c_invalid_pair = build_mut_timing_pair("mut-width-4", oi + 601)
    begin
      c_mut_op(op, c_invalid_pair[0], "15")
    rescue error
      c_error = error.to_s()
    if source_error == nil || c_error == nil
      fail_check(op + "/compound-string-policy", "invalid String did not raise in both lanes")
    if source_error != c_error
      fail_check(op + "/compound-string-policy", "source/C error text differs")
    checks += 2
    oi += 1

  # Consumed identities return the owned receiver itself. They must not apply
  # the immutable alias handoff (which marks a heap BigInt shared), otherwise
  # the next eligible consumed call silently loses receiver reuse.
  identity_value = make_width_value(4, 7103)
  identity_expected = make_width_value(4, 7103)
  identity_value = source_and_mut(identity_value, -1)
  identity_value = source_or_mut(identity_value, 0)
  identity_value = source_xor_mut(identity_value, 0)
  identity_value = source_and_mut(identity_value, identity_value)
  check_exact("compound-identity-chain/value", identity_value, identity_expected)
  if ccall("w_bigint_shared_value", identity_value)
    fail_check("compound-identity-chain/ownership", "consumed identity marked the receiver shared")
  reuse_rhs = make_width_value(4, 7207)
  if !ccall("w_bitwise_gate_source_and_reused_receiver", identity_value, reuse_rhs)
    fail_check("compound-identity-chain/reuse", "subsequent eligible source mutation did not reuse receiver storage")
  checks += 3

  # A deterministic 12,288-case source/C sweep varies both widths
  # independently, all four sign pairs, both negative encodings, operand
  # order, identities, distinct-equal storage, sparse high limbs, and inline
  # operands.  The fixed matrix above separately reaches the 4095/4096/4097
  # and 8192-limb acceptance boundaries.
  widths = [1, 2, 3, 4, 5, 8, 16, 31, 48, 64, 127, 257]
  oi = 0
  while oi < ops.size()
    op = ops[oi]
    d = 0
    while d < 4096
      aw = widths[d % widths.size()]
      bw = widths[(d * 7 + 3) % widths.size()]
      a = make_width_value(aw, d * 17 + 4001)
      b = make_width_value(bw, d * 29 + 5003)
      if (d & 1) != 0
        a = make_negative(a, (d & 4) != 0, "differential/a/" + d.to_s())
      if (d & 2) != 0
        b = make_negative(b, (d & 8) != 0, "differential/b/" + d.to_s())
      if d % 31 == 0
        b = a
      elsif d % 37 == 0
        b = distinct_equal(a, "differential/equal/" + d.to_s())
      elsif d % 41 == 0
        b = d % 2001 - 1000
      expected = c_op(op, a, b)
      check_exact(op + "/differential/" + d.to_s(), source_op(op, a, b), expected)
      if d % 8 == 0
        check_exact(op + "/differential-reverse/" + d.to_s(), source_op(op, b, a), c_op(op, b, a))
      if d % 64 == 0
        check_exact(op + "/differential-public/" + d.to_s(), public_op(op, a, b), expected)
      checks += 1
      d += 1
    oi += 1
  full = ccall("w_bitwise_gate_source_complete") ? "full" : "baseline-partial"
  << "correctness: ok (" + checks.to_s() + " exact checks; seam=" + full + "; partial_rows=" + partial_rows.to_s() + "; c_controls=" + control_rows.to_s() + ")"

-> time_and_source(left, right, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += consume_low_byte(source_and(left[k], right[k]))
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_and_c(left, right, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += consume_low_byte(c_and(left[k], right[k]))
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_or_source(left, right, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += consume_low_byte(source_or(left[k], right[k]))
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_or_c(left, right, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += consume_low_byte(c_or(left[k], right[k]))
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_xor_source(left, right, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += consume_low_byte(source_xor(left[k], right[k]))
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_xor_c(left, right, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += consume_low_byte(c_xor(left[k], right[k]))
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_and_source_baseline(left, right, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += consume_low_byte(baseline_and(left[k], right[k]))
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_or_source_baseline(left, right, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += consume_low_byte(baseline_or(left[k], right[k]))
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_xor_source_baseline(left, right, iters)
  checksum = 0
  i = 0
  started = thread_cpu_ns()
  while i < iters
    k = i & CORPUS_MASK
    checksum += consume_low_byte(baseline_xor(left[k], right[k]))
    i += 1
  [thread_cpu_ns() - started, checksum]

-> time_and_mut_source(receiver, argument, iters)
  i = 0
  result = receiver
  started = thread_cpu_ns()
  while i < iters
    result = source_and_mut(result, argument)
    i += 1
  elapsed = thread_cpu_ns() - started
  [elapsed, peek_low_byte(result)]

-> time_and_mut_c(receiver, argument, iters)
  i = 0
  result = receiver
  started = thread_cpu_ns()
  while i < iters
    result = c_and_mut(result, argument)
    i += 1
  elapsed = thread_cpu_ns() - started
  [elapsed, peek_low_byte(result)]

-> time_or_mut_source(receiver, argument, iters)
  i = 0
  result = receiver
  started = thread_cpu_ns()
  while i < iters
    result = source_or_mut(result, argument)
    i += 1
  elapsed = thread_cpu_ns() - started
  [elapsed, peek_low_byte(result)]

-> time_or_mut_c(receiver, argument, iters)
  i = 0
  result = receiver
  started = thread_cpu_ns()
  while i < iters
    result = c_or_mut(result, argument)
    i += 1
  elapsed = thread_cpu_ns() - started
  [elapsed, peek_low_byte(result)]

-> time_xor_mut_source(receiver, argument, iters)
  i = 0
  result = receiver
  started = thread_cpu_ns()
  while i < iters
    result = source_xor_mut(result, argument)
    i += 1
  elapsed = thread_cpu_ns() - started
  [elapsed, peek_low_byte(result)]

-> time_xor_mut_c(receiver, argument, iters)
  i = 0
  result = receiver
  started = thread_cpu_ns()
  while i < iters
    result = c_xor_mut(result, argument)
    i += 1
  elapsed = thread_cpu_ns() - started
  [elapsed, peek_low_byte(result)]

-> time_mut_lane(lane, op, receiver, argument, iters)
  if op == "and"
    return lane == "c" ? time_and_mut_c(receiver, argument, iters) : time_and_mut_source(receiver, argument, iters)
  if op == "or"
    return lane == "c" ? time_or_mut_c(receiver, argument, iters) : time_or_mut_source(receiver, argument, iters)
  lane == "c" ? time_xor_mut_c(receiver, argument, iters) : time_xor_mut_source(receiver, argument, iters)

-> time_lane(lane, op, left, right, iters)
  if op == "and"
    if lane == "c"
      return time_and_c(left, right, iters)
    return source_complete?() ? time_and_source(left, right, iters) : time_and_source_baseline(left, right, iters)
  if op == "or"
    if lane == "c"
      return time_or_c(left, right, iters)
    return source_complete?() ? time_or_source(left, right, iters) : time_or_source_baseline(left, right, iters)
  if lane == "c"
    return time_xor_c(left, right, iters)
  source_complete?() ? time_xor_source(left, right, iters) : time_xor_source_baseline(left, right, iters)

-> run_bench(lane, op, stratum, iters, warmup)
  if stratum.starts_with?("mut-width-")
    warm_pair = build_mut_timing_pair(stratum, 701)
    time_mut_lane(lane, op, warm_pair[0], warm_pair[1], warmup)
    pair = build_mut_timing_pair(stratum, 701)
    kind = ccall("w_bitwise_gate_mut_lane_kind", pair[0], pair[1])
    result = time_mut_lane(lane, op, pair[0], pair[1], iters)
    << "RESULT|" + op + "/" + stratum + "|" + result[0].to_s() + "|" + iters.to_s() + "|" + result[1].to_s() + "|" + kind.to_s()
    return
  pair = build_pairs(op, stratum)
  time_lane(lane, op, pair[0], pair[1], warmup)
  result = time_lane(lane, op, pair[0], pair[1], iters)
  kind = ccall("w_bitwise_gate_lane_kind", pair[0][0], pair[1][0])
  << "RESULT|" + op + "/" + stratum + "|" + result[0].to_s() + "|" + iters.to_s() + "|" + result[1].to_s() + "|" + kind.to_s()

args_v = argv()
mode = args_v.size() > 0 ? args_v[0] : "check"
if mode == "check"
  run_correctness()
  exit(0)
if mode == "seams"
  full = ccall("w_bitwise_gate_source_complete") ? 1 : 0
  << "SEAMS|full|" + full.to_s()
  exit(0)
if mode != "bench"
  << "mode must be check, seams, or bench"
  exit(2)

lane = args_v.size() > 1 ? args_v[1] : "source"
op = args_v.size() > 2 ? args_v[2] : "and"
stratum = args_v.size() > 3 ? args_v[3] : "width-4"
iters = args_v.size() > 4 ? args_v[4].to_i() : 1_000_000
warmup = args_v.size() > 5 ? args_v[5].to_i() : iters / 10
if !(lane in ("c" "source")) || !(op in ("and" "or" "xor")) || iters <= 0 || warmup < 0
  << "invalid bench arguments"
  exit(2)
run_bench(lane, op, stratum, iters, warmup)
