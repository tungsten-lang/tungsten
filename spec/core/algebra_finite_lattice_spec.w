# Finite lattices and Knaster-Tarski fixpoint regressions.
# Run in both engines:
#   bin/tungsten run spec/core/algebra_finite_lattice_spec.w
#   bin/tungsten compile spec/core/algebra_finite_lattice_spec.w \
#     --out /tmp/algebra-finite-lattice-spec

use algebra

-> lattice_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

# --- the divisor lattice of 60: meet is gcd, join is lcm ---

divisors = FiniteLattice.divisors(60)
lattice_check("divisors.size", divisors.size == 12)
lattice_check("divisors.bottom", divisors.bottom == 1)
lattice_check("divisors.top", divisors.top == 60)
lattice_check("divisors.meet_is_gcd", divisors.meet(12, 10) == 2)
lattice_check("divisors.join_is_lcm", divisors.join(4, 6) == 12)
lattice_check("divisors.leq", divisors.leq?(5, 15))
lattice_check("divisors.not_leq", !divisors.leq?(4, 6))
# 60 = 2 * 2 * 3 * 5 has four prime factors with multiplicity.
lattice_check("divisors.height", divisors.height == 5)

# join with a constant is monotone; its least fixpoint is the constant.
lift = ->(x) divisors.join(x, 4)
lattice_check("divisors.lift_monotone", divisors.monotone?(lift))
lattice_check("divisors.lfp", divisors.least_fixpoint(lift) == 4)
lattice_check("divisors.gfp", divisors.greatest_fixpoint(lift) == 60)

# --- chains ---

chain = FiniteLattice.chain(5)
lattice_check("chain.bottom", chain.bottom == 0)
lattice_check("chain.top", chain.top == 4)
lattice_check("chain.height", chain.height == 5)
lattice_check("chain.meet_is_min", chain.meet(1, 3) == 1)
lattice_check("chain.join_is_max", chain.join(1, 3) == 3)

# --- the powerset of {1, 2, 3} under inclusion ---

sets = FiniteLattice.powerset([1, 2, 3])
lattice_check("powerset.size", sets.size == 8)
lattice_check("powerset.bottom", sets.bottom == [])
lattice_check("powerset.top", sets.top == [1, 2, 3])
lattice_check("powerset.height", sets.height == 4)
lattice_check("powerset.meet_is_intersection", sets.meet([1, 2], [2, 3]) == [2])
lattice_check("powerset.join_is_union", sets.join([1], [3]) == [1, 3])

# Reachability closure for 1 -> 2 -> 3 seeded at 1: the least fixpoint of a
# monotone step is the closure, reached by iterating from the empty set.
step = ->(s)
  keep = []
  [1, 2, 3].each ->(x)
    inside = s.include?(x)
    inside = true if x == 1
    inside = true if x == 2 && s.include?(1)
    inside = true if x == 3 && s.include?(2)
    keep.push(x) if inside
  keep
lattice_check("closure.monotone", sets.monotone?(step))
lattice_check("closure.lfp", sets.least_fixpoint(step) == [1, 2, 3])

# Knaster-Tarski's construction: the least fixpoint is the meet of the
# prefixpoints and the greatest fixpoint is the join of the postfixpoints.
meet_all = sets.top
sets.prefixpoints(step).each ->(s)
  meet_all = sets.meet(meet_all, s)
lattice_check("closure.tarski_meet", meet_all == sets.least_fixpoint(step))
join_all = sets.bottom
sets.postfixpoints(step).each ->(s)
  join_all = sets.join(join_all, s)
lattice_check("closure.tarski_join", join_all == sets.greatest_fixpoint(step))

# --- the fixpoint lattice of a monotone map is again a lattice ---

# prune keeps 1 and 2, and keeps 3 exactly when 2 is present. Its fixpoints
# are [], [1], [2, 3], [1, 2, 3] — a lattice, but not a sublattice: the
# ambient join of [1] and [2, 3] is already the top.
prune = ->(s)
  keep = []
  [1, 2, 3].each ->(x)
    inside = false
    inside = true if x <= 2 && s.include?(x)
    inside = true if x == 3 && s.include?(2)
    keep.push(x) if inside
  keep
fixed = sets.fixpoint_lattice(prune)
lattice_check("fixpoints.size", fixed.size == 4)
lattice_check("fixpoints.bottom", fixed.bottom == [])
lattice_check("fixpoints.top", fixed.top == [1, 2, 3])
lattice_check("fixpoints.join", fixed.join([1], [2, 3]) == [1, 2, 3])
lattice_check("fixpoints.lfp_is_bottom",
              sets.least_fixpoint(prune) == fixed.bottom)
lattice_check("fixpoints.gfp_is_top",
              sets.greatest_fixpoint(prune) == fixed.top)

# --- failure modes are loud ---

flip = ->(x) 4 - x
lattice_check("chain.flip_not_monotone", !chain.monotone?(flip))
flip_failed = false
begin
  chain.least_fixpoint(flip)
rescue error
  flip_failed = error.to_s.include?("monotone")
lattice_check("chain.flip_is_loud", flip_failed)

escape = ->(x) x + 100
escape_failed = false
begin
  chain.least_fixpoint(escape)
rescue error
  escape_failed = error.to_s.include?("outside")
lattice_check("chain.escape_is_loud", escape_failed)

antichain_failed = false
begin
  FiniteLattice.new([1, 2], ->(a, b) a == b)
rescue error
  antichain_failed = error.to_s.include?("not a lattice")
lattice_check("antichain.is_loud", antichain_failed)

<< "algebra_finite_lattice_spec: all checks passed"
