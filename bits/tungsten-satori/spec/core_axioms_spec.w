# Soundness smoke test for the foundational axioms.
#
# Every axiom loaded by the prelude in foundational mode is instantiated many
# times with random literals (ℕ, ℤ, ℚ, ℝ values chosen to hit zero, negatives,
# and division/mod edge cases) and evaluated by the kernel. An axiom that ever
# evaluates to ⊥ contradicts the evaluator's literal semantics. That would make
# the system inconsistent, so the spec fails loudly.
#
#   cd ~/tungsten && bin/tungsten bits/tungsten-satori/spec/core_axioms_spec.w

use ../lib/satori

+ Lcg
  -> new(@s)
  -> pick(n)
    @s = (@s * 48271) % 2147483647
    @s % n

-> random_literal(ty, rng)
  case ty.name
  when "nat"
    vals = [0, 1, 2, 3, 5, 7, 10, 12, 100, 9223372036854775000]
    mk_nat(vals[rng.pick(vals.size)])
  when "int"
    vals = [0, 1, -1, 2, -2, 3, -7, 10, -12, 100]
    mk_lit(vals[rng.pick(vals.size)], ty_int)
  when "rat", "real"
    nums = [0, 1, -1, 2, -3, 5, 7, -10]
    dens = [1, 2, 3, 7]
    mk_lit(q_make(nums[rng.pick(nums.size)], dens[rng.pick(dens.size)]), ty)
  else
    nil

# Strip leading ∀ over numeric types, substituting random literals.
-> instantiate_random(p, rng, small)
  t = p
  while true
    q = dest_unop(t, "∀")
    if q == nil || q.tag != :lam
      return t
    lit = random_literal(q.ty, rng)
    if small && q.ty.name == "nat"
      lit = mk_nat(rng.pick(6))
    if lit == nil
      return nil
    t = tm_instantiate(q.b, lit, 0)

-> run_spec
  s = Session.new(Dir.pwd)
  s.quiet = true
  s.load_prelude
  k = s.k
  rng = Lcg.new(12345)
  names = k.foundational.keys.sort
  checked = 0
  bad = 0
  skipped = 0
  names.each -> (nm)
    ax = k.axioms[nm]
    trial = 0
    while trial < 25
      t = instantiate_random(ax.concl, rng, tm_show(ax.concl).include?("^"))
      if t == nil
        skipped += 1
        trial = 25
      else
        v = dest_binop(k.compute(t).concl, "=")[1]
        if is_const?(v, "⊥")
          << "✗ axiom " + nm + " is FALSE at: " + tm_show(t)
          bad += 1
          trial = 25
        checked += 1
      trial += 1
  << "core axioms: [names.size] foundational, [checked] random instances evaluated, [skipped] non-numeric skipped, [bad] contradictions"
  if bad > 0
    exit(1)

run_spec()
