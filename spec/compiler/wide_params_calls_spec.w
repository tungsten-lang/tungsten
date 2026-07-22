# Wide-arity direct functions (14+ params) that make calls must read their
# LATE params intact — pins the round-3 bug-3 report (2026-07-22), which did
# NOT reproduce on the fixed toolchain in any shape below; the corruption
# observed downstream is best explained as the conditional-reassign
# miscompile (see conditional_reassign_param_spec.w) occurring inside a wide
# function. This matrix keeps the arity paths honest either way: mixed arg
# types, Hash-subscript dispatch calls (single and repeated), call-in-arg,
# annotated locals, and a conditional late-param reassign.
#
# Note: DYNAMIC method dispatch (obj.m(...)) supports at most 8 args and
# raises loudly — that limit is intentional runtime behavior, not this bug.
#
# Run: `bin/tungsten -o /tmp/wpc spec/compiler/wide_params_calls_spec.w && /tmp/wpc`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> wide_mixed(tbl, s1, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, s2, a13)
  x = tbl[1]
  y = tbl[2]
  n = s1.size()
  m = s2.size()
  a10 + a11 + a12 + a13 + x + y + n + m

-> wide_reassign(tbl, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15)
  if a1 > 0
    a15 = a15 + 1000
  x = tbl[1]
  a13 + a14 + a15 + x

-> wide_annot(tbl, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15)
  acc = 0 ## i64
  x = tbl[1]
  acc = acc + a13 + a14 + a15
  acc + x

-> twice(v)
  v * 2

-> wide_callarg(tbl, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15)
  x = twice(tbl[1])
  a13 + a14 + a15 + x

-> wide_many_calls(tbl, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15)
  t1 = tbl[1]
  t2 = tbl[2]
  t3 = tbl[1]
  t4 = tbl[2]
  a13 + a14 + a15 + t1 + t2 + t3 + t4

h = {1 => 100, 2 => 200}
check("wide.mixed", wide_mixed(h, "abc", 1,2,3,4,5,6,7,8,9,10,11,12, "de", 13), 351)
check("wide.cond_reassign", wide_reassign(h,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15), 1142)
check("wide.annot_local", wide_annot(h,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15), 142)
check("wide.call_in_arg", wide_callarg(h,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15), 242)
check("wide.many_calls", wide_many_calls(h,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15), 642)
