# Stack-promoted small typed arrays must never escape their frame.
#
# `i64[N]` with N <= 255 and a packable element type is promoted to an LLVM
# `alloca` when the local provably does not escape (lowering/monomorphize.w,
# mark_stackable_typed_arrays). The escape predicate used to walk with
# ast_children, which keeps only values satisfying is_ast_node? — so nested
# child-lists (hash_literal `entries`, if `elsif_clauses`: W_PACKED_BODY refs
# that `type()` reports as "Array") were dropped wholesale, and a bare `e` in
# statement/implicit-return position was never inspected at all. Result:
# `{ "arr": e }` and `-> f \n e = i64[1] \n e` promoted to the stack, boxed the
# alloca pointer, and handed a dangling pointer to the caller — SIGSEGV once
# the frame was reused, or silent garbage (w_check_array_ebits reporting 168,
# then 80, then 96 across runs, which is what broke wassat's raw kernel path).
#
# Every maker below leaks its array by a different route; `churn` then stamps
# -1 over the vacated frames before anything is read back. Correct behaviour:
# the arrays are heap-allocated, so the writes survive, the untouched slots
# are still 0, and the native-signature call sees the same memory.
#
# Run: `bin/tungsten -o /tmp/sase spec/compiler/small_array_stack_escape_spec.w && /tmp/sase`

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

# Native typed signature — the boundary that segfaulted on a dangling box.
-> takes_i64(a, n) (i64[] i64) i64
  a[0]

# Escape 1: stored into a hash literal that is returned (nested child-list —
# invisible to an ast_children walk).
-> make_hash
  e = i64[4]
  e[0] = 11
  { "arr": e, "n": 4 }

# Escape 2: stored into an array literal that is returned.
-> make_arr
  e = i64[4]
  e[1] = 22
  [e]

# Escape 3: bare implicit return (the node itself is the var).
-> make_ret
  e = i64[4]
  e[2] = 33
  e

# Escape 4: explicit `return`.
-> make_explicit_ret
  e = i64[4]
  e[3] = 44
  return e

# Escape 5: aliased through another local, then returned.
-> make_alias
  e = i64[4]
  e[0] = 55
  x = e
  x

# Escape 6: hidden inside an elsif clause (the other nested child-list).
-> make_elsif(k)
  e = i64[4]
  e[1] = 66
  if k == 0
    0
  elsif k == 1
    e
  else
    0

# Escape 7: captured by a closure that outlives the frame.
-> make_closure
  e = i64[4]
  e[2] = 77
  -> () e[2]

# Not an escape: purely local use still gets the stack, and must behave.
-> stays_local
  e = i64[8]
  i = 0
  while i < 8
    e[i] = i * 3
    i += 1
  s = 0
  i = 0
  while i < 8
    s += e[i]
    i += 1
  s

# Overwrite the frames the makers just vacated.
-> churn(n)
  buf = i64[32]
  i = 0
  while i < 32
    buf[i] = 0 - 1
    i += 1
  if n > 0
    churn(n - 1)
  buf[0]

h = make_hash
a = make_arr
r = make_ret
er = make_explicit_ret
al = make_alias
el = make_elsif(1)
cl = make_closure
churn(40)

ha = h["arr"]
check("escape.hash_write_survives", ha[0] == 11)
check("escape.hash_rest_zeroed", ha[1] == 0 && ha[2] == 0 && ha[3] == 0)
check("escape.hash_native_signature", takes_i64(ha, 4) == 11)

aa = a[0]
check("escape.array_literal", aa[1] == 22)
check("escape.implicit_return", r[2] == 33)
check("escape.explicit_return", er[3] == 44)
check("escape.alias_local", al[0] == 55)
check("escape.elsif_branch", el[1] == 66)
check("escape.closure_capture", cl.call == 77)

check("local.not_escaping_still_correct", stays_local == 84)
