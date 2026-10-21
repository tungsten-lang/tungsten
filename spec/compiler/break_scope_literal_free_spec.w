# spec: compiled -- free insertion (ownership.w scope tracking)
# Free insertion versus a scope that ends in `break` (ownership_analyze).
#
# A branch that ends in break/next/return/raise emits no scope_pop, and the
# analysis used to pair pops with pushes by stack position. The `while`
# body's pop then closed the breaking `if` scope, the loop scope stayed open,
# and a heap literal born after the loop (here a string array, inside an
# enclosing elsif) was released at the loop body's pop, before it existed:
# LLVM rejected the module with "Instruction does not dominate all uses".
# Pops are now matched to their push by id. This spec must compile and run;
# it checks the values so a wrong release would surface as a bad result.
#
# Run: `bin/tungsten -o /tmp/bslf spec/compiler/break_scope_literal_free_spec.w && /tmp/bslf`

-> check(name, got, want)
  if got.to_s() == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want
    exit 1

# Top level, as in the original report: the loop and the literal sit in one
# elsif branch of the script.
mode = argv().size > 5 ? argv()[5] : "dfs"
k = 2
status = "unset"
if mode == "detour"
  status = "detour"
elsif mode == "dfs"
  n = 0
  while true
    n += 1
    if n > 3
      break
  status = ["done", "frontier-cap", "time", "stuck", "key-mismatch", "chunk"][k]
else
  raise "unknown mode " + mode
check("elsif.literal_after_break_loop", status, "time")

# The same shape inside a function, with `next` as well as `break`.
-> label(c, k)
  out = "none"
  if c
    n = 0
    while true
      n += 1
      if n % 2 == 0
        next
      if n > k
        break
    out = ["even", "odd", "big"][k] + " " + n.to_s()
  out

check("fn.literal_after_break_loop", label(true, 2), "big 3")
check("fn.branch_not_taken", label(false, 2), "none")

# A `return` inside the loop leaves the scopes open on that path too.
-> first_over(values, limit)
  if values.size() > 0
    i = 0
    while i < values.size()
      if values[i] > limit
        return values[i]
      i += 1
    tags = ["none", "found"]
    return tags[0]
  "empty"

check("fn.literal_after_return_loop", first_over([1, 2, 3], 9), "none")
check("fn.return_taken", first_over([1, 20, 3], 9), "20")
