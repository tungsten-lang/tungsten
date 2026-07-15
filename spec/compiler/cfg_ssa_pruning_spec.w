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

<< "PASS cfg ssa pruning"
