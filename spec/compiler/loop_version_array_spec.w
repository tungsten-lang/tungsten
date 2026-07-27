# Loop versioning for untyped-array element loops (lowering/analysis.w
# loop_version_spec → control_flow.w lower_while_versioned). Qualifying
# `while i < a.size` / `while i < n` loops lower twice behind a runtime
# guard: a fast arm with the array retyped :typed_array_w64 (unchecked
# inline slots access; ~33x on read reductions) and the original checked
# arm. This spec pins BOTH arms' semantics and the guard boundaries.
# Values verified against the unversioned compiler (HEAD differential).
#
# Run: `bin/tungsten -o /tmp/lva spec/compiler/loop_version_array_spec.w && /tmp/lva`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# fast arm: read+write mixed with control flow and break
-> mixed
  a = []
  j = 0 ## i64
  while j < 100
    a.push(j * 3)
    j = j + 1
  s = 0 ## i64
  i = 0 ## i64
  while i < a.size
    if i > 90
      break
    if a[i] > 200
      s = s + a[i]
    else
      s = s - 1
    a[i] = s
    i = i + 1
  s + a[50]
check("lv.mixed_rw_break", mixed, 5534)

# fast arm: var bound with nonzero start and step 2
-> stepped
  a = []
  j = 0 ## i64
  while j < 64
    a.push(j)
    j = j + 1
  n = 50 ## i64
  s = 0 ## i64
  i = 4 ## i64
  while i < n
    s = s + a[i]
    i = i + 2
  s
check("lv.var_bound_step2", stepped, 598)

# guard FAILS (n > size): slow path keeps grow-on-write semantics
-> grow
  a = []
  a.push(7)
  n = 5 ## i64
  i = 0 ## i64
  while i < n
    a[i] = i * 11
    i = i + 1
  a.size * 1000 + a[4]
check("lv.guard_fail_grow", grow, 5044)

# guard FAILS (negative start): slow path keeps negative-index wrap
-> negstart
  a = []
  j = 0 ## i64
  while j < 10
    a.push(j + 100)
    j = j + 1
  s = 0 ## i64
  i = 0 - 2 ## i64
  while i < a.size
    s = s + a[i]
    i = i + 1
  s
check("lv.guard_fail_negative_start", negstart, 1262)

# w64-store contract: values written in the fast arm read back boxed
-> writeback
  a = []
  j = 0 ## i64
  while j < 1024
    a.push(0)
    j = j + 1
  r = 0 ## i64
  while r < 3
    i = 0 ## i64
    while i < a.size
      a[i] = i + r
      i = i + 1
    r = r + 1
  a[1023]
check("lv.w64_store_boxed", writeback, 1025)
