# Replayable exact F2 linear algebra certificates.
#
#   bin/tungsten run spec/core/algebra_f2_linear_spec.w
#   bin/tungsten compile spec/core/algebra_f2_linear_spec.w \
#     --out /tmp/algebra-f2-linear-spec

use core/algebra/f2_linear

-> f2_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

+ ForgedF2Certificate
  -> verified?
    true

  -> certified?
    true

system = F2LinearSystem.new(4)
system.add_equation([1, 1, 0, 0], 0, "global norm")
system.add_equation([0, 1, 1, 0], 0, "local image at 2")
system.add_equation([0, 0, 1, 1], 0, "local image at 13")
solution = system.solve

f2_check("consistent", solution.consistent?, true)
f2_check("certificate", solution.certificate.verified?, true)
f2_check("rank", solution.rank, 3)
f2_check("dimension", solution.dimension, 1)
f2_check("basis.size", solution.basis.size, 1)
f2_check("basis.vector", solution.basis[0].to_s, "\[1, 1, 1, 1\]")
f2_check("contains.zero", solution.contains?([0, 0, 0, 0]), true)
f2_check("contains.generator", solution.contains?([1, 1, 1, 1]), true)
f2_check("excludes.nonmember", solution.contains?([1, 0, 0, 0]), false)

affine = F2LinearSystem.new(3)
affine.add_equation([1, 1, 0], 1)
affine.add_equation([0, 1, 1], 0)
affine_solution = affine.solve
f2_check("affine.certificate", affine_solution.certified?, true)
f2_check("affine.dimension", affine_solution.dimension, 1)
f2_check("affine.particular",
         affine_solution.particular_solution.to_s, "\[1, 0, 0\]")
f2_check("affine.particular_satisfies",
         affine_solution.contains?(affine_solution.particular_solution), true)

contradiction = F2LinearSystem.new(1)
contradiction.add_equation([1], 0)
contradiction.add_equation([1], 1)
empty = contradiction.solve
f2_check("inconsistent", empty.inconsistent?, true)
f2_check("inconsistent.certificate", empty.certified?, true)
f2_check("inconsistent.dimension", empty.dimension, -1)

reduction = F2LinearAlgebra.reduce(
  system.width, system.matrix, system.right_hand_side)
reduction["rref"][0][0] = reduction["rref"][0][0] ^ 1
tampered = F2LinearSystemCertificate.new(
  system.width, system.matrix, system.right_hand_side, reduction)
f2_check("tampered.rejected", tampered.verified?, false)

unconstrained = F2LinearSystem.new(1)
non_bit_reduction = F2LinearAlgebra.reduce(
  unconstrained.width, unconstrained.matrix, unconstrained.right_hand_side)
non_bit_reduction["particular"][0] = 2
non_bit_particular = F2LinearSystemCertificate.new(
  unconstrained.width,
  unconstrained.matrix,
  unconstrained.right_hand_side,
  non_bit_reduction)
f2_check("non_bit.particular.rejected",
         non_bit_particular.verified?, false)

forged_solution_error = false
begin
  F2LinearSolution.new(ForgedF2Certificate.new)
rescue e
  forged_solution_error = true
f2_check("forged.solution_certificate.rejected", forged_solution_error, true)

expect_error = false
begin
  F2LinearSystem.new(2).add_equation([1, 2], 0)
rescue e
  expect_error = true
f2_check("invalid.bit.rejected", expect_error, true)

<< "algebra_f2_linear_spec: all checks passed"
