# Exact finite permutation-group closure and orbit invariants.

use algebra

-> permutation_group_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

swap = FinitePermutation.new([1, 0, 2])
cycle = FinitePermutation.new([1, 2, 0])
S3 = FinitePermutationGroup.new([swap, cycle])

permutation_group_check("permutation.inverse",
                        swap.inverse.images.to_s,
                        swap.images.to_s)
permutation_group_check("permutation.order2",
                        swap.order, 2)
permutation_group_check("permutation.order3",
                        cycle.order, 3)
permutation_group_check("group.order",
                        S3.order, 6)
permutation_group_check("group.orbits",
                        S3.orbit_sizes.to_s, "\[3\]")
permutation_group_check("group.stabilizer_orbits",
                        S3.stabilizer_orbit_sizes(0).to_s,
                        "\[1, 2\]")
permutation_group_check("group.cycle_type",
                        S3.contains_cycle_lengths?([3]), true)
permutation_group_check("group.certificate",
                        S3.certificate.verified?, true)

bad = false
begin
  FinitePermutation.new([0, 0, 2])
rescue error
  bad = true
permutation_group_check("permutation.rejects_nonbijection",
                        bad, true)

limited = false
begin
  FinitePermutationGroup.new([swap, cycle], 5)
rescue error
  limited = true
permutation_group_check("group.limit_is_loud",
                        limited, true)

<< "algebra_permutation_groups_spec: all checks passed"
