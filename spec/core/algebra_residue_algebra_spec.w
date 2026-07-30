# Reduced residue algebras and primitive-idempotent certificates.

use algebra

-> residue_check(name, got, want)
  equal = got == want
  if got.class_name == "Array" && want.class_name == "Array"
    equal = got.to_s == want.to_s
  if !equal
    message = "FAIL " + name + ": got " + got.to_s
    raise message + ", want " + want.to_s
  << "PASS " + name

r = PolynomialRing.new([:x], RationalField.new)
x = r.generator(0)

sqrt5 = Algebra.order(x**2 - 5).maximal_order

inert = OrderResidueAlgebra.new(sqrt5, 2)
residue_check("inert.certified", inert.certified?, true)
residue_check("inert.dimension", inert.dimension, 2)
residue_check("inert.fixed_dimension",
              inert.frobenius_fixed_basis.size, 1)
residue_check("inert.components",
              inert.primitive_idempotents.size, 1)
residue_check("inert.local_dimension",
              inert.local_dimension(
                inert.primitive_idempotents[0]), 2)

ramified = OrderResidueAlgebra.new(sqrt5, 5)
residue_check("ramified.certified", ramified.certified?, true)
residue_check("ramified.reduced_dimension", ramified.dimension, 1)
residue_check("ramified.radical_rank_mod_p",
              ramified.quotient.kernel_dimension, 1)
residue_check("ramified.components",
              ramified.primitive_idempotents.size, 1)
residue_check("ramified.local_dimension",
              ramified.local_dimension(
                ramified.primitive_idempotents[0]), 2)

split = OrderResidueAlgebra.new(sqrt5, 11)
residue_check("split.certified", split.certified?, true)
residue_check("split.dimension", split.dimension, 2)
residue_check("split.fixed_dimension",
              split.frobenius_fixed_basis.size, 2)
residue_check("split.components",
              split.primitive_idempotents.size, 2)
split_sum = split.zero
split.primitive_idempotents.each -> (idempotent)
  split_sum = split.add(split_sum, idempotent)
residue_check("split.idempotent_sum",
              split.equal?(split_sum, split.one), true)

product_source = Algebra.product_order([
  x**2 - 5, x**2 + 1
]).maximal_order
component = product_source.component_orders[0]
split_again = OrderResidueAlgebra.new(component, 11)
residue_check("product_component.components",
              split_again.primitive_idempotents.size, 2)

<< "algebra_residue_algebra_spec: all checks passed"
