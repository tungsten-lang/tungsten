# spec: compiled
# Regression coverage for the conservative mem2reg phi-pruning pass.
# `merged` is assigned on both sides of a branch and therefore must remain in
# memory until liveness-pruned phi insertion exists. `straight` has one
# dominating definition and should still promote; its use after the join also
# exercises function-wide rewriting of an eliminated load.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit(1)

-> mixed_phi_and_straight(flag) (i64) i64
  merged = 10
  straight = 7
  if flag > 0
    merged = 20
  else
    merged = 30
  merged + straight

check("mixed phi true branch", mixed_phi_and_straight(1), 27)
check("mixed phi false branch", mixed_phi_and_straight(0), 37)

# The CFG eligibility precheck must also leave functions with no variable
# slots alone; CFG/dominator construction exists only to support mem2reg.
-> no_local_constant
  42

check("no-local function", no_local_constant(), 42)

# Dominating double/float/i128 variable slots should also be promoted across
# blocks by mem2reg while merged slots stay in memory.
-> mixed_double_phi_and_straight(flag, x) (i64 f64) f64
  merged = ~1.5
  straight = x * ~2.0
  if flag > 0
    merged = ~2.5
  else
    merged = ~3.5
  merged + straight

check("mixed double phi true branch", mixed_double_phi_and_straight(1, ~4.0), ~10.5)
check("mixed double phi false branch", mixed_double_phi_and_straight(0, ~4.0), ~11.5)

-> mixed_float_phi_and_straight(flag) (i64) f64
  x = ~4.0 ## f32
  merged = (x + ~1.0) ## f32
  straight = (x * ~2.0) ## f32
  if flag > 0
    merged = (x + ~2.0) ## f32
  else
    merged = (x + ~3.0) ## f32
  merged + straight

check("mixed float phi true branch", mixed_float_phi_and_straight(1), ~14.0)
check("mixed float phi false branch", mixed_float_phi_and_straight(0), ~15.0)

-> mixed_i128_phi_and_straight(flag) (i64) i64
  x = 5 ## i128
  merged = (x + 1) ## i128
  straight = (x * 3) ## i128
  if flag > 0
    merged = (x + 10) ## i128
  else
    merged = (x + 20) ## i128
  merged + straight

check("mixed i128 phi true branch", mixed_i128_phi_and_straight(1), 30)
check("mixed i128 phi false branch", mixed_i128_phi_and_straight(0), 40)

# Branch-local variables (not live-in at the join block) have their join phis
# pruned by live-in liveness and are promoted to SSA registers.
-> branch_local_pruned_phi(flag, x) (i64 i64) i64
  res = x
  if flag > 0
    branch_only = x * 3 + 1
    res = branch_only + 2
  else
    other_only = x * 5 + 1
    res = other_only + 4
  res

check("branch local pruned phi true", branch_local_pruned_phi(1, 10), 33)
check("branch local pruned phi false", branch_local_pruned_phi(0, 10), 55)

<< "PASS cfg ssa pruning"
