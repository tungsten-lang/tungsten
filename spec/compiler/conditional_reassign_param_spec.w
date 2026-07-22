# Conditional annotated reassign of an existing boxed variable (param or
# boxed local) must not retype it to a raw machine slot — one branch would
# hold raw bits while the other holds the boxed WValue, corrupting
# post-merge reads and the function's inferred return type (NaN-box tag
# junk at call boundaries). Fixed 2026-07-22 (round-3 bug 1): the annotated
# RHS still computes raw with wrapping semantics; the result is boxed back
# into the variable's existing representation.
#
# Run: `bin/tungsten -o /tmp/crp spec/compiler/conditional_reassign_param_spec.w && /tmp/crp`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> emit(buf, pos, v)
  if v < 0
    buf[pos] = 45
    pos = pos + 1 ## i64
  buf[pos] = 48
  pos + 1

-> via_caller(buf, pos, v)
  pos = emit(buf, pos, v)
  pos

-> wrap_reassign(x, big)
  if big
    x = (x * 18446744073709551615) ## u64
  x

-> loop_reassign(pos, n)
  i = 0 ## i64
  while i < n
    if i % 2 == 0
      pos = pos + 1 ## i64
    i += 1
  pos

b = u8[64]
check("reassign.branch_untaken", via_caller(b, 0, 12), 1)
check("reassign.branch_taken", via_caller(b, 0, 0 - 3), 2)
check("reassign.buf_cell0", b[0], 45)
check("reassign.buf_cell1", b[1], 48)
check("reassign.top_level_call", emit(b, 0, 12), 1)
check("reassign.wrap_untouched", wrap_reassign(7, false), 7)
check("reassign.wrap_semantics_kept", wrap_reassign(7, true).to_s(), "18446744073709551609")
check("reassign.loop_conditional", loop_reassign(100, 10), 105)
