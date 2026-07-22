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

# Round-4 (2026-07-22): UNCONDITIONAL param reassign chains over values past
# 2^48 must NOT truncate. The round-3 guard boxed the raw result back but
# stamped :int, so later machine reads went through the 48-bit nanunbox
# shortcut and lost the high bits — xorshift64* through a param returned
# garbage while an identical chain through a fresh local was exact. The fix
# stamps :bigint so reads take the full-width unbox. Values are the
# xorshift64* reference (independent oracle).

-> xs_param(x)
  x = x ^ (x >> 12) ## u64
  x = x ^ (x << 25) ## u64
  x = x ^ (x >> 27) ## u64
  x

-> xs_hoisted(x)
  y = x ## u64
  y = y ^ (y >> 12) ## u64
  y = y ^ (y << 25) ## u64
  y = y ^ (y >> 27) ## u64
  y

-> xs_partial_then_read(x)
  x = x ^ (x >> 12) ## u64
  mid = x + 0
  x = x ^ (x << 25) ## u64
  x = x ^ (x >> 27) ## u64
  mid

check("reassign.param_chain_big", xs_param(88172645463325252).to_s(), "3656804824253551335")
check("reassign.hoisted_local_twin", xs_hoisted(88172645463325252).to_s(), "3656804824253551335")
check("reassign.param_chain_matches_hoist",
      xs_param(88172645463325252), xs_hoisted(88172645463325252))
check("reassign.param_used_mid_chain", xs_partial_then_read(88172645463325252).to_s(),
      "88193037827817907")
check("reassign.param_chain_small", xs_param(12345), 414263032884)
