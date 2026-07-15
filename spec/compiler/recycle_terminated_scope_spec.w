# Regression coverage for path-local `## recycle` cleanup. A control transfer
# must recycle every lexical scope it abandons, exactly once, while compilation
# of a terminated branch must restore the scope stack before a sibling path is
# lowered. `scripts/test-recycle-terminated-scope-wire.sh` pins the WIRE shape;
# this file pins observable return/break/next/raise behavior.

-> check_recycle_scope(name, got, want)
  if got != want
    << "FAIL recycle terminated scope " + name + " got=" + got.to_s() + " want=" + want.to_s()
    exit(1)
  << "PASS recycle terminated scope " + name

-> recycle_scope_return(flag)
  if flag
    outer = [] ## recycle
    outer.push(10)
    if outer$size == 1
      inner = {} ## recycle
      inner["value"] = 32
      return inner["value"] + outer[0]
  -1

# A later function-body allocation must not be retroactively injected before
# an earlier return in a sibling CFG path: the allocation temp does not
# dominate that return, and no cleanup entry was pushed on that path.
-> recycle_scope_return_before_sibling(early)
  if early
    return 11
  later = {} ## recycle
  later["value"] = 31
  later["value"]

-> recycle_scope_break
  i = 0
  total = 0
  while i < 4
    scratch = [] ## recycle
    scratch.push(i)
    if i == 2
      break
    total += scratch[0]
    i += 1
  total

-> recycle_scope_next
  i = 0
  total = 0
  while i < 4
    scratch = [] ## recycle
    scratch.push(i)
    i += 1
    if (i & 1) == 0
      next
    total += scratch[0]
  total

# Minimal form of the Array#uniq discovery: an earlier nested break used to
# leave an empty branch scope on the compiler stack. The later Hash was then
# tracked in that stale scope, producing cleanup_push_hash but no normal pop or
# recycle call.
-> recycle_scope_sibling(run_loop)
  if run_loop
    i = 0
    while i < 2
      if i == 1
        break
      i += 1

  sibling = {} ## recycle
  sibling["answer"] = 42
  sibling["answer"]

# w_raise performs the exceptional-path recycle. The compiler must discard the
# abandoned try/if bookkeeping without emitting a second recycle, then attach
# the rescue Hash to the rescue scope and emit its one normal cleanup pair.
-> recycle_scope_exception(do_raise)
  result = 0
  begin
    trial = [] ## recycle
    trial.push(5)
    if do_raise
      raise "recycle scope probe"
    result += trial[0]
  rescue error
    recovered = {} ## recycle
    recovered["value"] = 7
    result += recovered["value"]
  result

# A double recycle leaves the same pointer in a pool twice. Two simultaneous
# checkouts would then alias; keep both live through the comparison so the
# check catches duplicated normal/exception cleanup.
-> recycle_array_pair_distinct
  first = [] ## recycle
  second = [] ## recycle
  wvalue_bits(first) != wvalue_bits(second)

-> recycle_hash_pair_distinct
  first = {} ## recycle
  second = {} ## recycle
  wvalue_bits(first) != wvalue_bits(second)

check_recycle_scope("return taken", recycle_scope_return(true), 42)
check_recycle_scope("return sibling", recycle_scope_return(false), -1)
check_recycle_scope("return before sibling", recycle_scope_return_before_sibling(true), 11)
check_recycle_scope("late sibling allocation", recycle_scope_return_before_sibling(false), 31)
check_recycle_scope("break", recycle_scope_break(), 1)
check_recycle_scope("next", recycle_scope_next(), 2)
check_recycle_scope("sibling after break", recycle_scope_sibling(true), 42)
check_recycle_scope("sibling without break", recycle_scope_sibling(false), 42)
check_recycle_scope("exception raise", recycle_scope_exception(true), 7)
check_recycle_scope("exception normal", recycle_scope_exception(false), 5)

# Seed each transfer/exception route repeatedly before probing for duplicated
# pool entries. One correct recycle per call keeps a pool cardinality of one;
# any double recycle makes the two live acquisitions alias.
probe_i = 0
while probe_i < 8
  recycle_scope_return(true)
  recycle_scope_break()
  recycle_scope_next()
  recycle_scope_sibling(true)
  recycle_scope_exception(true)
  probe_i += 1
check_recycle_scope("array pool no double recycle", recycle_array_pair_distinct(), true)
check_recycle_scope("hash pool no double recycle", recycle_hash_pair_distinct(), true)

<< "recycle_terminated_scope_spec: all checks passed"
